import XCTest
@testable import BeforeShow

final class AddShowFlowPolicyTests: XCTestCase {
    private let calendar = Calendar.current

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    // MARK: Save bar

    func testSaveBarReportsMissingFieldsBeforeFailureOrCapacity() {
        var input = AddShowSaveBarStatus.Input(
            nameIsEmpty: true,
            isAtFreeCapacity: true,
            failure: "这场已经在 BeforeShow 里了"
        )
        XCTAssertEqual(AddShowSaveBarStatus.resolve(input), .missingName)

        input.nameIsEmpty = false
        XCTAssertEqual(AddShowSaveBarStatus.resolve(input), .failure("这场已经在 BeforeShow 里了"))

        input.failure = nil
        XCTAssertEqual(AddShowSaveBarStatus.resolve(input), .atFreeCapacity)
    }

    func testSaveBarAsksForLifecycleChoiceInsteadOfPresentingSecondSheet() {
        let status = AddShowSaveBarStatus.resolve(.init(needsLifecycleChoice: true))
        XCTAssertEqual(status, .needsLifecycleChoice)
        XCTAssertEqual(status?.blocksSave, true)
    }

    func testCapacityAndFailureKeepSaveButtonTappable() {
        XCTAssertFalse(AddShowSaveBarStatus.atFreeCapacity.blocksSave)
        XCTAssertFalse(AddShowSaveBarStatus.failure("x").blocksSave)
        XCTAssertTrue(AddShowSaveBarStatus.missingStartTime.blocksSave)
    }

    func testImportingWinsOverEverything() {
        XCTAssertEqual(
            AddShowSaveBarStatus.resolve(.init(isParsingLink: true, nameIsEmpty: true)),
            .importing(isLink: true)
        )
        XCTAssertNil(AddShowSaveBarStatus.resolve(.init()))
    }

    // MARK: Paste

    func testPastingSupportedLinkIntoEmptyFieldStartsParsing() {
        XCTAssertTrue(AddShowLinkPasteDetection.shouldAutoParse(
            previous: "",
            current: "【大麦】演唱会 https://m.damai.cn/item.htm?id=1"
        ))
    }

    func testTypingOrUnsupportedLinkDoesNotAutoParse() {
        XCTAssertFalse(AddShowLinkPasteDetection.shouldAutoParse(
            previous: "https://m.damai.cn/item.htm?id=",
            current: "https://m.damai.cn/item.htm?id=1"
        ))
        XCTAssertFalse(AddShowLinkPasteDetection.shouldAutoParse(
            previous: "",
            current: "https://example.com/show"
        ))
    }

    func testComingBackWithANewCopyAsksForTheClipboard() {
        XCTAssertTrue(AddShowLinkReturnPaste.shouldRequest(seenChangeCount: 3, changeCount: 4, hasPasteable: true, linkText: "", isParsing: false))
    }

    func testComingBackWithoutANewCopyOrWithALinkAlreadyInDoesNotAsk() {
        XCTAssertFalse(AddShowLinkReturnPaste.shouldRequest(seenChangeCount: 4, changeCount: 4, hasPasteable: true, linkText: "", isParsing: false))
        XCTAssertFalse(AddShowLinkReturnPaste.shouldRequest(seenChangeCount: 3, changeCount: 4, hasPasteable: false, linkText: "", isParsing: false))
        XCTAssertFalse(AddShowLinkReturnPaste.shouldRequest(seenChangeCount: 3, changeCount: 4, hasPasteable: true, linkText: "https://m.damai.cn/item.htm?id=1", isParsing: false))
        XCTAssertFalse(AddShowLinkReturnPaste.shouldRequest(seenChangeCount: 3, changeCount: 4, hasPasteable: true, linkText: "", isParsing: true))
    }

    // MARK: Saved feedback

    func testSavedFeedbackTellsWhereTheShowWent() {
        let showDate = date(2026, 11, 20)
        XCTAssertEqual(
            AddShowSavedFeedback.title(for: .current, showDate: showDate, calendar: calendar),
            "已设为当前现场"
        )
        XCTAssertEqual(
            AddShowSavedFeedback.title(for: .footprint, showDate: showDate, calendar: calendar),
            "已放进足迹"
        )
        XCTAssertTrue(
            AddShowSavedFeedback.title(for: .future, showDate: showDate, calendar: calendar)
                .hasPrefix("已加入 · ")
        )
    }

    // MARK: Lifecycle question

    func testFutureShowDoesNotAskWhetherItEnded() {
        let draft = ShowDraft(name: "未来", date: date(2026, 8, 30), startTime: date(2026, 8, 30, 20))
        XCTAssertNil(AddShowLifecycleQuestion.resolve(for: draft, now: date(2026, 8, 29, 12)))
    }

    func testStartedShowAsksInlineWithEndBoundedByStart() {
        let draft = ShowDraft(name: "刚开场", date: date(2026, 8, 29), startTime: date(2026, 8, 29, 16))
        let question = AddShowLifecycleQuestion.resolve(for: draft, now: date(2026, 8, 29, 22))
        XCTAssertNotNil(question)
        XCTAssertLessThanOrEqual(question!.minimumEnd, date(2026, 8, 29, 22))
    }

    func testMultiDayShowBeforeFinalSessionIsLiveWithoutAsking() {
        let draft = ShowDraft(
            name: "三日音乐节",
            date: date(2026, 8, 29),
            startTime: date(2026, 8, 29, 14),
            endDate: date(2026, 8, 31),
            endTime: date(2026, 8, 29, 23)
        )
        XCTAssertNil(AddShowLifecycleQuestion.resolve(for: draft, now: date(2026, 8, 29, 23, 30)))
    }

    func testDefaultEndIsAboutThreeHoursAfterStartButNotInTheFuture() {
        let start = date(2026, 8, 29, 20)
        let question = AddShowLifecycleQuestion(minimumEnd: start, endCalendar: calendar)
        XCTAssertEqual(question.defaultEnd(now: date(2026, 8, 30, 9)), date(2026, 8, 29, 23))
        XCTAssertEqual(question.defaultEnd(now: date(2026, 8, 29, 21)), date(2026, 8, 29, 21))
    }

    // MARK: Overnight end

    func testEndBeforeStartOnSameDayRollsToNextDay() {
        let draft = ShowDraft(name: "夜场", date: date(2026, 8, 29), startTime: date(2026, 8, 29, 20))
        let endDay = draft.resolvedEndDay(
            requested: date(2026, 8, 29),
            endClock: date(2026, 8, 29, 0, 30),
            startClock: date(2026, 8, 29, 20)
        )
        XCTAssertEqual(endDay, date(2026, 8, 30))

        var saved = draft
        saved.endDate = endDay
        saved.endTime = date(2026, 8, 30, 0, 30)
        XCTAssertTrue(saved.hasValidEndTime(calendar: calendar))
    }

    func testSameDayLaterEndAndExplicitLaterDayAreKept() {
        let draft = ShowDraft(name: "常规", date: date(2026, 8, 29), startTime: date(2026, 8, 29, 20))
        XCTAssertEqual(
            draft.resolvedEndDay(requested: date(2026, 8, 29), endClock: date(2026, 8, 29, 23), startClock: date(2026, 8, 29, 20)),
            date(2026, 8, 29)
        )
        XCTAssertEqual(
            draft.resolvedEndDay(requested: date(2026, 8, 31), endClock: date(2026, 8, 29, 1), startClock: date(2026, 8, 29, 20)),
            date(2026, 8, 31)
        )
    }

    // MARK: Failure analytics

    func testFailureReasonsAreStableCodesWithoutUserContent() {
        XCTAssertEqual(AddShowFailureReason.code(for: ShowLinkParsingError.networkFailure), "network_failure")
        XCTAssertEqual(AddShowFailureReason.code(for: ShowLinkParsingError.parseFailed("用户链接 https://x")), "parse_failed")
        XCTAssertEqual(AddShowFailureReason.code(for: ShowValidationError.invalidEndTime), "validation_invalidEndTime")
        XCTAssertEqual(
            AddShowFailureReason.code(for: NSError(domain: "NSCocoaErrorDomain", code: 134030)),
            "NSCocoaErrorDomain#134030"
        )
        XCTAssertEqual(AddShowSaveBarStatus.invalidEndTime.analyticsValue, "invalid_end_time")
    }
}
