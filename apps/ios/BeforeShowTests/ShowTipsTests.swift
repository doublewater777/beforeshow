import XCTest
@testable import BeforeShow

final class ShowTipsTests: XCTestCase {
    private var calendar: Calendar!

    override func setUp() {
        super.setUp()
        calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    }

    func testDoesNotShowBeforeFourteenDayWindow() throws {
        let now = makeDate(year: 2026, month: 7, day: 1, hour: 12)
        let phase = try makePhase(showDay: 16, now: now)

        XCTAssertNil(resolve(phase: phase, now: now))
    }

    func testShowsCandidateSongsFromFourteenToEightDaysBefore() throws {
        let now = makeDate(year: 2026, month: 7, day: 1, hour: 12)
        let phase = try makePhase(showDay: 15, now: now)

        XCTAssertEqual(
            resolve(phase: phase, hasCandidateSongs: true, now: now),
            ShowTip(message: "还有 14 天，先去熟悉一下曲目？", buttonTitle: "去看看", action: .candidateSongs)
        )
    }

    func testShowsOutboundPlanFromSevenToTwoDaysBeforeWhenMissing() throws {
        let now = makeDate(year: 2026, month: 7, day: 1, hour: 12)
        let phase = try makePhase(showDay: 8, now: now)

        XCTAssertEqual(
            resolve(phase: phase, now: now),
            ShowTip(message: "还有 7 天，先定好怎么去？", buttonTitle: "生成计划", action: .outboundPlan)
        )
    }

    func testHidesSevenToTwoDayTipWhenOutboundPlanExists() throws {
        let now = makeDate(year: 2026, month: 7, day: 1, hour: 12)
        let phase = try makePhase(showDay: 3, now: now)

        XCTAssertNil(resolve(phase: phase, hasOutboundPlan: true, now: now))
    }

    func testShowsPreparationOneDayBefore() throws {
        let now = makeDate(year: 2026, month: 7, day: 1, hour: 12)
        let phase = try makePhase(showDay: 2, now: now)

        XCTAssertEqual(
            resolve(phase: phase, hasOutboundPlan: true, now: now),
            ShowTip(message: "明天开场，出门前要带的都确认了吗？", buttonTitle: "看准备", action: .showPreparation)
        )
    }

    func testShowsOutboundConfirmationOnShowDayBeforeStart() throws {
        let now = makeDate(year: 2026, month: 7, day: 1, hour: 12)
        let phase = try makePhase(showDay: 1, now: now)

        XCTAssertEqual(
            resolve(phase: phase, hasOutboundPlan: true, now: now),
            ShowTip(message: "就是今天，出发时间再确认一下？", buttonTitle: "查看去程", action: .outboundPlan)
        )
    }

    func testShowsFragmentsDuringShow() throws {
        let now = makeDate(year: 2026, month: 7, day: 1, hour: 21)
        let phase = try makePhase(showDay: 1, now: now)

        XCTAssertEqual(
            resolve(phase: phase, now: now),
            ShowTip(message: "正在现场，拍一张留给这场？", buttonTitle: "记一笔", action: .showFragments)
        )
    }

    func testShowsPostShowFragmentsOnlyWhenMissing() throws {
        let now = makeDate(year: 2026, month: 7, day: 2, hour: 12)
        let phase = try makePhase(showDay: 1, now: now)

        XCTAssertEqual(
            resolve(phase: phase, now: now),
            ShowTip(message: "刚散场，把这一刻先留下来？", buttonTitle: "记一笔", action: .showFragments)
        )
        XCTAssertNil(resolve(phase: phase, hasFragments: true, now: now))
    }

    func testHidesTipsForEndedCanceledAndUndatedPostponedShows() throws {
        let now = makeDate(year: 2026, month: 7, day: 10, hour: 12)
        let ended = try makePhase(showDay: 1, now: now)
        let canceledShow = try makeShow(day: 12)
        canceledShow.markCanceled()
        let postponedShow = try makeShow(day: 12)
        postponedShow.markPostponed(newDate: nil)

        XCTAssertNil(resolve(phase: ended, now: now))
        XCTAssertNil(resolve(phase: CurrentShowTimeState(show: canceledShow, calendar: calendar, now: now), now: now))
        XCTAssertNil(resolve(phase: CurrentShowTimeState(show: postponedShow, calendar: calendar, now: now), now: now))
    }

    /// Home Tips UI is this struct only: message + buttonTitle + action.
    /// A nil resolve must hide the Tips card — not fall back to tool-item marketing copy.
    func testResolvedTipIsCompleteHomeSurfaceAndNilMeansHide() throws {
        let now = makeDate(year: 2026, month: 7, day: 1, hour: 12)
        let inWindow = try makePhase(showDay: 8, now: now)
        let outsideWindow = try makePhase(showDay: 20, now: now)

        let tip = resolve(phase: inWindow, now: now)
        XCTAssertEqual(tip?.message, "还有 7 天，先定好怎么去？")
        XCTAssertEqual(tip?.buttonTitle, "生成计划")
        XCTAssertEqual(tip?.action, .outboundPlan)

        XCTAssertNil(resolve(phase: outsideWindow, now: now))
    }

    func testShowDayWithoutOutboundPlanUsesGenerateCopyNotToolStatusCopy() throws {
        let now = makeDate(year: 2026, month: 7, day: 1, hour: 12)
        let phase = try makePhase(showDay: 1, now: now)

        XCTAssertEqual(
            resolve(phase: phase, hasOutboundPlan: false, now: now),
            ShowTip(message: "就是今天，先定好怎么到现场？", buttonTitle: "生成计划", action: .outboundPlan)
        )
    }

    private func resolve(
        phase: CurrentShowTimeState,
        hasCandidateSongs: Bool = false,
        hasOutboundPlan: Bool = false,
        hasFragments: Bool = false,
        now: Date
    ) -> ShowTip? {
        ShowTipsResolver.resolve(
            phase: phase,
            hasCandidateSongs: hasCandidateSongs,
            hasOutboundPlan: hasOutboundPlan,
            hasFragments: hasFragments,
            now: now
        )
    }

    private func makePhase(showDay: Int, now: Date) throws -> CurrentShowTimeState {
        CurrentShowTimeState(show: try makeShow(day: showDay), calendar: calendar, now: now)
    }

    private func makeShow(day: Int) throws -> Show {
        try Show(
            name: "Tips 测试现场",
            date: makeDate(year: 2026, month: 7, day: day),
            startTime: makeDate(year: 2026, month: 7, day: day, hour: 20),
            type: .concert
        )
    }

    private func makeDate(year: Int, month: Int, day: Int, hour: Int = 0) -> Date {
        DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: year,
            month: month,
            day: day,
            hour: hour
        ).date!
    }
}
