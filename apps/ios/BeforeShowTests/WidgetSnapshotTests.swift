import Foundation
import XCTest
@testable import BeforeShow

final class WidgetSnapshotTests: XCTestCase {
    private func makeShow(
        name: String = "夜航西飞",
        changeStatus: ShowChangeStatus = .scheduled,
        postponedDate: Date? = nil
    ) throws -> Show {
        let calendar = Calendar.current
        let date = calendar.date(from: DateComponents(year: 2026, month: 8, day: 9))!
        let startTime = calendar.date(from: DateComponents(hour: 19, minute: 30))!
        let show = try Show(
            name: name,
            date: date,
            startTime: startTime,
            city: "上海",
            venueName: "梅赛德斯-奔驰文化中心"
        )
        if let postponedDate {
            show.markPostponed(newDate: postponedDate)
        } else if changeStatus == .canceled {
            show.markCanceled()
        }
        return show
    }

    func testSnapshotCodableRoundTrip() throws {
        let show = try makeShow()
        let snapshot = WidgetShowSnapshot(show: show, generatedAt: Date(timeIntervalSince1970: 1_800_000_000))

        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(WidgetShowSnapshot.self, from: data)

        XCTAssertEqual(decoded, snapshot)
        XCTAssertEqual(decoded.timing.effectiveDate, show.effectiveDate)
        XCTAssertEqual(decoded.name, "夜航西飞")
        XCTAssertEqual(decoded.city, "上海")
    }

    func testTimingInitMatchesShowInit() throws {
        let now = Date()
        let calendar = Calendar.current

        let scheduled = try makeShow()
        let postponed = try makeShow(
            postponedDate: calendar.date(from: DateComponents(year: 2026, month: 9, day: 1))
        )
        let canceled = try makeShow(changeStatus: .canceled)

        for show in [scheduled, postponed, canceled] {
            let viaShow = CurrentShowTimeState(show: show, calendar: calendar, now: now)
            let viaTiming = CurrentShowTimeState(timing: show.timingFields, calendar: calendar, now: now)
            XCTAssertEqual(viaShow, viaTiming)
        }
    }

    func testAppGroupStoreWriteReadClear() throws {
        // 注入临时目录,不动开发机真实 App Group 快照
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("widget-store-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        WidgetSnapshotStore.overrideContainerURL = tempDir
        defer {
            WidgetSnapshotStore.overrideContainerURL = nil
            try? FileManager.default.removeItem(at: tempDir)
        }

        let snapshot = WidgetShowSnapshot(
            showID: UUID(),
            name: "测试现场",
            city: "北京",
            venueName: nil,
            coverImageURL: nil,
            timing: ShowTimingFields(
                date: Date(timeIntervalSince1970: 1_800_000_000),
                startTime: Date(timeIntervalSince1970: 1_800_000_000),
                endDate: nil,
                endTime: nil,
                postponedDate: nil,
                changeStatus: .scheduled
            ),
            generatedAt: Date()
        )

        WidgetSnapshotStore.write(snapshot)
        XCTAssertEqual(WidgetSnapshotStore.read(), snapshot)

        WidgetSnapshotStore.write(nil)
        XCTAssertNil(WidgetSnapshotStore.read())
    }

    /// 跨午夜但不足 24h:日历日差为 1,实际应按秒数进 near 态。
    func testRemainingSecondsCrossMidnightIsUnderOneDay() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        let now = calendar.date(from: DateComponents(year: 2026, month: 8, day: 9, hour: 23, minute: 50))!
        let showDay = calendar.date(from: DateComponents(year: 2026, month: 8, day: 10))!
        let startClock = calendar.date(from: DateComponents(year: 2001, month: 1, day: 1, hour: 0, minute: 10))!

        let timing = ShowTimingFields(
            date: showDay,
            startTime: startClock,
            endDate: nil,
            endTime: nil,
            postponedDate: nil,
            changeStatus: .scheduled
        )
        let state = CurrentShowTimeState(timing: timing, calendar: calendar, now: now)
        XCTAssertEqual(state.dayDistance, 1, "calendar day distance is still 1")

        guard let start = state.effectiveStartTime else {
            return XCTFail("expected start")
        }
        let remaining = start.timeIntervalSince(now)
        XCTAssertEqual(remaining, 20 * 60, accuracy: 1)
        XCTAssertLessThan(remaining, 86_400)
        // Widget presentation 应走 near(秒表),不是 far(1 天)
        XCTAssertEqual(Int(remaining) / 86_400, 0)
        XCTAssertGreaterThanOrEqual(Int(remaining), 0)
    }

    /// 无 endDate 且结束时刻早于开始 → 跨午夜 +1 天。
    func testEndTimeBeforeStartWithoutEndDateRollsToNextDay() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        let showDay = calendar.date(from: DateComponents(year: 2026, month: 8, day: 9))!
        let startClock = calendar.date(from: DateComponents(year: 2001, month: 1, day: 1, hour: 22, minute: 0))!
        let endClock = calendar.date(from: DateComponents(year: 2001, month: 1, day: 1, hour: 1, minute: 30))!

        let timing = ShowTimingFields(
            date: showDay,
            startTime: startClock,
            endDate: nil,
            endTime: endClock,
            postponedDate: nil,
            changeStatus: .scheduled
        )
        let state = CurrentShowTimeState(timing: timing, calendar: calendar, now: showDay)
        guard let start = state.effectiveStartTime, let end = state.endBoundary else {
            return XCTFail("expected start and end")
        }
        XCTAssertEqual(end.timeIntervalSince(start), (3 * 3_600) + (30 * 60), accuracy: 1)
    }

    /// Live Activity 最早启动点 = 谢幕前 8h(默认 4h 演出 → 开场前 4h)。
    func testLiveActivityEarliestStartRespectsEightHourCap() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        let showDay = calendar.date(from: DateComponents(year: 2026, month: 8, day: 9))!
        let startClock = calendar.date(from: DateComponents(year: 2001, month: 1, day: 1, hour: 20, minute: 0))!
        let timing = ShowTimingFields(
            date: showDay,
            startTime: startClock,
            endDate: nil,
            endTime: nil,
            postponedDate: nil,
            changeStatus: .scheduled
        )
        let state = CurrentShowTimeState(timing: timing, calendar: calendar, now: showDay)
        guard let start = state.effectiveStartTime, let end = state.endBoundary else {
            return XCTFail("expected start/end")
        }

        let earliest = LiveActivityPlanner.earliestStart(activityEnd: end)
        // 默认 4h 演出 → 最早约开场前 4h,不是 12h
        XCTAssertEqual(earliest.timeIntervalSince(start), -4 * 3_600, accuracy: 1)
        XCTAssertEqual(end.timeIntervalSince(earliest), 8 * 3_600, accuracy: 1)
        // 旧逻辑 12h lead 会在开场前 4h 被系统掐断
        let wrongLead = start.addingTimeInterval(-12 * 3_600)
        XCTAssertLessThan(wrongLead.timeIntervalSince(earliest), 0)
    }

    /// 远期演出:timeline 最后日期必须是 12h 窗口终点,不能是 30 天后的谢幕。
    func testTimelineWindowIgnoresFarFutureBoundaries() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let farStart = now.addingTimeInterval(30 * 86_400)
        let farEnd = farStart.addingTimeInterval(4 * 3_600)
        let plan = WidgetTimelinePlanner.entryDates(
            now: now,
            startBoundary: farStart,
            endBoundary: farEnd
        )
        XCTAssertEqual(
            plan.windowEnd.timeIntervalSince(now),
            WidgetTimelinePlanner.refreshWindow,
            accuracy: 1
        )
        XCTAssertEqual(plan.dates.last, plan.windowEnd)
        XCTAssertFalse(plan.dates.contains(farStart))
        XCTAssertFalse(plan.dates.contains(farEnd))
    }

    /// 开场边界与小时点接近时,边界优先保留。
    func testTimelinePrefersBoundaryOverNearbyHourlyEntry() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        // 开场落在 now+1h 附近 30 秒内
        let start = now.addingTimeInterval(3_600 + 30)
        let plan = WidgetTimelinePlanner.entryDates(
            now: now,
            startBoundary: start,
            endBoundary: nil
        )
        XCTAssertTrue(plan.dates.contains(start))
        // 不应同时保留 now+1h 与 start(60s 去重后边界胜出)
        let hourly = now.addingTimeInterval(3_600)
        let hasBoth = plan.dates.contains(where: { abs($0.timeIntervalSince(hourly)) < 1 })
            && plan.dates.contains(where: { abs($0.timeIntervalSince(start)) < 1 })
        XCTAssertFalse(hasBoth)
    }

    func testCoverFilenameIsStablePerSourceAndDiffersAcrossURLs() {
        let a = "https://cdn.example.com/a.jpg"
        let b = "https://cdn.example.com/b.jpg"
        XCTAssertEqual(WidgetCoverCache.filename(for: a), WidgetCoverCache.filename(for: a))
        XCTAssertNotEqual(WidgetCoverCache.filename(for: a), WidgetCoverCache.filename(for: b))
        XCTAssertNil(WidgetCoverCache.cachedCoverPath(matching: nil))
        XCTAssertNil(WidgetCoverCache.cachedCoverPath(matching: a))
    }

    func testLiveActivityContentStateCarriesEditableFields() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let state = ShowLiveActivityAttributes.ContentState(
            showName: "夜航西飞",
            city: "上海",
            venueName: "梅奔",
            startDate: start,
            endDate: start.addingTimeInterval(4 * 3_600),
            coverImageFilename: "cover-abc.jpg"
        )
        let attributes = ShowLiveActivityAttributes(showID: "id-1")
        XCTAssertEqual(attributes.showID, "id-1")
        XCTAssertEqual(state.showName, "夜航西飞")
        XCTAssertEqual(state.city, "上海")

        // 延期后只换 ContentState,attributes 身份不变
        let postponed = ShowLiveActivityAttributes.ContentState(
            showName: "夜航西飞",
            city: "上海",
            venueName: "梅奔",
            startDate: start.addingTimeInterval(86_400),
            endDate: start.addingTimeInterval(86_400 + 4 * 3_600),
            coverImageFilename: "cover-abc.jpg"
        )
        XCTAssertNotEqual(state.startDate, postponed.startDate)
        XCTAssertEqual(attributes.showID, "id-1")
    }

    func testNilCityAndVenueSnapshotRoundTrip() throws {
        let snapshot = WidgetShowSnapshot(
            showID: UUID(),
            name: "纯名字",
            city: nil,
            venueName: "",
            coverImageURL: nil,
            timing: ShowTimingFields(
                date: Date(timeIntervalSince1970: 1_800_000_000),
                startTime: Date(timeIntervalSince1970: 1_800_000_000),
                endDate: nil,
                endTime: nil,
                postponedDate: nil,
                changeStatus: .scheduled
            ),
            generatedAt: Date()
        )
        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(WidgetShowSnapshot.self, from: data)
        XCTAssertNil(decoded.city)
        XCTAssertEqual(decoded.venueName, "")
        XCTAssertNil(decoded.coverImageURL)
    }

    // MARK: - Round-2 review additions

    /// generatedAt 每次同步都变;内容去重必须忽略它,否则 reload 去重失效。
    func testContentEqualIgnoresGeneratedAt() throws {
        let show = try makeShow()
        var a = WidgetShowSnapshot(show: show, generatedAt: Date(timeIntervalSince1970: 1_800_000_000))
        var b = a
        b.generatedAt = a.generatedAt.addingTimeInterval(600)

        XCTAssertTrue(a.isContentEqual(to: b))
        XCTAssertNotEqual(a, b, "generatedAt 仍参与默认 Equatable")

        b.city = "北京"
        XCTAssertFalse(a.isContentEqual(to: b))

        a.name = "改名"
        XCTAssertFalse(a.isContentEqual(to: b))
    }

    /// 开场边界距 now 不足 60s:首条 entry 必须仍是 now,边界共存紧随其后。
    func testTimelineKeepsNowEntryWhenBoundaryWithinSixtySeconds() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let start = now.addingTimeInterval(30)
        let plan = WidgetTimelinePlanner.entryDates(
            now: now,
            startBoundary: start,
            endBoundary: nil
        )
        XCTAssertEqual(plan.dates.first, now)
        XCTAssertTrue(plan.dates.contains(start))
    }

    func testLiveActivityCoverFilenameIsDistinctFromWidgetCover() {
        let source = "https://cdn.example.com/a.jpg"
        XCTAssertNotEqual(
            WidgetCoverCache.filename(for: source),
            WidgetCoverCache.liveActivityFilename(for: source)
        )
        XCTAssertEqual(
            WidgetCoverCache.liveActivityFilename(for: source),
            WidgetCoverCache.liveActivityFilename(for: source)
        )
    }

    // MARK: LiveActivityPlanner 决策(替代对 ActivityKit 真机行为的不可测断言)

    private func makePlannerSnapshot(
        start: Date,
        canceled: Bool = false
    ) -> WidgetShowSnapshot {
        let calendar = Calendar.current
        return WidgetShowSnapshot(
            showID: UUID(),
            name: "测试现场",
            city: "上海",
            venueName: "场馆",
            coverImageURL: nil,
            timing: ShowTimingFields(
                date: calendar.startOfDay(for: start),
                startTime: start,
                endDate: nil,
                endTime: nil,
                postponedDate: nil,
                changeStatus: canceled ? .canceled : .scheduled
            ),
            generatedAt: Date()
        )
    }

    /// 窗口内、无现有活动 → request;有同场活动 → update。
    func testPlannerRequestAndUpdateInsideWindow() {
        let now = Date()
        // 默认 4h 演出 → 窗口 = 开场前 4h;now+2h 在窗口内
        let snapshot = makePlannerSnapshot(start: now.addingTimeInterval(2 * 3_600))
        let showID = snapshot.showID.uuidString

        let request = LiveActivityPlanner.action(
            snapshot: snapshot, now: now, existing: [], coverFilename: nil, canSchedule: true
        )
        guard case .request = request else {
            return XCTFail("expected request, got \(request)")
        }

        let desired = LiveActivityPlanner.desiredState(snapshot: snapshot, now: now, coverFilename: nil)!
        let existing = [LiveActivityExisting(showID: showID, isPending: false, state: desired.state)]
        let update = LiveActivityPlanner.action(
            snapshot: snapshot, now: now, existing: existing, coverFilename: nil, canSchedule: true
        )
        guard case .update = update else {
            return XCTFail("expected update, got \(update)")
        }
    }

    /// 窗口外:pending 内容未变 → none(保留不重建);endDate 变了 → 重新 schedule。
    func testPlannerKeepsUnchangedPendingOutsideWindow() {
        let now = Date()
        // now+20h 开场,默认 4h 演出 → 窗口起点 = 开场前 4h = now+16h,现在在窗口外
        let snapshot = makePlannerSnapshot(start: now.addingTimeInterval(20 * 3_600))
        let showID = snapshot.showID.uuidString
        let desired = LiveActivityPlanner.desiredState(snapshot: snapshot, now: now, coverFilename: nil)!

        let unchanged = LiveActivityPlanner.action(
            snapshot: snapshot,
            now: now,
            existing: [LiveActivityExisting(showID: showID, isPending: true, state: desired.state)],
            coverFilename: nil,
            canSchedule: true
        )
        XCTAssertEqual(unchanged, .none)

        var changedState = desired.state
        changedState.endDate = desired.state.endDate?.addingTimeInterval(3_600)
        let changed = LiveActivityPlanner.action(
            snapshot: snapshot,
            now: now,
            existing: [LiveActivityExisting(showID: showID, isPending: true, state: changedState)],
            coverFilename: nil,
            canSchedule: true
        )
        guard case .schedule = changed else {
            return XCTFail("expected schedule on changed pending, got \(changed)")
        }

        // 无 schedule 能力的系统:窗口外只能结束,等窗口内打开 app
        let noSchedule = LiveActivityPlanner.action(
            snapshot: snapshot, now: now, existing: [], coverFilename: nil, canSchedule: false
        )
        XCTAssertEqual(noSchedule, .endAll)
    }

    /// 已过谢幕 / 已取消 → endAll。
    func testPlannerEndsAfterShowAndWhenCanceled() {
        let now = Date()
        // 5h 前开场,默认 4h 演出 → 谢幕已过 1h
        let past = makePlannerSnapshot(start: now.addingTimeInterval(-5 * 3_600))
        XCTAssertEqual(
            LiveActivityPlanner.action(
                snapshot: past, now: now, existing: [], coverFilename: nil, canSchedule: true
            ),
            .endAll
        )

        let canceled = makePlannerSnapshot(start: now.addingTimeInterval(2 * 3_600), canceled: true)
        XCTAssertEqual(
            LiveActivityPlanner.action(
                snapshot: canceled, now: now, existing: [], coverFilename: nil, canSchedule: true
            ),
            .endAll
        )

        XCTAssertEqual(
            LiveActivityPlanner.action(
                snapshot: nil, now: now, existing: [], coverFilename: nil, canSchedule: true
            ),
            .endAll
        )
    }
}
