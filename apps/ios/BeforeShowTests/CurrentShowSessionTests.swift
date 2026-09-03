import SwiftData
import XCTest
@testable import BeforeShow

final class CurrentShowSessionTests: XCTestCase {
    private var calendar: Calendar!
    private var now: Date!

    override func setUp() {
        super.setUp()
        calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        now = makeDate(year: 2026, month: 6, day: 15, hour: 12)
    }

    func testResolveRequiresDurableSelection() throws {
        let tomorrow = try makeShow(name: "明天的现场", day: 16)
        let later = try makeShow(name: "更远的现场", day: 22)
        let session = CurrentShowSession(calendar: calendar)

        XCTAssertNil(session.resolve(shows: [later, tomorrow], manualSelection: nil, now: now))

        let selection = CurrentShowSelection(selectedShowID: later.id)
        let snapshot = session.resolve(
            shows: [later, tomorrow],
            manualSelection: selection,
            now: now
        )
        XCTAssertEqual(snapshot?.show.id, later.id)
        XCTAssertEqual(snapshot?.phase.kind, .before)
    }

    func testSnapshotDoesNotRequireShowToBeCurrent() throws {
        let a = try makeShow(name: "A", day: 16)
        let b = try makeShow(name: "B", day: 20)
        let selection = CurrentShowSelection(selectedShowID: a.id)
        let session = CurrentShowSession(calendar: calendar)

        XCTAssertEqual(session.snapshot(for: b, now: now).show.id, b.id)
        XCTAssertFalse(session.isCurrent(b, among: [a, b], manualSelection: selection, now: now))
        XCTAssertTrue(session.isCurrent(a, among: [a, b], manualSelection: selection, now: now))
    }

    func testEndedCanceledAndUndatedPostponedShowsRemainManuallySelectable() throws {
        let undatedPostponed = try makeShow(name: "未定延期", day: 16)
        undatedPostponed.markPostponed(newDate: nil)
        let ended = try makeShow(name: "已结束", day: 1)
        ended.markEnded(at: makeDate(year: 2026, month: 6, day: 1, hour: 21))
        let canceled = try makeShow(name: "已取消", day: 17)
        canceled.markCanceled()
        let session = CurrentShowSession(calendar: calendar)

        XCTAssertTrue(session.isManuallySelectable(undatedPostponed, now: now))
        XCTAssertTrue(session.isManuallySelectable(ended, now: now))
        XCTAssertTrue(session.isManuallySelectable(canceled, now: now))
    }

    func testLifecycleMutationDoesNotClearExistingSelection() throws {
        let ended = try makeShow(name: "已结束", day: 1)
        ended.markEnded(at: makeDate(year: 2026, month: 6, day: 1, hour: 21))
        let selection = CurrentShowSelection(selectedShowID: ended.id)

        ShowMutationCoordinator.reconcileManualSelection(
            shows: [ended],
            selections: [selection],
            session: CurrentShowSession(calendar: calendar),
            now: now
        )

        XCTAssertEqual(selection.selectedShowID, ended.id)
    }

    func testMissingSelectedShowIsClearedByCompatibilityReconcile() throws {
        let selection = CurrentShowSelection(selectedShowID: UUID())
        ShowMutationCoordinator.reconcileManualSelection(
            shows: [],
            selections: [selection],
            session: CurrentShowSession(calendar: calendar),
            now: now
        )
        XCTAssertNil(selection.selectedShowID)
    }

    func testInitialPolicyPrefersActualLiveThenNearestFuture() throws {
        let live = try Show(
            name: "正在现场",
            date: makeDate(year: 2026, month: 6, day: 15),
            startTime: makeDate(year: 2026, month: 6, day: 15, hour: 10),
            endTime: makeDate(year: 2026, month: 6, day: 15, hour: 14)
        )
        let tomorrow = try makeShow(name: "明天", day: 16)
        let later = try makeShow(name: "以后", day: 20)
        let policy = InitialCurrentShowPolicy(calendar: calendar)

        XCTAssertEqual(policy.candidate(from: [later, tomorrow, live], now: now)?.id, live.id)
        XCTAssertEqual(policy.candidate(from: [later, tomorrow], now: now)?.id, tomorrow.id)
    }

    @MainActor
    func testSelectionStoreDeterministicallyNormalizesDuplicateRows() throws {
        let container = try ModelContainer(
            for: Show.self, CurrentShowSelection.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        )
        let context = container.mainContext
        let older = CurrentShowSelection(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            selectedShowID: UUID(),
            updatedAt: Date(timeIntervalSince1970: 10)
        )
        let newer = CurrentShowSelection(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            selectedShowID: UUID(),
            updatedAt: Date(timeIntervalSince1970: 20)
        )
        context.insert(older)
        context.insert(newer)
        try context.save()

        let store = CurrentShowSelectionStore(modelContext: context)
        let canonical = try store.normalizeDuplicates()
        try context.save()

        XCTAssertEqual(canonical?.id, newer.id)
        XCTAssertEqual(try context.fetch(FetchDescriptor<CurrentShowSelection>()).count, 1)
    }

    @MainActor
    func testOwnershipMigrationPreservesExplicitEndedSelectionAndIsIdempotent() throws {
        let container = try ModelContainer(
            for: Show.self, CurrentShowSelection.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        )
        let context = container.mainContext
        let ended = try makeShow(name: "过去", day: 1)
        ended.markEnded(at: makeDate(year: 2026, month: 6, day: 1, hour: 22))
        let future = try makeShow(name: "未来", day: 20)
        let selection = CurrentShowSelection(
            selectedShowID: ended.id,
            isManual: true,
            updatedAt: Date(timeIntervalSince1970: 100)
        )
        context.insert(ended)
        context.insert(future)
        context.insert(selection)
        try context.save()

        CurrentShowOwnershipMigration.migrateIfNeeded(in: context, now: now, calendar: calendar)
        CurrentShowOwnershipMigration.migrateIfNeeded(in: context, now: now, calendar: calendar)

        let stored = try XCTUnwrap(context.fetch(FetchDescriptor<CurrentShowSelection>()).first)
        XCTAssertEqual(stored.selectedShowID, ended.id)
        XCTAssertEqual(stored.isManual, true)
        XCTAssertEqual(context.fetch(FetchDescriptor<CurrentShowSelection>()).count, 1)
    }

    @MainActor
    func testOwnershipMigrationConvertsInvalidOldAutomaticSelectionToVisibleLegacyShow() throws {
        let container = try ModelContainer(
            for: Show.self, CurrentShowSelection.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        )
        let context = container.mainContext
        let ended = try makeShow(name: "旧自动场", day: 1)
        ended.markEnded(at: makeDate(year: 2026, month: 6, day: 1, hour: 22))
        let future = try makeShow(name: "下一场", day: 16)
        let selection = CurrentShowSelection(
            selectedShowID: ended.id,
            isManual: false
        )
        context.insert(ended)
        context.insert(future)
        context.insert(selection)
        try context.save()

        CurrentShowOwnershipMigration.migrateIfNeeded(in: context, now: now, calendar: calendar)

        let stored = try XCTUnwrap(context.fetch(FetchDescriptor<CurrentShowSelection>()).first)
        XCTAssertEqual(stored.selectedShowID, future.id)
        XCTAssertEqual(stored.isManual, true)
    }

    private func makeShow(name: String, day: Int) throws -> Show {
        try Show(
            name: name,
            date: makeDate(year: 2026, month: 6, day: day),
            startTime: makeDate(year: 2026, month: 6, day: day, hour: 20)
        )
    }

    private func makeDate(
        year: Int,
        month: Int,
        day: Int,
        hour: Int = 0,
        minute: Int = 0
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
