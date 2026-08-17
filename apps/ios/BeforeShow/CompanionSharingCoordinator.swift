import CloudKit
import Foundation
import os
import Security
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

    /// Share metadata waiting for successful acceptance/apply.
    private var pendingShareMetadata: [CKShare.Metadata]
    private var isFlushingAcceptedShares = false
    private let userDefaults: UserDefaults
    private let usesKeychainCloudSyncMarker: Bool

    private static let acceptedShareInboxKey = "companion.accepted-share-inbox.v1"
    static let cloudSyncEnabledKey = "companion.cloud-sync-enabled.v1"
    private static let cloudSyncMarkerService = "com.doublewaterapps.beforeshow.companion"
    private static let cloudSyncMarkerAccount = "cloud-sync-enabled"

    init(
        service: any CompanionSharingService = CloudKitCompanionSharingService.live(),
        container: CKContainer = CKContainer(
            identifier: CloudKitCompanionSharingService.defaultContainerIdentifier
        ),
        userDefaults: UserDefaults = .standard,
        usesKeychainCloudSyncMarker: Bool = true
    ) {
        self.service = service
        self.container = container
        self.userDefaults = userDefaults
        self.usesKeychainCloudSyncMarker = usesKeychainCloudSyncMarker
        self.pendingShareMetadata = Self.loadPersistedAcceptedShares(from: userDefaults)
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
            show.restoreCompanionState(status: snapshotBefore.status, name: snapshotBefore.name)
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
            try applyAcceptedSession(session, in: modelContext)
            pendingAcceptMessage = BSLocalization.format("已与%@确认同行", session.ownerDisplayName ?? BSLocalization.text("朋友"))
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
        let key = Self.metadataKey(metadata)
        guard !pendingShareMetadata.contains(where: { Self.metadataKey($0) == key }) else {
            return
        }
        pendingShareMetadata.append(metadata)
        Self.persistAcceptedShares(pendingShareMetadata, to: userDefaults)
    }

    func reloadPersistedAcceptedShares() {
        for metadata in Self.loadPersistedAcceptedShares(from: userDefaults) {
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
                !processedKeys.contains(Self.metadataKey($0))
            }
            guard !batch.isEmpty else { break }

            for metadata in batch {
                let key = Self.metadataKey(metadata)
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
                        Self.metadataKey($0) == key
                    }
                    Self.persistAcceptedShares(pendingShareMetadata, to: userDefaults)
                }
            }
        }
        Self.persistAcceptedShares(pendingShareMetadata, to: userDefaults)
    }

    var hasPendingAcceptedShares: Bool { !pendingShareMetadata.isEmpty }

    private static func metadataKey(_ metadata: CKShare.Metadata) -> String {
        let root = metadata.hierarchicalRootRecordID ?? metadata.rootRecordID
        let share = metadata.share.recordID
        return "\(root.zoneID.ownerName)|\(root.zoneID.zoneName)|\(root.recordName)|\(share.recordName)"
    }

    private static func loadPersistedAcceptedShares(from userDefaults: UserDefaults) -> [CKShare.Metadata] {
        guard let entries = userDefaults.array(forKey: acceptedShareInboxKey) as? [Data] else {
            return []
        }
        return entries.compactMap { data in
            try? NSKeyedUnarchiver.unarchivedObject(ofClass: CKShare.Metadata.self, from: data)
        }
    }

    private static func persistAcceptedShares(
        _ metadata: [CKShare.Metadata],
        to userDefaults: UserDefaults
    ) {
        var entries: [Data] = []
        for item in metadata {
            guard let data = try? NSKeyedArchiver.archivedData(
                withRootObject: item,
                requiringSecureCoding: true
            ) else {
                // Keep the previous durable queue intact if an archive unexpectedly fails.
                // The in-memory item remains retryable and will be written on a later flush.
                return
            }
            entries.append(data)
        }
        userDefaults.set(entries, forKey: acceptedShareInboxKey)
    }

    /// Used when a cold-launch scene callback arrives before the coordinator is installed.
    static func persistAcceptedShare(
        _ metadata: CKShare.Metadata,
        userDefaults: UserDefaults = .standard
    ) {
        var current = loadPersistedAcceptedShares(from: userDefaults)
        let key = metadataKey(metadata)
        if !current.contains(where: { metadataKey($0) == key }) {
            current.append(metadata)
        }
        persistAcceptedShares(current, to: userDefaults)
        userDefaults.set(true, forKey: cloudSyncEnabledKey)
        persistKeychainCloudSyncMarker()
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
                // The only accepted participant disappeared. Close the root and revoke the
                // remaining share so the owner does not keep a phantom confirmed relationship.
                try await cancelCompanion(for: show, in: modelContext)
                lastErrorMessage = BSLocalization.text("同行者已退出，同行关系已取消")
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
                try? applyAcceptedSession(session, in: modelContext)
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
        userDefaults.bool(forKey: Self.cloudSyncEnabledKey)
            || (usesKeychainCloudSyncMarker && Self.hasKeychainCloudSyncMarker())
    }

    private func enableCloudSync() {
        userDefaults.set(true, forKey: Self.cloudSyncEnabledKey)
        if usesKeychainCloudSyncMarker {
            Self.persistKeychainCloudSyncMarker()
        }
    }

    private static func hasKeychainCloudSyncMarker() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: cloudSyncMarkerService,
            kSecAttrAccount as String: cloudSyncMarkerAccount,
            kSecReturnData as String: false,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        return SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
    }

    private static func persistKeychainCloudSyncMarker() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: cloudSyncMarkerService,
            kSecAttrAccount as String: cloudSyncMarkerAccount
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: Data([1]),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        let status = SecItemAdd((query.merging(attributes, uniquingKeysWith: { _, new in new })) as CFDictionary, nil)
        guard status == errSecDuplicateItem else { return }
        SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
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
            return .warning("同行成员状态暂时无法同步，请稍后重试")
        }
    }

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

        if let byID = shows.first(where: { $0.id.uuidString == session.show.showID }) {
            byID.applyCompanionSession(session, isOwner: false)
            try modelContext.save()
            return
        }

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
            let delta = abs(candidate.startTime.timeIntervalSince(session.show.showStartTime))
            if delta > 60 { return false }
            return true
        }

        if candidates.count == 1, let match = candidates.first {
            match.applyCompanionSession(session, isOwner: false)
            try modelContext.save()
            return
        }

        let show = try Show(
            name: session.show.showName,
            date: session.show.showDate,
            startTime: session.show.showStartTime,
            city: city.flatMap { $0.isEmpty ? nil : $0 },
            venueName: venue.flatMap { $0.isEmpty ? nil : $0 },
            // 仅因接受邀请而新建：不占用本人的每月免费额度。
            // 上面的合并分支不改来源，用户自己添加的现场额度不会被退还。
            creationOrigin: .companionImport
        )
        show.applyCompanionSession(session, isOwner: false)
        modelContext.insert(show)
        try modelContext.save()
    }

    static func userMessage(for error: Error) -> String {
        if let sharing = error as? CompanionSharingError {
            switch sharing {
            case .iCloudAccountUnavailable:
                return BSLocalization.text("需要登录 iCloud 才能邀请同行")
            case .networkFailure:
                return BSLocalization.text("网络不可用，请稍后重试")
            case .sharePreparationFailed:
                return BSLocalization.text("邀请创建失败，请稍后重试")
            case .acceptFailed:
                return BSLocalization.text("接受邀请失败，请确认链接有效")
            case .sessionNotFound:
                return BSLocalization.text("找不到这场同行邀请")
            case .invalidPayload:
                return BSLocalization.text("邀请内容无效")
            case .permissionDenied:
                return BSLocalization.text("没有权限更新同行状态")
            case .conflict:
                return BSLocalization.text("同行状态已变更，请刷新后重试")
            case .statusSyncPending:
                return BSLocalization.text("已接受邀请，但状态同步失败，请稍后刷新")
            }
        }
        if error is ShowCompanionMutationError {
            return BSLocalization.text("同行状态无法更新")
        }
        if let ck = error as? CKError {
            return message(forCloudKit: ck)
        }
        return BSLocalization.format("同行操作失败：%@", error.localizedDescription)
    }

    private static func message(forCloudKit error: CKError) -> String {
        switch error.code {
        case .notAuthenticated, .managedAccountRestricted:
            return BSLocalization.text("需要登录 iCloud 才能邀请同行")
        case .networkUnavailable, .networkFailure, .serviceUnavailable, .zoneBusy, .requestRateLimited:
            return BSLocalization.text("网络不可用，请稍后重试")
        case .permissionFailure:
            return BSLocalization.text("没有权限创建同行邀请，请确认 iCloud 云盘已打开")
        case .quotaExceeded:
            return BSLocalization.text("iCloud 空间不足，无法创建同行邀请")
        case .invalidArguments, .constraintViolation:
            return BSLocalization.text("邀请创建失败：CloudKit 拒绝了这次请求")
        case .serverRejectedRequest:
            return BSLocalization.text("邀请创建失败：CloudKit 容器未就绪，请在 Xcode 打开 iCloud 能力并确认 Development 环境可用")
        default:
            return BSLocalization.format("邀请创建失败：%@", error.localizedDescription)
        }
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

    func application(
        _ application: UIApplication,
        userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata
    ) {
        deliverAcceptedShare(cloudKitShareMetadata)
    }

    func deliverAcceptedShare(_ metadata: CKShare.Metadata) {
        guard let coordinator = companionCoordinator else {
            // Persist before dependencies are available; a process termination must not
            // discard the invitation callback.
            CompanionSharingCoordinator.persistAcceptedShare(metadata)
            return
        }
        Task { @MainActor in
            coordinator.enqueueAcceptedShare(metadata)
            if let container = modelContainer {
                let context = ModelContext(container)
                await coordinator.flushPendingAcceptedShares(in: context)
            }
        }
    }

    func noteDependenciesReady() {
        guard let coordinator = companionCoordinator else { return }
        coordinator.reloadPersistedAcceptedShares()
        Task { @MainActor in
            if let container = modelContainer {
                let context = ModelContext(container)
                await coordinator.flushPendingAcceptedShares(in: context)
            }
        }
    }

    func application(
        _ application: UIApplication,
        performActionFor shortcutItem: UIApplicationShortcutItem,
        completionHandler: @escaping (Bool) -> Void
    ) {
        if shortcutItem.type == "com.doublewaterapps.beforeshow.pro-discount" {
            Task { @MainActor in
                ProOfferDeepLinkRouter.shared.routeToPro(showWinbackOffer: true)
            }
            completionHandler(true)
        } else {
            completionHandler(false)
        }
    }
}

final class BeforeShowSceneDelegate: NSObject, UIWindowSceneDelegate {
    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        if let metadata = connectionOptions.cloudKitShareMetadata {
            deliver(metadata)
        }
        if let shortcutItem = connectionOptions.shortcutItem,
           shortcutItem.type == "com.doublewaterapps.beforeshow.pro-discount" {
            Task { @MainActor in
                ProOfferDeepLinkRouter.shared.routeToPro(showWinbackOffer: true)
            }
        }
    }

   func windowScene(
       _ windowScene: UIWindowScene,
       userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata
   ) {
       deliver(cloudKitShareMetadata)
   }

    func windowScene(
        _ windowScene: UIWindowScene,
        performActionFor shortcutItem: UIApplicationShortcutItem,
        completionHandler: @escaping (Bool) -> Void
    ) {
        if shortcutItem.type == "com.doublewaterapps.beforeshow.pro-discount" {
            Task { @MainActor in
                ProOfferDeepLinkRouter.shared.routeToPro(showWinbackOffer: true)
            }
            completionHandler(true)
        } else {
            completionHandler(false)
        }
    }
    private func deliver(_ metadata: CKShare.Metadata) {
        guard let appDelegate = UIApplication.shared.delegate as? BeforeShowAppDelegate else {
            return
        }
        appDelegate.deliverAcceptedShare(metadata)
    }
}
