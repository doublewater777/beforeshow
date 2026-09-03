import SwiftData
import XCTest
@testable import BeforeShow

@MainActor
final class ListeningShowMutationIntegrationTests: XCTestCase {
    func testShowMutationCoordinatorInvalidatesOpeningStateInSameTransaction() async throws {
        let container = try ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let now = Date()
        let start = now.addingTimeInterval(-3_600)
        let show = try Show(
            name: "Canceled",
            date: start,
            startTime: start,
            artists: [ArtistSlot(name: "A", avatarURL: nil, appleMusicArtistID: "a")]
        )
        context.insert(show)
        context.insert(ShowOpeningFamiliarityBaseline(
            showID: show.id,
            effectiveStartAtCapture: start,
            familiarSongIDsAtCapture: []
        ))
        context.insert(ShowOpeningArtistTier(
            showID: show.id,
            artistID: "a",
            artistNameAtCapture: "A",
            tierRawValue: ListeningFamiliarityTier.firstEncounter.rawValue,
            baselineCapturedAt: now,
            catalogSnapshotFetchedAt: now
        ))
        try context.save()

        let effects = CurrentShowPostCommitEffects(
            reconcileNotifications: { _ in true },
            syncWidget: { _, _ in true }
        )
        _ = try await ShowMutationCoordinator.commitCurrentShowChange(
            shows: [show],
            selections: [],
            notificationStates: [],
            in: context,
            effects: effects
        ) {
            show.changeStatus = .canceled
        }

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ShowOpeningFamiliarityBaseline>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ShowOpeningArtistTier>()), 0)
    }
}
