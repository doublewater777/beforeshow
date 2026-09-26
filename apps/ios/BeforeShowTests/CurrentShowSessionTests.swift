import Foundation
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

    // MARK: - Durable Current Show ownership

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

    // MARK: - Single migration runner / container factory

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
        let originalUpdatedAt = Date(timeIntervalSince1970: 100)
        let selection = CurrentShowSelection(
            selectedShowID: ended.id,
            isManual: true,
            updatedAt: originalUpdatedAt
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
        XCTAssertEqual(stored.updatedAt, originalUpdatedAt)
        XCTAssertEqual(try context.fetch(FetchDescriptor<CurrentShowSelection>()).count, 1)
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

    @MainActor
    func testMigrationRunnerCanonicalizesSingletonsAndMarksPrePortfolioShowsMinted() throws {
        let container = try ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let first = try makeShow(name: "旧现场一", day: 16)
        let second = try makeShow(name: "旧现场二", day: 20)
        let selected = CurrentShowSelection(
            selectedShowID: second.id,
            isManual: true,
            updatedAt: Date(timeIntervalSince1970: 30)
        )
        let duplicateSelection = CurrentShowSelection(
            selectedShowID: first.id,
            isManual: false,
            updatedAt: Date(timeIntervalSince1970: 20)
        )
        let state = NotificationSchedulingState(
            stagedBackfillShowID: first.id,
            hasRequestedPermissionAfterFirstShow: false,
            updatedAt: Date(timeIntervalSince1970: 30)
        )
        let duplicateState = NotificationSchedulingState(
            stagedBackfillShowID: second.id,
            hasRequestedPermissionAfterFirstShow: true,
            backfillMintedShowIDs: [first.id],
            updatedAt: Date(timeIntervalSince1970: 20)
        )
        context.insert(first)
        context.insert(second)
        context.insert(selected)
        context.insert(duplicateSelection)
        context.insert(state)
        context.insert(duplicateState)
        try context.save()

        AppPersistenceMigrationRunner.run(in: context, now: now)
        AppPersistenceMigrationRunner.run(in: context, now: now)

        let selections = try context.fetch(FetchDescriptor<CurrentShowSelection>())
        let states = try context.fetch(FetchDescriptor<NotificationSchedulingState>())
        let storedSelection = try XCTUnwrap(selections.first)
        let storedState = try XCTUnwrap(states.first)

        XCTAssertEqual(selections.count, 1)
        XCTAssertEqual(storedSelection.selectedShowID, second.id)
        XCTAssertEqual(states.count, 1)
        XCTAssertEqual(storedState.portfolioMigrationVersion, 1)
        XCTAssertNil(storedState.stagedBackfillShowID)
        XCTAssertTrue(storedState.hasRequestedPermissionAfterFirstShow)
        XCTAssertEqual(Set(storedState.backfillMintedShowIDs ?? []), Set([first.id, second.id]))
    }

    @MainActor
    func testModelContainerFactoryStoresAllPhaseOnePersistenceModels() throws {
        let container = try ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let show = try makeShow(name: "容器现场", day: 20)
        let selection = CurrentShowSelection(selectedShowID: show.id)
        let state = NotificationSchedulingState(backfillMintedShowIDs: [show.id])
        let record = ShowNotificationScheduleRecord(
            showID: show.id,
            milestone: .showDay,
            fireDate: makeDate(year: 2026, month: 6, day: 20, hour: 17)
        )
        context.insert(show)
        context.insert(selection)
        context.insert(state)
        context.insert(record)
        try context.save()

        XCTAssertEqual(try context.fetch(FetchDescriptor<Show>()).count, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<CurrentShowSelection>()).count, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<NotificationSchedulingState>()).count, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<ShowNotificationScheduleRecord>()).count, 1)
    }

    // MARK: - Multi-show notification portfolio

    func testPortfolioSchedulesMultipleShowsWithoutCurrentShowInput() throws {
        let first = try makeShow(name: "第一场", day: 20)
        let second = try makeShow(name: "第二场", day: 25)
        let portfolioNow = makeDate(year: 2026, month: 6, day: 1, hour: 10)

        let plan = NotificationPortfolioPlanner(calendar: calendar).plan(
            shows: [second, first],
            existingRecords: [],
            schedulingState: nil,
            reason: .startup,
            now: portfolioNow
        )

        XCTAssertEqual(Set(plan.scheduledRequests.map(\.showID)), Set([first.id, second.id]))
        XCTAssertTrue(plan.scheduledRequests.contains { $0.showID == first.id && $0.milestone == .showDay })
        XCTAssertTrue(plan.scheduledRequests.contains { $0.showID == second.id && $0.milestone == .showDay })
    }

    func testPortfolioExcludesCanceledHistoricalAndUndatedPostponedShows() throws {
        let valid = try makeShow(name: "有效", day: 20)
        let canceled = try makeShow(name: "取消", day: 21)
        canceled.markCanceled()
        let historical = try makeShow(name: "历史", day: 22)
        historical.markAddedAsHistorical()
        let postponed = try makeShow(name: "延期未定", day: 23)
        postponed.markPostponed(newDate: nil)

        let plan = NotificationPortfolioPlanner(calendar: calendar).plan(
            shows: [valid, canceled, historical, postponed],
            existingRecords: [],
            schedulingState: nil,
            reason: .foreground,
            now: makeDate(year: 2026, month: 6, day: 1, hour: 10)
        )

        XCTAssertEqual(Set(plan.scheduledRequests.map(\.showID)), [valid.id])
    }

    func testPortfolioCapsSystemRequestsAtFiftySix() throws {
        let portfolioNow = makeDate(year: 2026, month: 6, day: 1, hour: 10)
        let shows = try (20...29).map { day in
            try makeShow(name: "第\(day)场", day: day)
        }

        let plan = NotificationPortfolioPlanner(calendar: calendar).plan(
            shows: shows,
            existingRecords: [],
            schedulingState: nil,
            reason: .startup,
            now: portfolioNow
        )

        XCTAssertEqual(plan.scheduledRequests.count, NotificationPortfolioPlan.maximumScheduledRequests)
        XCTAssertEqual(NotificationPortfolioPlan.maximumScheduledRequests, 56)
        XCTAssertGreaterThan(Set(plan.scheduledRequests.map(\.showID)).count, 1)
    }

    func testDeferredBackfillRecordSurvivesPortfolioCapacity() throws {
        let portfolioNow = makeDate(year: 2026, month: 6, day: 1, hour: 10)
        let shows = try (20...29).map { day in
            try makeShow(name: "第\(day)场", day: day)
        }
        let owner = try XCTUnwrap(shows.first)
        let deferredBackfill = ShowNotificationScheduleRecord(
            showID: owner.id,
            milestone: .fourteenDaysBefore,
            fireDate: makeDate(year: 2026, month: 7, day: 1, hour: 12),
            isBackfill: true,
            title: "保留标题",
            body: "保留正文"
        )

        let plan = NotificationPortfolioPlanner(calendar: calendar).plan(
            shows: shows,
            existingRecords: [deferredBackfill],
            schedulingState: nil,
            reason: .foreground,
            now: portfolioNow
        )

        XCTAssertFalse(
            plan.scheduledRequests.contains { $0.requestIdentifier == deferredBackfill.requestIdentifier }
        )
        XCTAssertTrue(
            plan.retainedBackfillRequests.contains { $0.requestIdentifier == deferredBackfill.requestIdentifier }
        )
        XCTAssertTrue(
            plan.modelRequests.contains { $0.requestIdentifier == deferredBackfill.requestIdentifier }
        )
    }

    func testAddedShowMintsBackfillOnlyOnce() throws {
        let show = try makeShow(name: "临近添加", day: 20)
        let state = NotificationSchedulingState()
        let planner = NotificationPortfolioPlanner(calendar: calendar)

        let first = planner.plan(
            shows: [show],
            existingRecords: [],
            schedulingState: state,
            reason: .showAddedCandidate(show.id),
            now: now
        )
        XCTAssertFalse(first.retainedBackfillRequests.isEmpty)
        XCTAssertEqual(first.backfillShowIDsToMarkMinted, [show.id])

        state.markBackfillMinted(showID: show.id)
        let second = planner.plan(
            shows: [show],
            existingRecords: [],
            schedulingState: state,
            reason: .showAddedCandidate(show.id),
            now: now
        )
        XCTAssertTrue(second.retainedBackfillRequests.isEmpty)
        XCTAssertTrue(second.backfillShowIDsToMarkMinted.isEmpty)
    }

    func testPortfolioRecordNormalizationPrefersRecordMatchingDesiredRequest() throws {
        let showID = UUID()
        let desired = ScheduledShowNotification(
            showID: showID,
            milestone: .showDay,
            fireDate: makeDate(year: 2026, month: 6, day: 20, hour: 17),
            title: "正确",
            body: "正确正文"
        )
        let matching = ShowNotificationScheduleRecord(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            showID: showID,
            milestone: .showDay,
            fireDate: desired.fireDate,
            title: desired.title,
            body: desired.body,
            createdAt: Date(timeIntervalSince1970: 10)
        )
        let stale = ShowNotificationScheduleRecord(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            showID: showID,
            milestone: .showDay,
            fireDate: desired.fireDate.addingTimeInterval(60),
            title: "旧",
            body: "旧正文",
            createdAt: Date(timeIntervalSince1970: 20)
        )

        let normalized = NotificationPortfolioRecordStore.normalize(
            records: [stale, matching],
            modelRequests: [desired]
        )

        XCTAssertEqual(normalized.canonicalByIdentifier[desired.requestIdentifier]?.id, matching.id)
        XCTAssertEqual(normalized.duplicates.map(\.id), [stale.id])
    }

    // MARK: - Widget / Live Activity independence

    func testLiveActivityUsesActuallyLiveShowWhenUserCurrentIsEnded() throws {
        let ended = try makeShow(name: "用户当前历史场", day: 1)
        ended.markEnded(at: makeDate(year: 2026, month: 6, day: 1, hour: 22))
        let live = try Show(
            name: "真正正在演出",
            date: makeDate(year: 2026, month: 6, day: 15),
            startTime: makeDate(year: 2026, month: 6, day: 15, hour: 10),
            endTime: makeDate(year: 2026, month: 6, day: 15, hour: 14)
        )

        let resolved = LiveActivityShowResolver(calendar: calendar).resolve(
            shows: [ended, live],
            currentShow: ended,
            now: now
        )

        XCTAssertEqual(resolved?.id, live.id)
    }

    func testLiveActivityUsesNearestUpcomingInsteadOfFartherUserCurrent() throws {
        let nearer = try makeShow(name: "近场", day: 16)
        let current = try makeShow(name: "用户当前远场", day: 25)

        let resolved = LiveActivityShowResolver(calendar: calendar).resolve(
            shows: [current, nearer],
            currentShow: current,
            now: now
        )

        XCTAssertEqual(resolved?.id, nearer.id)
    }

    func testLiveActivityKeepsUserCurrentWhenItIsActuallyLive() throws {
        let current = try Show(
            name: "用户当前直播场",
            date: makeDate(year: 2026, month: 6, day: 15),
            startTime: makeDate(year: 2026, month: 6, day: 15, hour: 9),
            endTime: makeDate(year: 2026, month: 6, day: 15, hour: 15)
        )
        let other = try Show(
            name: "另一直播场",
            date: makeDate(year: 2026, month: 6, day: 15),
            startTime: makeDate(year: 2026, month: 6, day: 15, hour: 11),
            endTime: makeDate(year: 2026, month: 6, day: 15, hour: 16)
        )

        let resolved = LiveActivityShowResolver(calendar: calendar).resolve(
            shows: [other, current],
            currentShow: current,
            now: now
        )

        XCTAssertEqual(resolved?.id, current.id)
    }

    func testCoverCachePrunesToWidgetAndLiveActivityUnion() throws {
        let container = FileManager.default.temporaryDirectory
            .appendingPathComponent("phase1-cover-union-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
        WidgetSnapshotStore.overrideContainerURL = container
        defer {
            WidgetSnapshotStore.overrideContainerURL = nil
            try? FileManager.default.removeItem(at: container)
        }

        let widgetSource = "https://example.com/widget.jpg"
        let liveSource = "https://example.com/live.jpg"
        let staleSource = "https://example.com/stale.jpg"
        try installFakeCoverCache(source: widgetSource, in: container)
        try installFakeCoverCache(source: liveSource, in: container)
        try installFakeCoverCache(source: staleSource, in: container)
        let legacy = container.appendingPathComponent(WidgetSnapshotStore.legacyCoverCacheFilename)
        try Data("legacy".utf8).write(to: legacy)

        WidgetCoverCache.pruneCovers(keeping: [widgetSource, liveSource])

        assertFakeCoverCacheExists(source: widgetSource, in: container)
        assertFakeCoverCacheExists(source: liveSource, in: container)
        assertFakeCoverCacheMissing(source: staleSource, in: container)
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacy.path))
    }

    // MARK: - Notification deep-link ownership

    @MainActor
    func testNotificationRouterPublishesOnlyToFeatureRootAndDoesNotMutateCurrentSelection() {
        let router = NotificationDeepLinkRouter.shared
        _ = router.consumeFeatureRoot()
        _ = router.consume()

        let currentID = UUID()
        let targetID = UUID()
        let selection = CurrentShowSelection(selectedShowID: currentID)
        let deepLink = NotificationDeepLink(showID: targetID, destination: .memoryFragments)

        router.route(to: deepLink)

        XCTAssertEqual(router.featureRootDeepLink, deepLink)
        XCTAssertNil(router.pendingDeepLink)
        XCTAssertEqual(selection.selectedShowID, currentID)
        XCTAssertEqual(router.consumeFeatureRoot(), deepLink)
        XCTAssertNil(router.featureRootDeepLink)
    }

    // MARK: - Helpers

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

    private func installFakeCoverCache(source: String, in container: URL) throws {
        let files = [
            WidgetCoverCache.filename(for: source),
            WidgetCoverCache.liveActivityFilename(for: source),
            WidgetCoverCache.filename(for: source) + ".source"
        ]
        for file in files {
            try Data(source.utf8).write(to: container.appendingPathComponent(file))
        }
    }

    private func assertFakeCoverCacheExists(source: String, in container: URL) {
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: container.appendingPathComponent(WidgetCoverCache.filename(for: source)).path
            )
        )
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: container.appendingPathComponent(WidgetCoverCache.liveActivityFilename(for: source)).path
            )
        )
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: container.appendingPathComponent(WidgetCoverCache.filename(for: source) + ".source").path
            )
        )
    }

    private func assertFakeCoverCacheMissing(source: String, in container: URL) {
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: container.appendingPathComponent(WidgetCoverCache.filename(for: source)).path
            )
        )
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: container.appendingPathComponent(WidgetCoverCache.liveActivityFilename(for: source)).path
            )
        )
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: container.appendingPathComponent(WidgetCoverCache.filename(for: source) + ".source").path
            )
        )
    }
}
