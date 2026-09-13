import CloudKit
import SwiftData
import XCTest
@testable import BeforeShow

@MainActor
final class CompanionJoinGateTests: XCTestCase {
    func testPendingSharedSessionIsNotImportedBeforeJoinConfirmation() async throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "CompanionJoinGateTests-\(UUID().uuidString)"))
        defer {
            if let suite = defaults.volatileDomainNames.first(where: { $0.hasPrefix("CompanionJoinGateTests-") }) {
                defaults.removePersistentDomain(forName: suite)
            }
        }
        defaults.set(true, forKey: CompanionCloudSyncMarker.userDefaultsKey)

        let date = Date(timeIntervalSince1970: 2_100_000_000)
        let showSnapshot = CompanionShowSnapshot(
            showID: UUID().uuidString,
            showName: "等待确认的同行现场",
            showDate: date,
            showStartTime: date,
            sourceShowDate: date
        )
        let session = CompanionSessionSnapshot(
            sessionLocator: CompanionRecordLocator(
                recordName: "pending-session",
                ownerName: "owner-token"
            ),
            shareLocator: CompanionRecordLocator(
                recordName: "pending-share",
                ownerName: "owner-token"
            ),
            show: showSnapshot,
            ownerDisplayName: "Alex",
            participantDisplayName: nil,
            participantDisplayNames: [],
            status: .pending,
            createdAt: date.addingTimeInterval(-3_600),
            acceptedAt: nil,
            canceledAt: nil
        )
        let coordinator = CompanionSharingCoordinator(
            service: PendingDiscoveryService(session: session),
            userDefaults: defaults,
            usesKeychainCloudSyncMarker: false
        )

        let configuration = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(
            for: Show.self,
            CurrentShowSelection.self,
            configurations: configuration
        )

        await coordinator.refreshAllLinkedShows(in: container.mainContext)

        XCTAssertTrue(try container.mainContext.fetch(FetchDescriptor<Show>()).isEmpty)
        XCTAssertNil(coordinator.pendingAcceptResult)
        XCTAssertNil(coordinator.pendingAcceptMessage)
    }
}

private struct PendingDiscoveryService: CompanionSharingService {
    let session: CompanionSessionSnapshot

    func prepareInvitation(
        show _: CompanionShowSnapshot,
        ownerDisplayName _: String?,
        preferredParticipantName _: String?
    ) async throws -> CompanionPreparedShare {
        throw CompanionSharingError.sharePreparationFailed
    }

    func loadShareSystemFields(shareLocator _: CompanionRecordLocator) async throws -> Data {
        throw CompanionSharingError.sessionNotFound
    }

    func acceptShare(
        metadata _: CKShare.Metadata,
        participantDisplayName _: String?
    ) async throws -> CompanionSessionSnapshot {
        throw CompanionSharingError.acceptFailed
    }

    func cancelSession(
        sessionLocator _: CompanionRecordLocator,
        shareLocator _: CompanionRecordLocator?,
        isOwner _: Bool
    ) async throws -> CompanionSessionSnapshot {
        throw CompanionSharingError.sessionNotFound
    }

    func fetchSession(sessionLocator _: CompanionRecordLocator) async throws -> CompanionSessionSnapshot {
        throw CompanionSharingError.sessionNotFound
    }

    func listAcceptedSharedSessions() async throws -> [CompanionSessionSnapshot] {
        [session]
    }

    func reconcileOwnerMembership(
        shareLocator _: CompanionRecordLocator
    ) async throws -> CompanionMembershipState {
        .healthy
    }
}
