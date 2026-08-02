import CloudKit
import Foundation
import SwiftData
import UIKit

/// Orchestrates CloudKit companion invite / accept / cancel against local `Show` cache.
@MainActor
@Observable
final class CompanionSharingCoordinator {
    private let service: any CompanionSharingService
    private let container: CKContainer

    private(set) var pendingAcceptMessage: String?
    private(set) var lastErrorMessage: String?
    private(set) var lastErrorKind: CompanionSharingError?

    /// Share metadata that arrived before the model container was ready.
    private var pendingShareMetadata: [CKShare.Metadata] = []

    init(
        service: any CompanionSharingService = CloudKitCompanionSharingService.live(),
        container: CKContainer = CKContainer(
            identifier: CloudKitCompanionSharingService.defaultContainerIdentifier
        )
    ) {
        self.service = service
        self.container = container
    }

    // MARK: Invite (owner)

    /// Creates CloudKit session + share, updates local show to pending, returns share data for UI.
    func prepareInvitation(
        for show: Show,
        preferredParticipantName: String?,
        ownerDisplayName: String?,
        in modelContext: ModelContext
    ) async throws -> CompanionPreparedShare {
        let snapshotBefore = show.companionStateSnapshot()
        let cloudBefore = show.companionCloudLinkageSnapshot()

        do {
            switch show.companionStatus {
            case .none, .canceled:
                try show.markCompanionInvitationSent(name: preferredParticipantName)
            case .pending:
                // Keep local pending while (re)creating a CloudKit share.
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
            show.restoreCompanionState(status: snapshotBefore.status, name: snapshotBefore.name)
            show.restoreCompanionCloudLinkage(cloudBefore)
            try? modelContext.save()
            lastErrorMessage = Self.userMessage(for: error)
            throw error
        }
    }

    func shareSystemFieldsForResend(show: Show) async throws -> Data {
        guard let shareLocator = show.companionShareLocator else {
            throw CompanionSharingError.sessionNotFound
        }
        do {
            return try await service.loadShareSystemFields(shareLocator: shareLocator)
        } catch {
            // Preserve the original error class so UI does not recreate on network/auth failures.
            throw error
        }
    }

    // MARK: Accept (participant)

    func handleAcceptedShare(
        metadata: CKShare.Metadata,
        participantDisplayName: String?,
        in modelContext: ModelContext
    ) async {
        do {
            let session = try await service.acceptShare(
                metadata: metadata,
                participantDisplayName: participantDisplayName
            )
            try applyAcceptedSession(session, in: modelContext)
            pendingAcceptMessage = "已与\(session.ownerDisplayName ?? "朋友")确认同行"
            lastErrorMessage = nil
            lastErrorKind = nil
        } catch {
            lastErrorMessage = Self.userMessage(for: error)
            lastErrorKind = error as? CompanionSharingError
        }
    }

    /// Queue or process share metadata depending on whether dependencies are ready.
    func enqueueAcceptedShare(_ metadata: CKShare.Metadata) {
        pendingShareMetadata.append(metadata)
    }

    func flushPendingAcceptedShares(in modelContext: ModelContext) async {
        guard !pendingShareMetadata.isEmpty else { return }
        let batch = pendingShareMetadata
        pendingShareMetadata.removeAll()
        var retryable: [CKShare.Metadata] = []
        for metadata in batch {
            lastErrorKind = nil
            await handleAcceptedShare(
                metadata: metadata,
                participantDisplayName: nil,
                in: modelContext
            )
            // Requeue typed retryable failures (network / conflict / status sync).
            if let kind = lastErrorKind {
                switch kind {
                case .networkFailure, .conflict, .statusSyncPending, .sharePreparationFailed:
                    retryable.append(metadata)
                default:
                    break
                }
            }
        }
        pendingShareMetadata.append(contentsOf: retryable)
    }

    /// True when acceptance metadata is still waiting for a successful apply.
    var hasPendingAcceptedShares: Bool { !pendingShareMetadata.isEmpty }

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
                // Prefer model cancel transition when status still pending/confirmed.
                if show.companionStatus == .pending || show.companionStatus == .confirmed {
                    try show.cancelCompanion()
                } else {
                    show.applyCompanionSession(session, isOwner: isOwner)
                }
                show.clearCompanionCloudLinkage()
            } catch CompanionSharingError.sessionNotFound {
                if show.companionStatus == .pending || show.companionStatus == .confirmed {
                    try show.cancelCompanion()
                }
                show.clearCompanionCloudLinkage()
            } catch {
                // Do not claim remote cancel succeeded offline / on network errors.
                lastErrorMessage = Self.userMessage(for: error)
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
            let session = try await service.fetchSession(sessionLocator: sessionLocator)
            let isOwnerRole = show.companionIsOwner ?? (session.show.showID == show.id.uuidString)
            // If owner observes canceled root but still has a share locator, finish revocation first.
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
                    lastErrorMessage = nil
                    return
                } catch {
                    if show.companionStatus == .pending || show.companionStatus == .confirmed {
                        try? show.cancelCompanion()
                    }
                    // Keep share locator for retry.
                    show.companionCloudRecordName = sessionLocator.recordName
                    show.companionCloudZoneName = sessionLocator.zoneName
                    show.companionCloudOwnerName = sessionLocator.ownerName
                    show.companionShareRecordName = shareLocator.recordName
                    show.companionShareZoneName = shareLocator.zoneName
                    show.companionShareOwnerName = shareLocator.ownerName
                    show.companionIsOwner = true
                    try modelContext.save()
                    lastErrorMessage = Self.userMessage(for: error)
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
            lastErrorMessage = nil
        } catch let error as CompanionSharingError where error == .sessionNotFound {
            // Linked session disappeared (owner revoked share / deleted root).
            // Treat as terminal local cancellation rather than keeping a stale confirmed state.
            if show.companionStatus == .pending || show.companionStatus == .confirmed {
                try? show.cancelCompanion()
            }
            show.clearCompanionCloudLinkage()
            try? modelContext.save()
            lastErrorMessage = nil
        } catch {
            // Keep last known local state on network / permission failures.
            // Do not rollback the shared main context — that would discard unrelated edits.
            lastErrorMessage = Self.userMessage(for: error)
        }
    }

    func refreshAllLinkedShows(in modelContext: ModelContext) async {
        let descriptor = FetchDescriptor<Show>()
        guard let shows = try? modelContext.fetch(descriptor) else { return }
        for show in shows where show.companionCloudRecordName != nil {
            await refreshCompanion(for: show, in: modelContext)
        }
    }

    /// Reconcile local state after system UICloudSharingController events.
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

        // One-companion model: only treat "no accepted non-owner" as removal when we were
        // already confirmed. A normal pending invite save has zero accepted participants.
        let acceptedParticipants = share.participants.filter {
            $0.role != .owner && $0.acceptanceStatus == .accepted
        }
        let pendingParticipants = share.participants.filter {
            $0.role != .owner && $0.acceptanceStatus == .pending
        }

        if acceptedParticipants.isEmpty,
           pendingParticipants.isEmpty,
           show.companionStatus == .confirmed {
            // Confirmed participant removed via system UI — mirror as canceled.
            if show.companionSessionLocator != nil {
                try? await cancelCompanion(for: show, in: modelContext)
                return
            }
        } else if acceptedParticipants.count > 1 {
            // Domain assumes a single companion; surface an error for now.
            lastErrorMessage = "同行邀请目前只支持一位同伴"
            try? modelContext.save()
            return
        }

        try? modelContext.save()
        // Preserve membership error if refresh would clear it.
        let membershipError = lastErrorMessage
        await refreshCompanion(for: show, in: modelContext)
        if let membershipError, lastErrorMessage == nil {
            lastErrorMessage = membershipError
        }
    }

    func handleShareControllerDidStopSharing(
        for show: Show,
        in modelContext: ModelContext
    ) async {
        // System UI already revoked the share; mirror locally.
        if show.companionStatus == .pending || show.companionStatus == .confirmed {
            try? show.cancelCompanion()
        }
        show.clearCompanionCloudLinkage()
        try? modelContext.save()
    }

    func handleShareControllerFailure(_ error: Error) {
        lastErrorMessage = Self.userMessage(for: error)
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

    private func applyAcceptedSession(
        _ session: CompanionSessionSnapshot,
        in modelContext: ModelContext
    ) throws {
        let descriptor = FetchDescriptor<Show>()
        let shows = try modelContext.fetch(descriptor)

        if let existing = shows.first(where: {
            $0.companionCloudRecordName == session.sessionLocator.recordName
        }) {
            existing.applyCompanionSession(session, isOwner: false)
            try modelContext.save()
            return
        }

        // Prefer matching an upcoming local show with the same stable showID when available.
        if let byID = shows.first(where: { $0.id.uuidString == session.show.showID }) {
            byID.applyCompanionSession(session, isOwner: false)
            try modelContext.save()
            return
        }

        // Prefer a high-confidence unique match: same name + day + location when available.
        let calendar = Calendar.current
        let location = session.show.showLocation
        let parts = location?.split(separator: "·").map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        } ?? []
        let venue: String? = parts.first.map { String($0) }
        let city: String? = parts.count > 1 ? parts.last.map { String($0) } : nil

        let candidates = shows.filter { candidate in
            guard candidate.companionStatus == .none else { return false }
            guard candidate.name == session.show.showName else { return false }
            guard calendar.isDate(candidate.effectiveDate, inSameDayAs: session.show.showDate) else {
                return false
            }
            if let venue {
                guard let candidateVenue = candidate.venueName,
                      !candidateVenue.isEmpty,
                      candidateVenue == venue else {
                    return false
                }
            }
            if let city {
                guard let candidateCity = candidate.city,
                      !candidateCity.isEmpty,
                      candidateCity == city else {
                    return false
                }
            }
            // Require start-time agreement within 1 minute when both sides have times.
            let delta = abs(candidate.startTime.timeIntervalSince(session.show.showStartTime))
            if delta > 60 {
                return false
            }
            return true
        }

        if candidates.count == 1, let match = candidates.first {
            match.applyCompanionSession(session, isOwner: false)
            try modelContext.save()
            return
        }

        // Ambiguous or missing: create a dedicated show from the shared snapshot.
        let show = try Show(
            name: session.show.showName,
            date: session.show.showDate,
            startTime: session.show.showStartTime,
            city: city.flatMap { $0.isEmpty ? nil : $0 },
            venueName: venue.flatMap { $0.isEmpty ? nil : $0 }
        )
        show.applyCompanionSession(session, isOwner: false)
        modelContext.insert(show)
        try modelContext.save()
    }

    static func userMessage(for error: Error) -> String {
        if let sharing = error as? CompanionSharingError {
            switch sharing {
            case .iCloudAccountUnavailable:
                return "需要登录 iCloud 才能邀请同行"
            case .networkFailure:
                return "网络不可用，请稍后重试"
            case .sharePreparationFailed:
                return "邀请创建失败，请稍后重试"
            case .acceptFailed:
                return "接受邀请失败，请确认链接有效"
            case .sessionNotFound:
                return "找不到这场同行邀请"
            case .invalidPayload:
                return "邀请内容无效"
            case .permissionDenied:
                return "没有权限更新同行状态"
            case .conflict:
                return "同行状态已变更，请刷新后重试"
            case .statusSyncPending:
                return "已接受邀请，但状态同步失败，请稍后刷新"
            }
        }
        if error is ShowCompanionMutationError {
            return "同行状态无法更新"
        }
        return "同行操作失败，请稍后重试"
    }
}

// MARK: - Cloud linkage snapshot helpers

extension Show {
    struct CompanionCloudLinkageSnapshot: Equatable {
        var record: String?
        var zone: String?
        var owner: String?
        var share: String?
        var shareZone: String?
        var shareOwner: String?
        var isOwner: Bool?
    }

    func companionCloudLinkageSnapshot() -> CompanionCloudLinkageSnapshot {
        CompanionCloudLinkageSnapshot(
            record: companionCloudRecordName,
            zone: companionCloudZoneName,
            owner: companionCloudOwnerName,
            share: companionShareRecordName,
            shareZone: companionShareZoneName,
            shareOwner: companionShareOwnerName,
            isOwner: companionIsOwner
        )
    }

    func restoreCompanionCloudLinkage(_ snapshot: CompanionCloudLinkageSnapshot) {
        companionCloudRecordName = snapshot.record
        companionCloudZoneName = snapshot.zone
        companionCloudOwnerName = snapshot.owner
        companionShareRecordName = snapshot.share
        companionShareZoneName = snapshot.shareZone
        companionShareOwnerName = snapshot.shareOwner
        companionIsOwner = snapshot.isOwner
    }
}

// MARK: - App / scene delegate bridge for CloudKit share acceptance

final class BeforeShowAppDelegate: NSObject, UIApplicationDelegate {
    var companionCoordinator: CompanionSharingCoordinator?
    var modelContainer: ModelContainer?

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(
            name: "Default Configuration",
            sessionRole: connectingSceneSession.role
        )
        configuration.delegateClass = BeforeShowSceneDelegate.self
        return configuration
    }

    // Fallback for non-scene paths / older system delivery.
    func application(
        _ application: UIApplication,
        userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata
    ) {
        deliverAcceptedShare(cloudKitShareMetadata)
    }

    /// Metadata that arrived before coordinator/container wiring (cold launch).
    private var earlyShareMetadata: [CKShare.Metadata] = []

    func deliverAcceptedShare(_ metadata: CKShare.Metadata) {
        guard let coordinator = companionCoordinator else {
            // Dependencies not ready — queue on the app delegate itself.
            earlyShareMetadata.append(metadata)
            return
        }
        // Always enter the coordinator inbox so retries are centralized.
        Task { @MainActor in
            coordinator.enqueueAcceptedShare(metadata)
            if let container = modelContainer {
                let context = ModelContext(container)
                await coordinator.flushPendingAcceptedShares(in: context)
            }
        }
    }

    /// Called when RootView/task wires dependencies so cold-launch metadata is drained.
    func noteDependenciesReady() {
        let queued = earlyShareMetadata
        earlyShareMetadata.removeAll()
        guard let coordinator = companionCoordinator else { return }
        Task { @MainActor in
            for metadata in queued {
                coordinator.enqueueAcceptedShare(metadata)
            }
            if let container = modelContainer {
                let context = ModelContext(container)
                await coordinator.flushPendingAcceptedShares(in: context)
            }
        }
    }
}

final class BeforeShowSceneDelegate: NSObject, UIWindowSceneDelegate {
    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        // UIScene.ConnectionOptions exposes a single optional metadata value on this SDK.
        if let metadata = connectionOptions.cloudKitShareMetadata {
            deliver(metadata)
        }
    }

    func windowScene(
        _ windowScene: UIWindowScene,
        userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata
    ) {
        deliver(cloudKitShareMetadata)
    }

    private func deliver(_ metadata: CKShare.Metadata) {
        guard let appDelegate = UIApplication.shared.delegate as? BeforeShowAppDelegate else {
            return
        }
        appDelegate.deliverAcceptedShare(metadata)
    }
}
