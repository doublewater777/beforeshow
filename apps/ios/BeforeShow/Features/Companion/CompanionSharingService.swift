import CloudKit
import Foundation

// MARK: - Service protocol

protocol CompanionSharingService: Sendable {
    func prepareInvitation(
        show: CompanionShowSnapshot,
        ownerDisplayName: String?,
        preferredParticipantName: String?
    ) async throws -> CompanionPreparedShare

    func loadShareSystemFields(shareLocator: CompanionRecordLocator) async throws -> Data

    /// Read the frozen invitation payload without accepting the CloudKit share.
    /// Product membership is not committed until `acceptShare` runs after the user taps
    /// the in-app join action.
    func previewAcceptedShare(
        metadata: CKShare.Metadata,
        participantDisplayName: String?
    ) async throws -> CompanionSessionSnapshot

    func acceptShare(
        metadata: CKShare.Metadata,
        participantDisplayName: String?
    ) async throws -> CompanionSessionSnapshot

    func cancelSession(
        sessionLocator: CompanionRecordLocator,
        shareLocator: CompanionRecordLocator?,
        isOwner: Bool
    ) async throws -> CompanionSessionSnapshot

    func fetchSession(sessionLocator: CompanionRecordLocator) async throws -> CompanionSessionSnapshot

    /// Discover already-accepted shared companion sessions for startup recovery.
    func listAcceptedSharedSessions() async throws -> [CompanionSessionSnapshot]

    /// Reconcile the owner-side share. Multiple accepted members are a valid group.
    func reconcileOwnerMembership(
        shareLocator: CompanionRecordLocator
    ) async throws -> CompanionMembershipState
}

extension CompanionSharingService {
    /// Non-CloudKit test doubles can retain the old single-step behavior unless a test
    /// specifically exercises the preview phase.
    func previewAcceptedShare(
        metadata: CKShare.Metadata,
        participantDisplayName: String?
    ) async throws -> CompanionSessionSnapshot {
        try await acceptShare(
            metadata: metadata,
            participantDisplayName: participantDisplayName
        )
    }
}
