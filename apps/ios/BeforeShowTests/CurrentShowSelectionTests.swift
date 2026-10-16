import SwiftData
import XCTest
@testable import BeforeShow

final class CurrentShowSelectionTests: XCTestCase {
    private var calendar: Calendar!
    private var now: Date!

    override func setUp() {
        super.setUp()
        calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        now = makeDate(year: 2026, month: 6, day: 15, hour: 12)
    }

    func testSessionReturnsNilWithoutDurableSelectionEvenWhenShowsExist() throws {
        let previousShow = try makeShow(name: "上一场", day: 10)
        let liveShow = try makeShow(name: "正在进行", day: 15)
        let futureShow = try makeShow(name: "下一场", day: 16)

        let selected = CurrentShowSession(calendar: calendar).selectCurrentShow(
            from: [previousShow, liveShow, futureShow],
            manualSelection: nil,
            now: makeDate(year: 2026, month: 6, day: 15, hour: 21)
        )

        XCTAssertNil(selected, "Runtime time progression must not synthesize a Current Show")
    }

    func testDurableSelectionSurvivesConfirmedEndAndNearbyFutureShow() throws {
        let endedShow = try makeShow(name: "已经结束的现场", day: 10)
        endedShow.markEnded(at: makeDate(year: 2026, month: 6, day: 10, hour: 22))
        let tomorrowShow = try makeShow(name: "明天的现场", day: 16)
        let selection = CurrentShowSelection(selectedShowID: endedShow.id)

        let selected = CurrentShowSession(calendar: calendar).selectCurrentShow(
            from: [tomorrowShow, endedShow],
            manualSelection: selection,
            now: now
        )

        XCTAssertEqual(selected?.id, endedShow.id)
    }

    func testDurableCanceledSelectionRemainsCurrent() throws {
        let canceledShow = try makeShow(name: "已取消现场", day: 16)
        canceledShow.markCanceled()
        let futureShow = try makeShow(name: "另一场", day: 20)
        let selection = CurrentShowSelection(selectedShowID: canceledShow.id)

        let selected = CurrentShowSession(calendar: calendar).selectCurrentShow(
            from: [canceledShow, futureShow],
            manualSelection: selection,
            now: now
        )

        XCTAssertEqual(selected?.id, canceledShow.id)
    }

    func testDurableUndatedPostponedSelectionRemainsCurrent() throws {
        let postponedShow = try makeShow(name: "未定延期现场", day: 16)
        postponedShow.markPostponed(newDate: nil)
        let futureShow = try makeShow(name: "另一场", day: 20)
        let selection = CurrentShowSelection(selectedShowID: postponedShow.id)

        let selected = CurrentShowSession(calendar: calendar).selectCurrentShow(
            from: [postponedShow, futureShow],
            manualSelection: selection,
            now: now
        )

        XCTAssertEqual(selected?.id, postponedShow.id)
    }

    func testRuntimeTimeProgressionNeverReplacesDurableSelection() throws {
        let selectedShow = try makeShow(name: "用户当前", day: 10)
        let laterLiveShow = try makeShow(name: "后来正在进行", day: 20)
        let selection = CurrentShowSelection(selectedShowID: selectedShow.id)
        let session = CurrentShowSession(calendar: calendar)

        let before = session.selectCurrentShow(
            from: [selectedShow, laterLiveShow],
            manualSelection: selection,
            now: now
        )
        let after = session.selectCurrentShow(
            from: [selectedShow, laterLiveShow],
            manualSelection: selection,
            now: makeDate(year: 2026, month: 6, day: 20, hour: 21)
        )

        XCTAssertEqual(before?.id, selectedShow.id)
        XCTAssertEqual(after?.id, selectedShow.id)
    }

    func testSelectionPointingToMissingShowResolvesNilInsteadOfAutoSelectingAnotherShow() throws {
        let futureShow = try makeShow(name: "仍存在的现场", day: 20)
        let selection = CurrentShowSelection(selectedShowID: UUID())

        let selected = CurrentShowSession(calendar: calendar).selectCurrentShow(
            from: [futureShow],
            manualSelection: selection,
            now: now
        )

        XCTAssertNil(selected)
    }

    func testEveryPersistedShowIsManuallySelectableRegardlessOfLifecycle() throws {
        let endedShow = try makeShow(name: "结束", day: 10)
        endedShow.markEnded(at: makeDate(year: 2026, month: 6, day: 10, hour: 22))
        let canceledShow = try makeShow(name: "取消", day: 16)
        canceledShow.markCanceled()
        let postponedShow = try makeShow(name: "延期未定", day: 17)
        postponedShow.markPostponed(newDate: nil)
        let session = CurrentShowSession(calendar: calendar)

        XCTAssertTrue(session.isManuallySelectable(endedShow, now: now))
        XCTAssertTrue(session.isManuallySelectable(canceledShow, now: now))
        XCTAssertTrue(session.isManuallySelectable(postponedShow, now: now))
    }

    @MainActor
    func testSelectionStoreSelectPersistsAndSessionResolvesIt() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let nearestShow = try makeShow(name: "最近现场", day: 16)
        let chosenShow = try makeShow(name: "用户选择", day: 25)
        context.insert(nearestShow)
        context.insert(chosenShow)

        let store = CurrentShowSelectionStore(modelContext: context)
        let selection = try store.select(showID: chosenShow.id)
        try context.save()

        let stored = try XCTUnwrap(store.canonicalSelection())
        let selected = CurrentShowSession(calendar: calendar).selectCurrentShow(
            from: [nearestShow, chosenShow],
            manualSelection: stored,
            now: now
        )

        XCTAssertEqual(selection.selectedShowID, chosenShow.id)
        XCTAssertEqual(stored.selectedShowID, chosenShow.id)
        XCTAssertEqual(stored.isManual, true)
        XCTAssertEqual(selected?.id, chosenShow.id)
    }

    @MainActor
    func testSelectionStoreNormalizesDuplicatesDeterministically() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let olderShowID = UUID()
        let newerShowID = UUID()
        let older = CurrentShowSelection(
            selectedShowID: olderShowID,
            updatedAt: Date(timeIntervalSince1970: 100)
        )
        let newer = CurrentShowSelection(
            selectedShowID: newerShowID,
            updatedAt: Date(timeIntervalSince1970: 200)
        )
        context.insert(older)
        context.insert(newer)
        try context.save()

        let canonical = try XCTUnwrap(
            CurrentShowSelectionStore(modelContext: context).normalizeDuplicates()
        )
        try context.save()

        let remaining = try context.fetch(FetchDescriptor<CurrentShowSelection>())
        XCTAssertEqual(canonical.id, newer.id)
        XCTAssertEqual(canonical.selectedShowID, newerShowID)
        XCTAssertEqual(remaining.count, 1)
        XCTAssertEqual(remaining.first?.id, newer.id)
    }

    @MainActor
    func testBootstrapDoesNotReplaceExistingValidSelection() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let currentShow = try makeShow(name: "用户当前", day: 10)
        let futureShow = try makeShow(name: "未来现场", day: 16)
        let selection = CurrentShowSelection(selectedShowID: currentShow.id)
        context.insert(currentShow)
        context.insert(futureShow)
        context.insert(selection)
        try context.save()

        let bootstrapped = try CurrentShowSelectionStore(modelContext: context).bootstrapIfNeeded(
            shows: [futureShow, currentShow],
            now: now,
            policy: InitialCurrentShowPolicy(calendar: calendar)
        )

        XCTAssertEqual(bootstrapped?.selectedShowID, currentShow.id)
    }

    @MainActor
    func testBootstrapCreatesInitialSelectionOnlyWhenSelectionIsMissing() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let nearerShow = try makeShow(name: "明天", day: 16)
        let laterShow = try makeShow(name: "下周", day: 22)
        context.insert(nearerShow)
        context.insert(laterShow)
        try context.save()

        let selection = try CurrentShowSelectionStore(modelContext: context).bootstrapIfNeeded(
            shows: [laterShow, nearerShow],
            now: now,
            policy: InitialCurrentShowPolicy(calendar: calendar)
        )
        try context.save()

        XCTAssertEqual(selection?.selectedShowID, nearerShow.id)
        XCTAssertEqual(
            try context.fetch(FetchDescriptor<CurrentShowSelection>()).count,
            1
        )
    }

    @MainActor
    func testClearKeepsCanonicalRowButRemovesCurrentOwnership() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let showID = UUID()
        context.insert(CurrentShowSelection(selectedShowID: showID))
        try context.save()

        let store = CurrentShowSelectionStore(modelContext: context)
        let cleared = try store.clear()
        try context.save()

        XCTAssertNil(cleared?.selectedShowID)
        XCTAssertEqual(cleared?.isManual, true)
        XCTAssertEqual(
            try context.fetch(FetchDescriptor<CurrentShowSelection>()).count,
            1
        )
    }

    func testAutomaticSelectionChoosesNearestFutureRegardlessOfAddOrder() throws {
        let farther = try makeShow(name: "较远", day: 24)
        let closer = try makeShow(name: "较近", day: 16)
        let selection = CurrentShowSelection(
            selectedShowID: farther.id, isManual: false
        )
        let selected = CurrentShowSession(calendar: calendar).selectCurrentShow(
            from: [farther, closer], manualSelection: selection, now: now
        )
        XCTAssertEqual(selected?.id, closer.id)
    }

    func testOverlappingLiveShowsRetainCurrentAutomaticShow() throws {
        let first = try Show(
            name: "先开场",
            date: makeDate(year: 2026, month: 6, day: 15),
            startTime: makeDate(year: 2026, month: 6, day: 15, hour: 19)
        )
        let second = try Show(
            name: "后开场",
            date: makeDate(year: 2026, month: 6, day: 15),
            startTime: makeDate(year: 2026, month: 6, day: 15, hour: 20)
        )
        let atOverlap = makeDate(year: 2026, month: 6, day: 15, hour: 20)
            .addingTimeInterval(30 * 60)
        let selection = CurrentShowSelection(
            selectedShowID: first.id, isManual: false
        )
        let resolved = CurrentShowSession(calendar: calendar).selectCurrentShow(
            from: [first, second], manualSelection: selection, now: atOverlap
        )
        XCTAssertEqual(resolved?.id, first.id)
    }

    func testAutomaticSelectionRetainsPostShowThenAdvancesAfterThreeDays() throws {
        let finished = try makeShow(name: "刚散场", day: 14)
        finished.markEnded(at: makeDate(year: 2026, month: 6, day: 14, hour: 22))
        let upcoming = try makeShow(name: "下一场", day: 20)
        let selection = CurrentShowSelection(
            selectedShowID: finished.id, isManual: false
        )
        let session = CurrentShowSession(calendar: calendar)
        XCTAssertEqual(
            session.selectCurrentShow(from: [finished, upcoming], manualSelection: selection, now: now)?.id,
            finished.id
        )
        let afterRetention = makeDate(year: 2026, month: 6, day: 19, hour: 12)
        XCTAssertEqual(
            session.selectCurrentShow(from: [finished, upcoming], manualSelection: selection, now: afterRetention)?.id,
            upcoming.id
        )
    }

    func testLiveShowOverridesAutomaticPostShowButNotManual() throws {
        let finished = try makeShow(name: "散场", day: 14)
        finished.markEnded(at: makeDate(year: 2026, month: 6, day: 14, hour: 22))
        let live = try makeShow(name: "正在现场", day: 15)
        let atLive = makeDate(year: 2026, month: 6, day: 15, hour: 21)
        let session = CurrentShowSession(calendar: calendar)
        let automatic = CurrentShowSelection(
            selectedShowID: finished.id, isManual: false
        )
        XCTAssertEqual(
            session.selectCurrentShow(from: [finished, live], manualSelection: automatic, now: atLive)?.id,
            live.id
        )
        let manual = CurrentShowSelection(selectedShowID: finished.id)
        XCTAssertEqual(
            session.selectCurrentShow(from: [finished, live], manualSelection: manual, now: atLive)?.id,
            finished.id
        )
    }

    func testAutomaticFestivalSurvivesMidnightUntilAnotherShowActuallyStarts() throws {
        for hasTimetable in [false, true] {
            let festival = try Show(
                name: "多日音乐节",
                date: makeDate(year: 2026, month: 6, day: 15, hour: 0),
                startTime: makeDate(year: 2026, month: 6, day: 15, hour: 14),
                endDate: makeDate(year: 2026, month: 6, day: 17, hour: 0),
                endTime: makeDate(year: 2026, month: 6, day: 17, hour: 22),
                timeZoneIdentifier: "UTC"
            )
            if hasTimetable {
                let days = try [15, 17].map { day in
                    try TimetableDay(
                        date: makeDate(year: 2026, month: 6, day: day, hour: 0),
                        stages: [TimetableStage(name: "主舞台", performances: [
                            TimetablePerformance(
                                artistName: "演出艺人",
                                startsAt: makeDate(year: 2026, month: 6, day: day, hour: 14),
                                endsAt: makeDate(year: 2026, month: 6, day: day, hour: 22)
                            )
                        ])]
                    )
                }
                festival.timetable = try Timetable(timeZoneIdentifier: "UTC", days: days)
            }
            let other = try Show(
                name: "另一场",
                date: makeDate(year: 2026, month: 6, day: 17, hour: 0),
                startTime: makeDate(year: 2026, month: 6, day: 17, hour: 10),
                endTime: makeDate(year: 2026, month: 6, day: 17, hour: 12),
                timeZoneIdentifier: "UTC"
            )
            let policy = InitialCurrentShowPolicy(calendar: calendar)
            let beforeOpening = [
                makeDate(year: 2026, month: 6, day: 15, hour: 23),
                makeDate(year: 2026, month: 6, day: 16, hour: 12),
                makeDate(year: 2026, month: 6, day: 17, hour: 0),
                makeDate(year: 2026, month: 6, day: 17, hour: 9)
            ]
            for instant in beforeOpening {
                XCTAssertEqual(
                    policy.candidate(from: [other, festival], retaining: festival.id, now: instant)?.id,
                    festival.id,
                    "Retain the festival between sessions (timetable: \(hasTimetable), time: \(instant))"
                )
            }
            XCTAssertEqual(
                policy.candidate(
                    from: [other, festival], retaining: festival.id,
                    now: makeDate(year: 2026, month: 6, day: 17, hour: 10)
                )?.id,
                other.id
            )
        }
    }

    func testAutomaticCurrentShowSurvivesUndatedPostponement() throws {
        let current = try makeShow(name: "原当前现场", day: 16)
        let other = try makeShow(name: "另一场", day: 20)
        let policy = InitialCurrentShowPolicy(calendar: calendar)
        let selectedID = try XCTUnwrap(policy.candidate(from: [other, current], now: now)?.id)
        current.markPostponed(newDate: nil)

        XCTAssertEqual(
            policy.candidate(from: [other, current], retaining: selectedID, now: now)?.id,
            current.id
        )
        XCTAssertEqual(
            policy.candidate(from: [other, current], now: now)?.id,
            other.id,
            "An unselected undated postponed show must not become a new candidate"
        )
    }

    func testAutomaticSelectionExcludesHistoricalCanceledAndUndatedPostponed() throws {
        let historical = try makeShow(name: "补录", day: 14)
        historical.markAddedAsHistorical()
        let canceled = try makeShow(name: "取消", day: 16)
        canceled.markCanceled()
        let postponed = try makeShow(name: "延期待定", day: 17)
        postponed.markPostponed(newDate: nil)
        let future = try makeShow(name: "有效现场", day: 20)
        let selected = InitialCurrentShowPolicy(calendar: calendar).candidate(
            from: [historical, canceled, postponed, future], now: now
        )
        XCTAssertEqual(selected?.id, future.id)
    }

    @MainActor
    func testBootstrapReconcilesAutomaticSelectionButKeepsManual() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let farther = try makeShow(name: "较远", day: 24)
        let closer = try makeShow(name: "较近", day: 16)
        let selection = CurrentShowSelection(
            selectedShowID: farther.id, isManual: false
        )
        context.insert(farther)
        context.insert(closer)
        context.insert(selection)
        try context.save()
        let store = CurrentShowSelectionStore(modelContext: context)
        _ = try store.bootstrapIfNeeded(
            shows: [farther, closer],
            now: now,
            policy: InitialCurrentShowPolicy(calendar: calendar)
        )
        XCTAssertEqual(selection.selectedShowID, closer.id)
        XCTAssertEqual(selection.isManual, false)
        XCTAssertEqual(selection.selectionPolicyVersion, 2)
        selection.select(showID: farther.id)
        _ = try store.bootstrapIfNeeded(
            shows: [farther, closer],
            now: now,
            policy: InitialCurrentShowPolicy(calendar: calendar)
        )
        XCTAssertEqual(selection.selectedShowID, farther.id)
        XCTAssertEqual(selection.isManual, true)
    }

    @MainActor
    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: Show.self, CurrentShowSelection.self,
            configurations: ModelConfiguration(
                isStoredInMemoryOnly: true,
                cloudKitDatabase: .none
            )
        )
    }

    private func makeShow(name: String, day: Int) throws -> Show {
        try Show(
            name: name,
            date: makeDate(year: 2026, month: 6, day: day),
            startTime: makeDate(year: 2026, month: 6, day: day, hour: 20)
        )
    }

    private func makeDate(year: Int, month: Int, day: Int, hour: Int = 20) -> Date {
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
