import SwiftData
import XCTest
@testable import BeforeShow

final class ShowModelTests: XCTestCase {
    @MainActor
    func testShowCanBeCreatedAndStoredWithOnlyNameAndDate() throws {
        let date = Date(timeIntervalSince1970: 1_779_552_000)
        let show = try Show(
            name: "落日飞车 北京站",
            date: date,
            coverImageURL: "https://example.com/cover.jpg",
            artistAvatarURLs: ["https://example.com/artist.jpg"],
            type: .concert
        )

        let container = try ModelContainer(
            for: Show.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        container.mainContext.insert(show)
        try container.mainContext.save()

        let shows = try container.mainContext.fetch(FetchDescriptor<Show>())
        XCTAssertEqual(shows.count, 1)
        XCTAssertEqual(shows[0].name, "落日飞车 北京站")
        XCTAssertEqual(shows[0].date, date)
        XCTAssertEqual(shows[0].type, .concert)
        XCTAssertNil(shows[0].startTime)
        XCTAssertNil(shows[0].venueName)
        XCTAssertEqual(shows[0].coverImageURL, "https://example.com/cover.jpg")
        XCTAssertEqual(shows[0].artistAvatarURLs, ["https://example.com/artist.jpg"])
    }

    func testOnlyConfirmedV21ShowTypesAreAccepted() {
        XCTAssertEqual(ShowType.allCases, [.concert, .livehouse, .musicFestival])
        XCTAssertNil(ShowType(rawValue: "theater"))
        XCTAssertNil(ShowType(rawValue: "sports"))
    }

    func testPostponedAndCanceledAreRepresentedWithoutGenericAbnormalStates() throws {
        let show = try Show(name: "延期测试现场", date: Date(), type: .livehouse)

        show.markPostponed(newDate: nil)
        XCTAssertEqual(show.changeStatus, .postponed)
        XCTAssertNil(show.postponedDate)

        let newDate = Date(timeIntervalSinceNow: 86_400)
        show.markPostponed(newDate: newDate)
        XCTAssertEqual(show.changeStatus, .postponed)
        XCTAssertEqual(show.postponedDate, newDate)

        show.markCanceled()
        XCTAssertEqual(show.changeStatus, .canceled)

        XCTAssertEqual(ShowChangeStatus.allCases, [.scheduled, .postponed, .canceled])
    }

    @MainActor
    func testShowStoresOptionalEndDateAndEndTime() throws {
        let container = try ModelContainer(
            for: Show.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let startDate = Date(timeIntervalSince1970: 1_783_468_800)
        let startTime = Date(timeIntervalSince1970: 1_783_551_600)
        let endDate = Date(timeIntervalSince1970: 1_783_555_200)
        let endTime = Date(timeIntervalSince1970: 1_783_558_800)
        let show = try Show(
            name: "深夜发光 Livehouse",
            date: startDate,
            startTime: startTime,
            endDate: endDate,
            endTime: endTime,
            type: .livehouse
        )

        container.mainContext.insert(show)
        try container.mainContext.save()

        let storedShow = try XCTUnwrap(container.mainContext.fetch(FetchDescriptor<Show>()).first)
        XCTAssertEqual(storedShow.endDate, endDate)
        XCTAssertEqual(storedShow.endTime, endTime)
    }

    func testInvalidEndDateBeforeStartDateIsRejected() {
        XCTAssertThrowsError(try Show(
            name: "错误时间现场",
            date: makeDate(year: 2026, month: 7, day: 8, hour: 0, minute: 0, calendar: .current),
            startTime: makeDate(year: 2026, month: 7, day: 8, hour: 20, minute: 0, calendar: .current),
            endDate: makeDate(year: 2026, month: 7, day: 7, hour: 0, minute: 0, calendar: .current),
            endTime: makeDate(year: 2026, month: 7, day: 7, hour: 22, minute: 0, calendar: .current),
            type: .concert
        )) { error in
            XCTAssertEqual(error as? ShowValidationError, .invalidEndTime)
        }
    }

    func testCurrentShowTimeStateMovesStartTimeOntoPostponedDate() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let originalDate = makeDate(year: 2026, month: 6, day: 10, hour: 0, minute: 0, calendar: calendar)
        let originalStartTime = makeDate(year: 2026, month: 6, day: 10, hour: 19, minute: 30, calendar: calendar)
        let postponedDate = makeDate(year: 2026, month: 6, day: 16, hour: 0, minute: 0, calendar: calendar)
        let show = try Show(
            name: "延期但保留开场时间的现场",
            date: originalDate,
            startTime: originalStartTime,
            type: .concert
        )

        show.markPostponed(newDate: postponedDate)

        let state = CurrentShowTimeState(
            show: show,
            calendar: calendar,
            now: makeDate(year: 2026, month: 6, day: 15, hour: 12, minute: 0, calendar: calendar)
        )

        XCTAssertEqual(state.kind, .before)
        XCTAssertEqual(state.statusText, "已延期")
        XCTAssertEqual(state.countdownText, "还有 1 天")
        XCTAssertEqual(state.effectiveDate, postponedDate)
        XCTAssertEqual(
            state.effectiveStartTime,
            makeDate(year: 2026, month: 6, day: 16, hour: 19, minute: 30, calendar: calendar)
        )
    }

    func testCrossDayLivehouseUsesActualEndTimeForCountdownAndRetention() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let show = try Show(
            name: "深夜发光 Livehouse",
            date: makeDate(year: 2026, month: 7, day: 8, hour: 0, minute: 0, calendar: calendar),
            startTime: makeDate(year: 2026, month: 7, day: 8, hour: 23, minute: 0, calendar: calendar),
            endDate: makeDate(year: 2026, month: 7, day: 9, hour: 0, minute: 0, calendar: calendar),
            endTime: makeDate(year: 2026, month: 7, day: 9, hour: 1, minute: 0, calendar: calendar),
            type: .livehouse
        )

        let beforeStart = CurrentShowTimeState(
            show: show,
            calendar: calendar,
            now: makeDate(year: 2026, month: 7, day: 8, hour: 20, minute: 0, calendar: calendar)
        )
        XCTAssertEqual(beforeStart.kind, .today)
        XCTAssertEqual(beforeStart.countdownText, "还有 3 小时")

        let beforeEnd = CurrentShowTimeState(
            show: show,
            calendar: calendar,
            now: makeDate(year: 2026, month: 7, day: 9, hour: 0, minute: 30, calendar: calendar)
        )
        XCTAssertEqual(beforeEnd.kind, .today)
        XCTAssertEqual(beforeEnd.countdownText, "正在现场")

        let afterEnd = CurrentShowTimeState(
            show: show,
            calendar: calendar,
            now: makeDate(year: 2026, month: 7, day: 9, hour: 1, minute: 30, calendar: calendar)
        )
        XCTAssertEqual(afterEnd.kind, .postShow)
        XCTAssertEqual(afterEnd.helperText, "7月9日 01:00 结束 · 停留期还剩 2 天 23 小时")

        let afterRetention = CurrentShowTimeState(
            show: show,
            calendar: calendar,
            now: makeDate(year: 2026, month: 7, day: 12, hour: 2, minute: 0, calendar: calendar)
        )
        XCTAssertEqual(afterRetention.kind, .ended)
    }

    func testMissingEndTimeUsesElevenFiftyFivePMOnlyAsStateBoundary() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let show = try Show(
            name: "未填结束时间的现场",
            date: makeDate(year: 2026, month: 7, day: 8, hour: 0, minute: 0, calendar: calendar),
            startTime: makeDate(year: 2026, month: 7, day: 8, hour: 19, minute: 30, calendar: calendar),
            type: .concert
        )

        XCTAssertNil(show.endTime)

        let beforeFallbackEnd = CurrentShowTimeState(
            show: show,
            calendar: calendar,
            now: makeDate(year: 2026, month: 7, day: 8, hour: 22, minute: 30, calendar: calendar)
        )
        XCTAssertEqual(beforeFallbackEnd.kind, .today)
        XCTAssertEqual(beforeFallbackEnd.countdownText, "正在现场")

        let afterFallbackEnd = CurrentShowTimeState(
            show: show,
            calendar: calendar,
            now: makeDate(year: 2026, month: 7, day: 8, hour: 23, minute: 56, calendar: calendar)
        )
        XCTAssertEqual(afterFallbackEnd.kind, .postShow)
        XCTAssertEqual(afterFallbackEnd.helperText, "7月8日 23:55 结束 · 停留期还剩 2 天 23 小时")
    }

    func testFestivalDateRangeStaysTodayUntilRangeEnds() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let show = try Show(
            name: "绿洲音乐节",
            date: makeDate(year: 2026, month: 8, day: 15, hour: 0, minute: 0, calendar: calendar),
            startTime: makeDate(year: 2026, month: 8, day: 15, hour: 13, minute: 0, calendar: calendar),
            endDate: makeDate(year: 2026, month: 8, day: 17, hour: 0, minute: 0, calendar: calendar),
            type: .musicFestival
        )

        let middleDay = CurrentShowTimeState(
            show: show,
            calendar: calendar,
            now: makeDate(year: 2026, month: 8, day: 16, hour: 12, minute: 0, calendar: calendar)
        )
        XCTAssertEqual(middleDay.kind, .today)
        XCTAssertEqual(middleDay.countdownText, "正在现场")

        let afterRange = CurrentShowTimeState(
            show: show,
            calendar: calendar,
            now: makeDate(year: 2026, month: 8, day: 18, hour: 1, minute: 0, calendar: calendar)
        )
        XCTAssertEqual(afterRange.kind, .postShow)
    }

    func testShowDisplayFormatterFormatsCrossDayAndFestivalRanges() throws {
        let crossDay = try Show(
            name: "深夜发光 Livehouse",
            date: makeDate(year: 2026, month: 7, day: 8, hour: 0, minute: 0, calendar: .current),
            startTime: makeDate(year: 2026, month: 7, day: 8, hour: 23, minute: 0, calendar: .current),
            endDate: makeDate(year: 2026, month: 7, day: 9, hour: 0, minute: 0, calendar: .current),
            endTime: makeDate(year: 2026, month: 7, day: 9, hour: 1, minute: 0, calendar: .current),
            type: .livehouse
        )
        let festival = try Show(
            name: "绿洲音乐节",
            date: makeDate(year: 2026, month: 8, day: 15, hour: 0, minute: 0, calendar: .current),
            startTime: makeDate(year: 2026, month: 8, day: 15, hour: 13, minute: 0, calendar: .current),
            endDate: makeDate(year: 2026, month: 8, day: 17, hour: 0, minute: 0, calendar: .current),
            type: .musicFestival
        )
        let noEndTime = try Show(
            name: "普通演唱会",
            date: makeDate(year: 2026, month: 9, day: 12, hour: 0, minute: 0, calendar: .current),
            startTime: makeDate(year: 2026, month: 9, day: 12, hour: 19, minute: 30, calendar: .current),
            type: .concert
        )
        let formatter = ShowDisplayFormatter()

        XCTAssertEqual(formatter.dateText(for: crossDay), "2026年7月8日 23:00 - 7月9日 01:00")
        XCTAssertEqual(formatter.dateText(for: festival), "2026年8月15日-17日 · 每日 13:00")
        XCTAssertEqual(formatter.dateText(for: noEndTime), "2026年9月12日 19:30")
    }

    func testShowCoverFallbackUsesSplashImageWithoutMissingCoverCopy() {
        let presentation = ShowCoverFallbackPresentation(reason: .noCover)

        XCTAssertEqual(presentation.assetName, "splash_bg")
        XCTAssertEqual(presentation.alignment, .top)
        XCTAssertTrue(presentation.visibleTexts.isEmpty)
    }

    func testTodayAllToolsSummaryUsesCurrentToolNames() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let show = try Show(
            name: "今晚现场",
            date: makeDate(year: 2026, month: 7, day: 8, hour: 0, minute: 0, calendar: calendar),
            startTime: makeDate(year: 2026, month: 7, day: 8, hour: 20, minute: 0, calendar: calendar),
            type: .concert
        )
        let state = CurrentShowTimeState(
            show: show,
            calendar: calendar,
            now: makeDate(year: 2026, month: 7, day: 8, hour: 12, minute: 0, calendar: calendar)
        )

        XCTAssertEqual(state.kind, .today)
        XCTAssertEqual(state.allToolsSummary, "候选曲目 · 现场准备 · 现场碎片")
        XCTAssertFalse(state.allToolsSummary.contains("路上先听"))
    }

    func testCurrentHomeHeroUsesLabeledPosterCardWithActionsOnCover() {
        let presentation = CurrentShowHeroLayoutPresentation()

        XCTAssertTrue(presentation.showsSectionTitle)
        XCTAssertEqual(presentation.actionPlacement, .coverTopTrailing)
        XCTAssertGreaterThanOrEqual(presentation.topSpacing, 44)
        XCTAssertGreaterThan(presentation.actionTopOffset, presentation.topSpacing)
        XCTAssertEqual(presentation.actionButtonSize, 42)
        XCTAssertEqual(presentation.coverAspectRatio, 0.72)
    }

    private func makeDate(
        year: Int,
        month: Int,
        day: Int,
        hour: Int,
        minute: Int,
        calendar: Calendar
    ) -> Date {
        DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute
        ).date!
    }
}
