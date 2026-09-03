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
