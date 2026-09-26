import Foundation
import SwiftData
import XCTest
@testable import BeforeShow

final class ShowMutationCoordinatorTests: XCTestCase {
    @MainActor
    private func makeContainer(
        _ additionalModels: any PersistentModel.Type...
    ) throws -> ModelContainer {
        let coreModels: [any PersistentModel.Type] = [
            Show.self,
            CurrentShowSelection.self,
            NotificationSchedulingState.self
        ]
        return try ModelContainer(
            for: Schema(coreModels + additionalModels),
            configurations: ModelConfiguration(
                isStoredInMemoryOnly: true,
                cloudKitDatabase: .none
            )
        )
    }

    @MainActor
    func testDraftCommitSurvivesPostCommitSyncFailures() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        let start = Date(timeIntervalSince1970: 2_000_000_000)
        let show = try Show(name: "原现场", date: start, startTime: start)
        context.insert(show)
        try context.save()

        var committedNameSeenByNotificationSync: String?
        var committedNameSeenByWidgetSync: String?
        let effects = CurrentShowPostCommitEffects(
            reconcileNotifications: { _ in
                let verificationContext = ModelContext(container)
                committedNameSeenByNotificationSync = try? verificationContext
                    .fetch(FetchDescriptor<Show>())
                    .first?
                    .name
                return false
            },
            syncWidget: { _, _ in
                let verificationContext = ModelContext(container)
                committedNameSeenByWidgetSync = try? verificationContext
                    .fetch(FetchDescriptor<Show>())
                    .first?
                    .name
                return true
            }
        )

        let didSync = try await ShowMutationCoordinator.applyDraft(
            ShowDraft(show: show).renaming(to: "已提交现场"),
            to: show,
            shows: [show],
            selections: [],
            notificationStates: [],
            in: context,
            effects: effects
        )

        let verificationContext = ModelContext(container)
        let storedShow = try XCTUnwrap(verificationContext.fetch(FetchDescriptor<Show>()).first)
        XCTAssertEqual(storedShow.name, "已提交现场")
        XCTAssertEqual(committedNameSeenByNotificationSync, "已提交现场")
        XCTAssertEqual(committedNameSeenByWidgetSync, "已提交现场")
        XCTAssertFalse(didSync)
    }

    @MainActor
    func testStatusCommitPreservesUserCurrentBeforeFailedNotificationReconcile() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        let start = Date(timeIntervalSinceNow: 86_400)
        let show = try Show(name: "将取消的现场", date: start, startTime: start)
        let selection = CurrentShowSelection(selectedShowID: show.id)
        context.insert(show)
        context.insert(selection)
        try context.save()

        var widgetSelectionID: UUID?
        let effects = CurrentShowPostCommitEffects(
            reconcileNotifications: { _ in
                let verificationContext = ModelContext(container)
                let storedShow = try? verificationContext.fetch(FetchDescriptor<Show>()).first
                let storedSelections = (try? verificationContext
                    .fetch(FetchDescriptor<CurrentShowSelection>())) ?? []
                let storedNotificationStates = (try? verificationContext
                    .fetch(FetchDescriptor<NotificationSchedulingState>())) ?? []

                XCTAssertEqual(storedShow?.changeStatus, .canceled)
                XCTAssertEqual(storedSelections.first?.selectedShowID, show.id)
                XCTAssertTrue(storedNotificationStates.isEmpty)
                return false
            },
            syncWidget: { _, durableSelection in
                widgetSelectionID = durableSelection?.selectedShowID
                return true
            }
        )

        let result = await ShowMutationCoordinator.updateStatus(
            show: show,
            message: "已记录取消",
            shows: [show],
            selections: [selection],
            notificationStates: [],
            in: context,
            effects: effects,
            mutation: { show.markCanceled() }
        )

        let verificationContext = ModelContext(container)
        XCTAssertEqual(
            try XCTUnwrap(verificationContext.fetch(FetchDescriptor<Show>()).first).changeStatus,
            .canceled
        )
        XCTAssertEqual(
            try XCTUnwrap(
                verificationContext.fetch(FetchDescriptor<CurrentShowSelection>()).first
            ).selectedShowID,
            show.id
        )
        XCTAssertTrue(
            try verificationContext.fetch(FetchDescriptor<NotificationSchedulingState>()).isEmpty
        )
        XCTAssertEqual(widgetSelectionID, show.id)
        XCTAssertEqual(result.tone, .neutral)
        XCTAssertEqual(result.message, "已记录取消，同步暂未更新")
    }

    @MainActor
    func testCurrentSelectionCommitsBeforeIndependentPostCommitSync() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        let nearestDate = Date(timeIntervalSinceNow: 86_400)
        let chosenDate = Date(timeIntervalSinceNow: 7 * 86_400)
        let nearest = try Show(name: "最近现场", date: nearestDate, startTime: nearestDate)
        let chosen = try Show(name: "手动现场", date: chosenDate, startTime: chosenDate)
        context.insert(nearest)
        context.insert(chosen)
        try context.save()

        var widgetSelectionID: UUID?
        let effects = CurrentShowPostCommitEffects(
            reconcileNotifications: { _ in
                let verificationContext = ModelContext(container)
                let storedSelections = (try? verificationContext
                    .fetch(FetchDescriptor<CurrentShowSelection>())) ?? []
                let storedNotificationStates = (try? verificationContext
                    .fetch(FetchDescriptor<NotificationSchedulingState>())) ?? []

                XCTAssertEqual(storedSelections.first?.selectedShowID, chosen.id)
                XCTAssertTrue(storedNotificationStates.isEmpty)
                return true
            },
            syncWidget: { _, durableSelection in
                widgetSelectionID = durableSelection?.selectedShowID
                return true
            }
        )

        let didSync = try await ShowMutationCoordinator.selectCurrentShow(
            showID: chosen.id,
            shows: [nearest, chosen],
            selections: [],
            notificationStates: [],
            in: context,
            effects: effects
        )

        XCTAssertTrue(didSync)
        XCTAssertEqual(widgetSelectionID, chosen.id)
        XCTAssertTrue(try context.fetch(FetchDescriptor<NotificationSchedulingState>()).isEmpty)
    }

    @MainActor
    func testDeleteCurrentShowCommitsDeterministicFallbackBeforePostCommitSync() async throws {
        let container = try makeContainer(
            MemoryFragment.self,
            MemoryMediaItem.self,
            ShowAsset.self,
            DynamicCover.self
        )
        let context = container.mainContext
        let deletedDate = Date(timeIntervalSinceNow: 86_400)
        let nextDate = Date(timeIntervalSinceNow: 2 * 86_400)
        let deleted = try Show(name: "待删除现场", date: deletedDate, startTime: deletedDate)
        let next = try Show(name: "下一场现场", date: nextDate, startTime: nextDate)
        let selection = CurrentShowSelection(selectedShowID: deleted.id)
        context.insert(deleted)
        context.insert(next)
        context.insert(selection)
        try context.save()

        var widgetShowIDs: [UUID] = []
        var widgetSelectionID: UUID?
        let effects = CurrentShowPostCommitEffects(
            reconcileNotifications: { _ in
                let verificationContext = ModelContext(container)
                let storedShows = (try? verificationContext.fetch(FetchDescriptor<Show>())) ?? []
                let storedSelections = (try? verificationContext
                    .fetch(FetchDescriptor<CurrentShowSelection>())) ?? []

                XCTAssertEqual(storedShows.map(\.id), [next.id])
                XCTAssertEqual(storedSelections.first?.selectedShowID, next.id)
                return true
            },
            syncWidget: { shows, durableSelection in
                widgetShowIDs = shows.map(\.id)
                widgetSelectionID = durableSelection?.selectedShowID
                return true
            }
        )

        let result = try await ShowDeletionCoordinator.delete(
            deleted,
            from: [deleted, next],
            selections: [selection],
            notificationStates: [],
            in: context,
            effects: effects
        )

        XCTAssertEqual(result, .complete(didSync: true))
        XCTAssertEqual(widgetShowIDs, [next.id])
        XCTAssertEqual(widgetSelectionID, next.id)
    }

    func testDuplicateMatcherNormalizesFormattingAndRejectsNearDuplicates() throws {
        let start = Date(timeIntervalSince1970: 2_000_100_000)
        let first = try Show(
            name: "TEST Live",
            date: start,
            startTime: start,
            city: "上海",
            venueName: "MAO Livehouse",
            artists: [ArtistSlot(name: "Example Band")]
        )
        let formattingVariant = try Show(
            name: "test-live",
            date: start,
            startTime: start,
            city: "上海",
            venueName: "MAO Livehouse",
            artists: [ArtistSlot(name: "example band")]
        )
        let otherVenue = try Show(
            name: "TEST Live",
            date: start,
            startTime: start,
            city: "上海",
            venueName: "另一场馆",
            artists: [ArtistSlot(name: "Example Band")]
        )
        let nextNight = try Show(
            name: "TEST Live",
            date: start.addingTimeInterval(86_400),
            startTime: start.addingTimeInterval(86_400),
            city: "上海",
            venueName: "MAO Livehouse",
            artists: [ArtistSlot(name: "Example Band")]
        )

        XCTAssertTrue(ShowDuplicateMatcher.isDuplicate(first, formattingVariant))
        XCTAssertFalse(ShowDuplicateMatcher.isDuplicate(first, otherVenue))
        XCTAssertFalse(ShowDuplicateMatcher.isDuplicate(first, nextNight))
    }

    @MainActor
    func testAddShowPersistenceRejectsSecondLogicalDuplicate() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let now = Date()
        let start = now.addingTimeInterval(7 * 86_400)
        let first = try Show(
            name: "重复现场",
            date: start,
            startTime: start,
            city: "上海",
            venueName: "测试场馆",
            artists: [ArtistSlot(name: "测试艺人")]
        )
        let duplicate = try Show(
            name: " 重复现场 ",
            date: start,
            startTime: start,
            city: "上海",
            venueName: "测试场馆",
            artists: [ArtistSlot(name: "测试艺人")]
        )

        _ = try AddShowPersistenceCoordinator.persist(
            first,
            lifecycle: .future,
            selections: [],
            notificationStates: [],
            in: context,
            now: now
        )
        let selections = try context.fetch(FetchDescriptor<CurrentShowSelection>())
        let notificationStates = try context.fetch(FetchDescriptor<NotificationSchedulingState>())

        XCTAssertThrowsError(
            try AddShowPersistenceCoordinator.persist(
                duplicate,
                lifecycle: .future,
                selections: selections,
                notificationStates: notificationStates,
                in: context,
                now: now
            )
        ) { error in
            XCTAssertEqual(
                error as? AddShowPersistenceError,
                .duplicateShow(existingShowID: first.id)
            )
        }
        XCTAssertEqual(try context.fetch(FetchDescriptor<Show>()).count, 1)
    }

    @MainActor
    func testAddingAnotherShowDoesNotStealDurableCurrentShow() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let now = Date()
        let currentDate = now.addingTimeInterval(3 * 86_400)
        let addedDate = now.addingTimeInterval(86_400)
        let current = try Show(name: "用户当前", date: currentDate, startTime: currentDate)
        let selection = CurrentShowSelection(selectedShowID: current.id)
        context.insert(current)
        context.insert(selection)
        try context.save()

        let added = try Show(name: "新加入", date: addedDate, startTime: addedDate)
        let result = try AddShowPersistenceCoordinator.persist(
            added,
            lifecycle: .future,
            selections: [selection],
            notificationStates: [],
            in: context,
            now: now
        )

        XCTAssertEqual(result.outcome, .future)
        XCTAssertEqual(selection.selectedShowID, current.id)
        XCTAssertEqual(result.notificationState?.stagedBackfillShowID, added.id)
    }

    @MainActor
    func testFirstUpcomingShowBecomesCurrentAndStagesOnlyItsBackfillHandoff() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let now = Date()
        let start = now.addingTimeInterval(3 * 86_400)
        let show = try Show(name: "第一场", date: start, startTime: start)

        let result = try AddShowPersistenceCoordinator.persist(
            show,
            lifecycle: .future,
            selections: [],
            notificationStates: [],
            in: context,
            now: now
        )

        let selection = try XCTUnwrap(
            context.fetch(FetchDescriptor<CurrentShowSelection>()).first
        )
        XCTAssertEqual(selection.selectedShowID, show.id)
        XCTAssertEqual(result.notificationState?.stagedBackfillShowID, show.id)
        XCTAssertEqual(result.outcome, .future)
    }

    @MainActor
    func testDeletionKeepsContentDuplicateWithDistinctIDs() async throws {
        let container = try makeContainer(
            MemoryFragment.self,
            MemoryMediaItem.self,
            ShowAsset.self,
            DynamicCover.self
        )
        let context = container.mainContext
        let start = Date(timeIntervalSinceNow: 7 * 86_400)
        let first = try Show(name: "历史重复现场", date: start, startTime: start)
        let second = try Show(name: "历史重复现场", date: start, startTime: start)
        context.insert(first)
        context.insert(second)
        try context.save()

        let effects = CurrentShowPostCommitEffects(
            reconcileNotifications: { _ in true },
            syncWidget: { _, _ in true }
        )
        _ = try await ShowDeletionCoordinator.delete(
            first,
            from: [first, second],
            selections: [],
            notificationStates: [],
            in: context,
            effects: effects
        )

        let remaining = try context.fetch(FetchDescriptor<Show>())
        XCTAssertEqual(remaining.count, 1)
        XCTAssertEqual(remaining.first?.persistentModelID, second.persistentModelID)
    }

    @MainActor
    func testDeletionKeepsLegacyRowThatSharesBusinessUUID() async throws {
        let container = try makeContainer(
            MemoryFragment.self,
            MemoryMediaItem.self,
            ShowAsset.self,
            DynamicCover.self
        )
        let context = container.mainContext
        let sharedID = UUID()
        let firstStart = Date(timeIntervalSinceNow: 7 * 86_400)
        let secondStart = Date(timeIntervalSinceNow: 8 * 86_400)
        let first = try Show(
            id: sharedID,
            name: "坏数据 A",
            date: firstStart,
            startTime: firstStart
        )
        let second = try Show(
            id: sharedID,
            name: "坏数据 B",
            date: secondStart,
            startTime: secondStart
        )
        let selection = CurrentShowSelection(selectedShowID: sharedID)
        context.insert(first)
        context.insert(second)
        context.insert(selection)
        try context.save()

        let effects = CurrentShowPostCommitEffects(
            reconcileNotifications: { _ in true },
            syncWidget: { _, _ in true }
        )
        _ = try await ShowDeletionCoordinator.delete(
            first,
            from: [first, second],
            selections: [selection],
            notificationStates: [],
            in: context,
            effects: effects
        )

        let remaining = try context.fetch(FetchDescriptor<Show>())
        XCTAssertEqual(remaining.count, 1)
        XCTAssertEqual(remaining.first?.persistentModelID, second.persistentModelID)
        XCTAssertEqual(selection.selectedShowID, sharedID)
    }
}

private extension ShowDraft {
    func renaming(to name: String) -> ShowDraft {
        var draft = self
        draft.name = name
        return draft
    }
}
