import CloudKit
import Foundation
import SwiftData

/// Orchestrates CloudKit companion invite / accept / cancel against local `Show` cache.
@MainActor
@Observable
final class CompanionSharingCoordinator {
    private let service: any CompanionSharingService
    private let explicitContainer: CKContainer?
    var container: CKContainer {
        explicitContainer ?? (service as? CloudKitCompanionSharingService)?.container ?? CKContainer(identifier: CloudKitCompanionSharingService.defaultContainerIdentifier)
    }

    private(set) var pendingAcceptMessage: String?
    private(set) var lastErrorMessage: String?
    private(set) var lastErrorKind: CompanionSharingError?

    /// Share metadata waiting for successful acceptance/apply.
    private var pendingShareMetadata: [CKShare.Metadata]
    private var isFlushingAcceptedShares = false
    private let userDefaults: UserDefaults
    private let usesKeychainCloudSyncMarker: Bool

    static let cloudSyncEnabledKey = CompanionCloudSyncMarker.userDefaultsKey

    init(
        service: any CompanionSharingService = CloudKitCompanionSharingService.live(),
        container: CKContainer? = nil,
        userDefaults: UserDefaults = .standard,
        usesKeychainCloudSyncMarker: Bool = true
    ) {
        self.service = service
        self.explicitContainer = container
        self.userDefaults = userDefaults
        self.usesKeychainCloudSyncMarker = usesKeychainCloudSyncMarker
        self.pendingShareMetadata = CompanionAcceptedShareInbox.load(from: userDefaults)
        if !pendingShareMetadata.isEmpty {
            enableCloudSync()
        }
    }

    // MARK: Invite (owner)

    func prepareInvitation(
        for show: Show,
        preferredParticipantName: String?,
        ownerDisplayName: String?,
        in modelContext: ModelContext
    ) async throws -> CompanionPreparedShare {
        // This method is reached from an explicit "邀请同行" action. Persisting the
        // opt-in before the remote mutation also preserves recovery if the process is
        // terminated after CloudKit creates the session but before local linkage saves.
        enableCloudSync()
        let snapshotBefore = show.companionStateSnapshot()
        let cloudBefore = show.companionCloudLinkageSnapshot()

        // Non-mutating validation outside the rollback scope.
        if show.companionStatus == .canceled, show.companionShareLocator != nil {
            throw CompanionSharingError.conflict
        }

        do {
            switch show.companionStatus {
            case .none, .canceled:
                try show.markCompanionInvitationSent(name: preferredParticipantName)
            case .pending:
                show.applyCompanionState(status: .pending, name: preferredParticipantName)
            case .confirmed:
                throw ShowCompanionMutationError.invalidTransition(from: .confirmed, to: .pending)
            }
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }

        do {
            let prepared = try await service.prepareInvitation(
                show: CompanionShowSnapshot(show: show),
                ownerDisplayName: ownerDisplayName,
                preferredParticipantName: preferredParticipantName
            )
            show.applyCompanionSession(
                prepared.session,
                isOwner: true,
                preferredName: preferredParticipantName
            )
            try modelContext.save()
            return prepared
        } catch {
            show.restoreCompanionState(status: snapshotBefore.status, names: snapshotBefore.names)
            show.restoreCompanionCloudLinkage(cloudBefore)
            try? modelContext.save()
            lastErrorMessage = Self.userMessage(for: error)
            lastErrorKind = error as? CompanionSharingError
            throw error
        }
    }

    func shareSystemFieldsForResend(show: Show) async throws -> Data {
        guard let shareLocator = show.companionShareLocator else {
            throw CompanionSharingError.sessionNotFound
        }
        return try await service.loadShareSystemFields(shareLocator: shareLocator)
    }

    // MARK: Accept (participant)

    func handleAcceptedShare(
        metadata: CKShare.Metadata,
        participantDisplayName: String?,
        in modelContext: ModelContext
    ) async {
        // A share callback is an explicit companion entry point. Keep the recovery
        // marker even if acceptance needs a later retry.
        enableCloudSync()
        do {
            let session = try await service.acceptShare(
                metadata: metadata,
                participantDisplayName: participantDisplayName
            )
            let importResult = try CompanionAcceptedSessionImporter.apply(session, in: modelContext)
            pendingAcceptMessage = CompanionSharingPresentation.acceptedMessage(
                ownerDisplayName: session.ownerDisplayName,
                importResult: importResult
            )
            lastErrorMessage = nil
            lastErrorKind = nil
        } catch {
            lastErrorMessage = Self.userMessage(for: error)
            if let sharing = error as? CompanionSharingError {
                lastErrorKind = sharing
            } else {
                lastErrorKind = .statusSyncPending
            }
        }
    }

    func enqueueAcceptedShare(_ metadata: CKShare.Metadata) {
        enableCloudSync()
        let key = CompanionAcceptedShareInbox.metadataKey(metadata)
        guard !pendingShareMetadata.contains(where: { CompanionAcceptedShareInbox.metadataKey($0) == key }) else {
            return
        }
        pendingShareMetadata.append(metadata)
        CompanionAcceptedShareInbox.persist(pendingShareMetadata, to: userDefaults)
    }

    func reloadPersistedAcceptedShares() {
        for metadata in CompanionAcceptedShareInbox.load(from: userDefaults) {
            enqueueAcceptedShare(metadata)
        }
    }

    func flushPendingAcceptedShares(in modelContext: ModelContext) async {
        guard !isFlushingAcceptedShares else { return }
        guard !pendingShareMetadata.isEmpty else { return }
        isFlushingAcceptedShares = true
        defer { isFlushingAcceptedShares = false }

        var processedKeys = Set<String>()
        while true {
            let batch = pendingShareMetadata.filter {
                !processedKeys.contains(CompanionAcceptedShareInbox.metadataKey($0))
            }
            guard !batch.isEmpty else { break }

            for metadata in batch {
                let key = CompanionAcceptedShareInbox.metadataKey(metadata)
                processedKeys.insert(key)
                lastErrorKind = nil
                await handleAcceptedShare(
                    metadata: metadata,
                    participantDisplayName: nil,
                    in: modelContext
                )
                let shouldRetry: Bool
                switch lastErrorKind {
                case .iCloudAccountUnavailable, .networkFailure, .conflict, .statusSyncPending, .sharePreparationFailed:
                    shouldRetry = true
                case .none, .acceptFailed, .sessionNotFound,
                        .invalidPayload, .permissionDenied:
                    // Invalid payload and permission denial are terminal after compensating leave.
                    shouldRetry = false
                }
                if !shouldRetry {
                    pendingShareMetadata.removeAll {
                        CompanionAcceptedShareInbox.metadataKey($0) == key
                    }
                    CompanionAcceptedShareInbox.persist(pendingShareMetadata, to: userDefaults)
                }
            }
        }
        CompanionAcceptedShareInbox.persist(pendingShareMetadata, to: userDefaults)
    }

    var hasPendingAcceptedShares: Bool { !pendingShareMetadata.isEmpty }

    /// Used when a cold-launch scene callback arrives before the coordinator is installed.
    static func persistAcceptedShare(
        _ metadata: CKShare.Metadata,
        userDefaults: UserDefaults = .standard
    ) {
        CompanionAcceptedShareInbox.append(metadata, to: userDefaults)
        CompanionCloudSyncMarker.enable(in: userDefaults, usesKeychain: true)
    }

    // MARK: Cancel / sync

    func cancelCompanion(for show: Show, in modelContext: ModelContext) async throws {
        let isOwner = show.companionIsOwner ?? true
        if let sessionLocator = show.companionSessionLocator {
            do {
                let session = try await service.cancelSession(
                    sessionLocator: sessionLocator,
                    shareLocator: show.companionShareLocator,
                    isOwner: isOwner
                )
                if show.companionStatus == .pending || show.companionStatus == .confirmed {
                    try show.cancelCompanion()
                } else {
                    show.applyCompanionSession(session, isOwner: isOwner)
                }
                // Keep share locator if remote cancel returned one (revocation incomplete).
                if let retained = session.shareLocator, isOwner {
                    show.companionShareRecordName = retained.recordName
                    show.companionShareZoneName = retained.zoneName
                    show.companionShareOwnerName = retained.ownerName
                    show.companionCloudRecordName = session.sessionLocator.recordName
                    show.companionCloudZoneName = session.sessionLocator.zoneName
                    show.companionCloudOwnerName = session.sessionLocator.ownerName
                    show.companionIsOwner = true
                } else {
                    show.clearCompanionCloudLinkage()
                }
            } catch CompanionSharingError.sessionNotFound {
                if show.companionStatus == .pending || show.companionStatus == .confirmed {
                    try show.cancelCompanion()
                }
                show.clearCompanionCloudLinkage()
            } catch {
                lastErrorMessage = Self.userMessage(for: error)
                lastErrorKind = error as? CompanionSharingError
                throw error
            }
        } else {
            try show.cancelCompanion()
            show.clearCompanionCloudLinkage()
        }
        try modelContext.save()
    }

    func refreshCompanion(for show: Show, in modelContext: ModelContext) async {
        guard let sessionLocator = show.companionSessionLocator else { return }
        do {
            let membershipState: CompanionMembershipState
            if show.companionIsOwner == true, let shareLocator = show.companionShareLocator {
                membershipState = await reconcileOwnerShareMembership(shareLocator: shareLocator)
            } else {
                membershipState = .healthy
            }

            if case .removed = membershipState,
               show.companionStatus == .confirmed {
                // Every accepted member left. Close the root and revoke the remaining share
                // so the owner does not keep a phantom confirmed relationship.
                try await cancelCompanion(for: show, in: modelContext)
                lastErrorMessage = CompanionSharingPresentation.companionLeftMessage
                lastErrorKind = .permissionDenied
                return
            }
            let membershipWarning = membershipState.warning

            let session = try await service.fetchSession(sessionLocator: sessionLocator)
            let isOwnerRole = show.companionIsOwner ?? (session.show.showID == show.id.uuidString)

            if session.status == .canceled,
               isOwnerRole,
               let shareLocator = show.companionShareLocator ?? session.shareLocator {
                do {
                    _ = try await service.cancelSession(
                        sessionLocator: sessionLocator,
                        shareLocator: shareLocator,
                        isOwner: true
                    )
                    if show.companionStatus == .pending || show.companionStatus == .confirmed {
                        try? show.cancelCompanion()
                    }
                    show.clearCompanionCloudLinkage()
                    try modelContext.save()
                    lastErrorMessage = membershipWarning
                    lastErrorKind = membershipWarning == nil ? nil : .permissionDenied
                    return
                } catch {
                    if show.companionStatus == .pending || show.companionStatus == .confirmed {
                        try? show.cancelCompanion()
                    }
                    show.companionCloudRecordName = sessionLocator.recordName
                    show.companionCloudZoneName = sessionLocator.zoneName
                    show.companionCloudOwnerName = sessionLocator.ownerName
                    show.companionShareRecordName = shareLocator.recordName
                    show.companionShareZoneName = shareLocator.zoneName
                    show.companionShareOwnerName = shareLocator.ownerName
                    show.companionIsOwner = true
                    try modelContext.save()
                    lastErrorMessage = Self.userMessage(for: error)
                    lastErrorKind = error as? CompanionSharingError
                    return
                }
            }

            if session.status == .canceled,
               isOwnerRole == false,
               let shareLocator = show.companionShareLocator ?? session.shareLocator {
                do {
                    _ = try await service.cancelSession(
                        sessionLocator: sessionLocator,
                        shareLocator: shareLocator,
                        isOwner: false
                    )
                } catch {
                    if show.companionStatus == .pending || show.companionStatus == .confirmed {
                        try? show.cancelCompanion()
                    }
                    show.companionCloudRecordName = sessionLocator.recordName
                    show.companionCloudZoneName = sessionLocator.zoneName
                    show.companionCloudOwnerName = sessionLocator.ownerName
                    show.companionShareRecordName = shareLocator.recordName
                    show.companionShareZoneName = shareLocator.zoneName
                    show.companionShareOwnerName = shareLocator.ownerName
                    show.companionIsOwner = false
                    try modelContext.save()
                    lastErrorMessage = Self.userMessage(for: error)
                    lastErrorKind = error as? CompanionSharingError
                    return
                }
            }

            show.applyCompanionSession(session, isOwner: isOwnerRole)
            if session.status == .canceled {
                if show.companionStatus == .pending || show.companionStatus == .confirmed {
                    try? show.cancelCompanion()
                }
                show.clearCompanionCloudLinkage()
            }
            try modelContext.save()
            lastErrorMessage = membershipWarning
            lastErrorKind = membershipWarning == nil ? nil : .permissionDenied
        } catch let error as CompanionSharingError
            where error == .sessionNotFound
                || (error == .permissionDenied && show.companionIsOwner == false) {
            if show.companionStatus == .pending || show.companionStatus == .confirmed {
                try? show.cancelCompanion()
            }
            show.clearCompanionCloudLinkage()
            try? modelContext.save()
            lastErrorMessage = nil
            lastErrorKind = nil
        } catch {
            lastErrorMessage = Self.userMessage(for: error)
            lastErrorKind = error as? CompanionSharingError
        }
    }

    func refreshAllLinkedShows(in modelContext: ModelContext) async {
        await flushPendingAcceptedShares(in: modelContext)

        let descriptor = FetchDescriptor<Show>()
        guard let shows = try? modelContext.fetch(descriptor) else { return }
        let hasLocalCompanionLink = shows.contains { $0.companionCloudRecordName != nil }
        if hasLocalCompanionLink {
            // Also migrate existing linked shows into the durable marker before any
            // local-store reset can remove the only local linkage evidence.
            enableCloudSync()
        }
        guard hasLocalCompanionLink || hasPendingAcceptedShares || isCloudSyncEnabled else {
            // Do not perform accountStatus() or shared-database discovery for users who
            // have never entered the companion flow.
            return
        }

        do {
            let sessions = try await service.listAcceptedSharedSessions()
            for session in sessions {
                // Recover accepted shared sessions after a reinstall or local-store reset.
                try? CompanionAcceptedSessionImporter.apply(session, in: modelContext)
            }
        } catch {
            lastErrorMessage = Self.userMessage(for: error)
            lastErrorKind = error as? CompanionSharingError
        }
        guard let shows = try? modelContext.fetch(descriptor) else { return }
        for show in shows where show.companionCloudRecordName != nil {
            await refreshCompanion(for: show, in: modelContext)
        }
    }

    func handleShareControllerDidSave(
        share: CKShare?,
        for show: Show,
        in modelContext: ModelContext
    ) async {
        guard let share else {
            await refreshCompanion(for: show, in: modelContext)
            return
        }
        show.companionShareRecordName = share.recordID.recordName
        show.companionShareZoneName = share.recordID.zoneID.zoneName
        show.companionShareOwnerName = share.recordID.zoneID.ownerName
        try? modelContext.save()
        await refreshCompanion(for: show, in: modelContext)
    }

    func handleShareControllerDidStopSharing(
        for show: Show,
        in modelContext: ModelContext
    ) async {
        if show.companionStatus == .pending || show.companionStatus == .confirmed {
            try? show.cancelCompanion()
        }
        show.clearCompanionCloudLinkage()
        try? modelContext.save()
    }

    func handleShareControllerFailure(_ error: Error) {
        CompanionDebugLog.write("Share controller failed: \(error)")
        lastErrorMessage = Self.userMessage(for: error)
        lastErrorKind = error as? CompanionSharingError
    }

    func consumePendingAcceptMessage() -> String? {
        let message = pendingAcceptMessage
        pendingAcceptMessage = nil
        return message
    }

    func consumeLastErrorMessage() -> String? {
        let message = lastErrorMessage
        lastErrorMessage = nil
        return message
    }

    // MARK: Private

    private var isCloudSyncEnabled: Bool {
        CompanionCloudSyncMarker.isEnabled(
            in: userDefaults,
            usesKeychain: usesKeychainCloudSyncMarker
        )
    }

    private func enableCloudSync() {
        CompanionCloudSyncMarker.enable(
            in: userDefaults,
            usesKeychain: usesKeychainCloudSyncMarker
        )
    }

    private func reconcileOwnerShareMembership(
        shareLocator: CompanionRecordLocator
    ) async -> CompanionMembershipState {
        do {
            return try await service.reconcileOwnerMembership(shareLocator: shareLocator)
        } catch {
            if let sharing = error as? CompanionSharingError,
               sharing == .sessionNotFound {
                // The share disappeared on another device; let the owner close the root.
                return .removed
            }
            // Transport failures are non-terminal and must be surfaced as a warning.
            return .warning(CompanionSharingPresentation.membershipSyncWarning)
        }
    }

    static func userMessage(for error: Error) -> String {
        CompanionSharingPresentation.userMessage(for: error)
    }

}

// MARK: - Cloud linkage snapshot helpers



// MARK: - App / scene delegate bridge for CloudKit share acceptance
