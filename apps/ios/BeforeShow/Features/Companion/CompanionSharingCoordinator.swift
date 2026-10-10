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
    private(set) var isLoadingInvitation = false
    private(set) var invitePresentationGeneration = 0
    private var canceledPresentationGeneration: Int?
    private var loadingShareKey: String?
    private var loadingShareGeneration: Int?
    private(set) var lastErrorMessage: String?
    private(set) var lastErrorKind: CompanionSharingError?

    private var pendingShareMetadata: [CKShare.Metadata]
    private var pendingJoinMetadataKey: String?
    private var isFlushingAcceptedShares = false
    private let userDefaults: UserDefaults
    private let usesKeychainCloudSyncMarker: Bool

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
        do {
            return try await CompanionInvitationPreparation.run(
                service: service, show: show,
                preferredParticipantName: preferredParticipantName,
                ownerDisplayName: ownerDisplayName,
                in: modelContext
            )
        } catch {
            recordError(error)
            throw error
        }
    }

    func shareSystemFieldsForResend(show: Show) async throws -> Data {
        let attempt = CompanionAnalyticsAttempt(
            .invitation, source: "resend", sessionRecordName: show.companionCloudRecordName
        )
        do {
            guard let shareLocator = show.companionShareLocator else {
                throw CompanionSharingError.sessionNotFound
            }
            attempt.stage = "cloud_load"
            let data = try await attempt.withCloudDiagnostics {
                try await service.loadShareSystemFields(shareLocator: shareLocator)
            }
            attempt.finish(.succeeded)
            return data
        } catch {
            attempt.finish(.failed, error: error)
            throw error
        }
    }

    func handleAcceptedShare(
        metadata: CKShare.Metadata,
        participantDisplayName: String?,
        importStrategy: CompanionAcceptedImportStrategy = .automatic,
        in modelContext: ModelContext
    ) async {
        enableCloudSync()
        do {
            let (session, importResult) = try await CompanionJoinOperation.run(
                source: "confirmation", in: modelContext, strategy: importStrategy
            ) { attempt in
                attempt.linkSession(metadata.hierarchicalRootRecordID?.recordName)
                return try await service.acceptShare(
                    metadata: metadata,
                    participantDisplayName: participantDisplayName
                )
            }
            pendingAcceptResult = importResult
            pendingAcceptMessage = CompanionSharingPresentation.acceptedMessage(
                ownerDisplayName: session.ownerDisplayName,
                importResult: importResult
            )
            lastErrorMessage = nil
            lastErrorKind = nil
        } catch {
            pendingAcceptResult = nil
            pendingAcceptMessage = nil
            recordError(error, fallback: .acceptFailed)
        }
    }

    func enqueueAcceptedShare(
        _ metadata: CKShare.Metadata,
        startsNewPresentation: Bool = true
    ) {
        enableCloudSync()
        let key = CompanionAcceptedShareInbox.metadataKey(metadata)
        guard !pendingShareMetadata.contains(where: { CompanionAcceptedShareInbox.metadataKey($0) == key }) else {
            return
        }
        if !isLoadingInvitation && pendingJoinSession == nil && pendingJoinMetadataKey == nil {
            beginInvitePresentationIfNeeded(forceNew: startsNewPresentation)
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
        guard !isFlushingAcceptedShares, pendingJoinSession == nil, pendingJoinMetadataKey == nil else { return }
        guard let metadata = pendingShareMetadata.first else { return }
        beginInvitePresentationIfNeeded()
        isFlushingAcceptedShares = true
        var resumeQueue = false
        defer {
            isFlushingAcceptedShares = false
            loadingShareKey = nil
            loadingShareGeneration = nil
            if resumeQueue {
                continuePendingShareDrain(in: modelContext)
            }
        }

        let key = CompanionAcceptedShareInbox.metadataKey(metadata)
        loadingShareKey = key
        loadingShareGeneration = invitePresentationGeneration
        lastErrorKind = nil
        do {
            let session = try await service.previewAcceptedShare(
                metadata: metadata,
                participantDisplayName: nil
            )
            guard pendingShareMetadata.contains(where: { CompanionAcceptedShareInbox.metadataKey($0) == key }) else {
                isLoadingInvitation = false
                resumeQueue = true
                return
            }

            if resolvePreviewedShareForExistingLocalShow(session, in: modelContext) {
                isLoadingInvitation = false
                pendingJoinMetadataKey = key
                removePendingShare(key: key)
                return
            }

            pendingJoinSession = session
            isLoadingInvitation = false
            pendingJoinMetadataKey = key
            lastErrorMessage = nil
            lastErrorKind = nil
        } catch {
            isLoadingInvitation = false
            guard pendingShareMetadata.contains(where: { CompanionAcceptedShareInbox.metadataKey($0) == key }) else {
                resumeQueue = true
                return
            }
            recordError(error, fallback: .statusSyncPending)
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
                || ($0.companionShareRecordName != nil && $0.companionShareRecordName == session.shareLocator?.recordName)
                || ($0.id.uuidString == session.show.showID && ($0.companionStatus == .confirmed || $0.companionIsOwner == true))
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

    func confirmPendingJoin(
        in modelContext: ModelContext,
        importStrategy: CompanionAcceptedImportStrategy = .automatic
    ) async -> Bool {
        guard let key = pendingJoinMetadataKey,
              let metadata = pendingShareMetadata.first(where: {
                  CompanionAcceptedShareInbox.metadataKey($0) == key
              }) else {
            return false
        }

        await handleAcceptedShare(
            metadata: metadata,
            participantDisplayName: CompanionUserProfile.nickname,
            importStrategy: importStrategy,
            in: modelContext
        )
        guard lastErrorKind == nil, pendingAcceptResult != nil else {
            resolvePendingInviteFailure(key: key, clearJoin: true, in: modelContext)
            return false
        }

        pendingJoinSession = nil
        removePendingShare(key: key)
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
        removePendingShare(key: key)
        lastErrorMessage = nil
        lastErrorKind = nil
        return true
    }

    var hasPendingAcceptedShares: Bool { !pendingShareMetadata.isEmpty }

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
                resetShowCompanionLinkage(show)
            } catch {
                recordError(error)
                throw error
            }
        } else {
            resetShowCompanionLinkage(show)
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
               let shareLocator = show.companionShareLocator ?? session.shareLocator {
                do {
                    _ = try await service.cancelSession(
                        sessionLocator: sessionLocator,
                        shareLocator: shareLocator,
                        isOwner: isOwnerRole
                    )
                    resetShowCompanionLinkage(show)
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
                    show.companionIsOwner = isOwnerRole
                    try modelContext.save()
                    recordError(error)
                    return
                }
            }

            show.applyCompanionSession(session, isOwner: isOwnerRole)
            if session.status == .canceled {
                resetShowCompanionLinkage(show)
            }
            try modelContext.save()
            lastErrorMessage = membershipWarning
            lastErrorKind = membershipWarning == nil ? nil : .permissionDenied
        } catch let error as CompanionSharingError
            where error == .sessionNotFound
                || (error == .permissionDenied && show.companionIsOwner == false) {
            resetShowCompanionLinkage(show)
            try? modelContext.save()
            lastErrorMessage = nil
            lastErrorKind = nil
        } catch {
            recordError(error)
        }
    }

    func refreshAllLinkedShows(in modelContext: ModelContext, refreshLinks: Bool = true) async {
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
                _ = try? CompanionAcceptedSessionImporter.apply(session, in: modelContext)
            }
        } catch {
            CompanionDebugLog.write("refreshAllLinkedShows: \(error)")
        }
        guard refreshLinks else { return }
        guard let shows = try? modelContext.fetch(descriptor) else { return }
        for show in shows where show.companionCloudRecordName != nil {
            await refreshCompanion(for: show, in: modelContext)
        }
    }

    func handleShareControllerDidStopSharing(
        for show: Show,
        in modelContext: ModelContext
    ) async {
        resetShowCompanionLinkage(show)
        try? modelContext.save()
    }

    private func resetShowCompanionLinkage(_ show: Show) {
        if show.companionStatus == .pending || show.companionStatus == .confirmed {
            try? show.cancelCompanion()
        }
        show.clearCompanionCloudLinkage()
    }

    func handleShareControllerFailure(_ error: Error) {
        CompanionDebugLog.write("Share controller failed: \(error)")
        recordError(error)
    }

    private(set) var currentUserDisplayName: String?

    func fetchCurrentUserDisplayName() async -> String? {
        if let currentUserDisplayName { return currentUserDisplayName }
        let name = await service.fetchCurrentUserDisplayName()
        if let name { currentUserDisplayName = name }
        return name
    }

    func handleIncomingInviteFailure(_ error: Error) {
        isLoadingInvitation = false
        pendingAcceptResult = nil
        pendingAcceptMessage = nil
        recordError(error, fallback: .acceptFailed)
    }

    @discardableResult
    func beginLoadingInvitation() -> Int {
        pendingAcceptMessage = nil
        pendingAcceptResult = nil
        lastErrorMessage = nil
        lastErrorKind = nil
        beginInvitePresentationIfNeeded(forceNew: true)
        return invitePresentationGeneration
    }

    private func beginInvitePresentationIfNeeded(forceNew: Bool = false) {
        if forceNew || (!isLoadingInvitation && pendingJoinSession == nil) {
            invitePresentationGeneration &+= 1
            canceledPresentationGeneration = nil
        }
        if pendingJoinSession == nil { isLoadingInvitation = true }
    }

    func cancelLoadingInvitationPresentation() {
        guard pendingJoinSession == nil else { return }
        canceledPresentationGeneration = invitePresentationGeneration
        isLoadingInvitation = false
        if loadingShareGeneration == invitePresentationGeneration,
           let loadingShareKey {
            removePendingShare(key: loadingShareKey)
        }
        lastErrorMessage = nil
        lastErrorKind = nil
    }

    func isInvitePresentationActive(_ generation: Int) -> Bool {
        generation == invitePresentationGeneration
            && canceledPresentationGeneration != generation
    }

    private func recordError(_ error: Error, fallback: CompanionSharingError? = nil) {
        lastErrorMessage = Self.userMessage(for: error)
        lastErrorKind = error as? CompanionSharingError ?? fallback
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
        guard CompanionPendingInviteDrainPolicy.action(
            for: lastErrorKind,
            remainingInviteCount: pendingShareMetadata.count - 1
        ).discardsCurrent else { return }
        if clearJoin { pendingJoinSession = nil }
        pendingJoinMetadataKey = key
        removePendingShare(key: key)
    }
    func finishPendingJoinPresentation(in modelContext: ModelContext) {
        guard pendingJoinSession == nil, pendingJoinMetadataKey != nil else { return }
        pendingJoinMetadataKey = nil
        continuePendingShareDrain(in: modelContext)
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
}
