import CloudKit
import Foundation
import SwiftData

@MainActor
@Observable
final class CompanionSharingCoordinator {
    private let service: any CompanionSharingService
    private let explicitContainer: CKContainer?
    var container: CKContainer {
        explicitContainer ?? (service as? CloudKitCompanionSharingService)?.container ?? CKContainer(identifier: CloudKitCompanionSharingService.defaultContainerIdentifier)
    }

    private(set) var pendingAcceptMessage: String?
    private(set) var pendingAcceptResult: CompanionAcceptedImportResult?
    private(set) var pendingJoinSession: CompanionSessionSnapshot?
    private(set) var lastErrorMessage: String?
    private(set) var lastErrorKind: CompanionSharingError?

    private var pendingShareMetadata: [CKShare.Metadata]
    private var pendingJoinMetadataKey: String?
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

    func prepareInvitation(
        for show: Show,
        preferredParticipantName: String?,
        ownerDisplayName: String?,
        in modelContext: ModelContext
    ) async throws -> CompanionPreparedShare {
        enableCloudSync()
        let snapshotBefore = show.companionStateSnapshot()
        let cloudBefore = show.companionCloudLinkageSnapshot()

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

    func handleAcceptedShare(
        metadata: CKShare.Metadata,
        participantDisplayName: String?,
        in modelContext: ModelContext
    ) async {
        enableCloudSync()
        do {
            let session = try await service.acceptShare(
                metadata: metadata,
                participantDisplayName: participantDisplayName
            )
            let importResult = try CompanionAcceptedSessionImporter.apply(session, in: modelContext)
            pendingAcceptResult = importResult
            pendingAcceptMessage = CompanionSharingPresentation.acceptedMessage(
                ownerDisplayName: session.ownerDisplayName,
                importResult: importResult
            )
            lastErrorMessage = nil
            lastErrorKind = nil
        } catch {
            pendingAcceptResult = nil
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
        guard !isFlushingAcceptedShares, pendingJoinSession == nil else { return }
        guard let metadata = pendingShareMetadata.first else { return }
        isFlushingAcceptedShares = true
        defer { isFlushingAcceptedShares = false }

        let key = CompanionAcceptedShareInbox.metadataKey(metadata)
        lastErrorKind = nil
        do {
            let session = try await service.previewAcceptedShare(
                metadata: metadata,
                participantDisplayName: nil
            )

            if resolvePreviewedShareForExistingLocalShow(session, in: modelContext) {
                removePendingShare(key: key)
                continuePendingShareDrain(in: modelContext)
                return
            }

            pendingJoinSession = session
            pendingJoinMetadataKey = key
            lastErrorMessage = nil
            lastErrorKind = nil
        } catch {
            lastErrorMessage = Self.userMessage(for: error)
            lastErrorKind = error as? CompanionSharingError ?? .statusSyncPending
            resolvePendingInviteFailure(key: key, clearJoin: false, in: modelContext)
        }
    }

    @discardableResult
    func resolvePreviewedShareForExistingLocalShow(
        _ session: CompanionSessionSnapshot,
        in modelContext: ModelContext,
        now: Date = Date()
    ) -> Bool {
        let shows = (try? modelContext.fetch(FetchDescriptor<Show>())) ?? []
        guard let existing = shows.first(where: {
            $0.companionCloudRecordName == session.sessionLocator.recordName
        }) else {
            return false
        }

        let wasHistorical = existing.wasAddedAsHistorical == true
            || CurrentShowTimeState(show: existing, now: now).kind == .ended
        pendingAcceptResult = CompanionAcceptedImportResult(
            showID: existing.id,
            inserted: false,
            becameCurrent: false,
            wasHistorical: wasHistorical
        )
        pendingAcceptMessage = CompanionSharingPresentation.alreadyJoinedMessage
        lastErrorMessage = nil
        lastErrorKind = nil
        return true
    }

    func confirmPendingJoin(in modelContext: ModelContext) async -> Bool {
        guard let key = pendingJoinMetadataKey,
              let metadata = pendingShareMetadata.first(where: {
                  CompanionAcceptedShareInbox.metadataKey($0) == key
              }) else {
            return false
        }

        await handleAcceptedShare(
            metadata: metadata,
            participantDisplayName: nil,
            in: modelContext
        )
        guard lastErrorKind == nil, pendingAcceptResult != nil else {
            resolvePendingInviteFailure(key: key, clearJoin: true, in: modelContext)
            return false
        }

        pendingJoinSession = nil
        pendingJoinMetadataKey = nil
        removePendingShare(key: key)
        continuePendingShareDrain(in: modelContext)
        return true
    }

    func declinePendingJoin(in modelContext: ModelContext) async -> Bool {
        guard let key = pendingJoinMetadataKey else {
            pendingJoinSession = nil
            lastErrorMessage = nil
            lastErrorKind = nil
            continuePendingShareDrain(in: modelContext)
            return true
        }
        pendingJoinSession = nil
        pendingJoinMetadataKey = nil
        removePendingShare(key: key)
        lastErrorMessage = nil
        lastErrorKind = nil
        continuePendingShareDrain(in: modelContext)
        return true
    }

    var hasPendingAcceptedShares: Bool { !pendingShareMetadata.isEmpty }

    static func persistAcceptedShare(
        _ metadata: CKShare.Metadata,
        userDefaults: UserDefaults = .standard
    ) {
        CompanionAcceptedShareInbox.append(metadata, to: userDefaults)
        CompanionCloudSyncMarker.enable(in: userDefaults, usesKeychain: true)
    }

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
        if pendingJoinSession != nil { return }

        let descriptor = FetchDescriptor<Show>()
        guard let shows = try? modelContext.fetch(descriptor) else { return }
        let hasLocalCompanionLink = shows.contains { $0.companionCloudRecordName != nil }
        if hasLocalCompanionLink {
            enableCloudSync()
        }
        guard hasLocalCompanionLink || hasPendingAcceptedShares || isCloudSyncEnabled else {
            return
        }

        do {
            let sessions = try await service.listAcceptedSharedSessions()
            for session in sessions where session.status == .accepted {
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

    func consumePendingAcceptResult() -> CompanionAcceptedImportResult? {
        let result = pendingAcceptResult
        pendingAcceptResult = nil
        return result
    }

    func consumeLastErrorMessage() -> String? {
        let message = lastErrorMessage
        lastErrorMessage = nil
        return message
    }

    private func removePendingShare(key: String) {
        pendingShareMetadata.removeAll {
            CompanionAcceptedShareInbox.metadataKey($0) == key
        }
        CompanionAcceptedShareInbox.persist(pendingShareMetadata, to: userDefaults)
    }

    private func resolvePendingInviteFailure(
        key: String,
        clearJoin: Bool,
        in modelContext: ModelContext
    ) {
        let action = CompanionPendingInviteDrainPolicy.action(
            for: lastErrorKind,
            remainingInviteCount: pendingShareMetadata.count - 1
        )
        guard action.discardsCurrent else { return }
        if clearJoin {
            pendingJoinSession = nil
            pendingJoinMetadataKey = nil
        }
        removePendingShare(key: key)
        if action.continues {
            continuePendingShareDrain(in: modelContext)
        }
    }

    private func continuePendingShareDrain(in modelContext: ModelContext) {
        guard !pendingShareMetadata.isEmpty else { return }
        Task { @MainActor [weak self] in
            await Task.yield()
            await self?.flushPendingAcceptedShares(in: modelContext)
        }
    }

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
                return .removed
            }
            return .warning(CompanionSharingPresentation.membershipSyncWarning)
        }
    }

    static func userMessage(for error: Error) -> String {
        CompanionSharingPresentation.userMessage(for: error)
    }
}
