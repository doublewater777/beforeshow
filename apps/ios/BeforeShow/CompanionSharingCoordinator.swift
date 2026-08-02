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
        let cloudBefore = (
            record: show.companionCloudRecordName,
            share: show.companionShareRecordName,
            isOwner: show.companionIsOwner
        )

        do {
            switch show.companionStatus {
            case .none, .canceled:
                try show.markCompanionInvitationSent(name: preferredParticipantName)
            case .pending:
                // Allow recreating a CloudKit share when re-sending from pending.
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
            show.companionCloudRecordName = cloudBefore.record
            show.companionShareRecordName = cloudBefore.share
            show.companionIsOwner = cloudBefore.isOwner
            try? modelContext.save()
            lastErrorMessage = Self.userMessage(for: error)
            throw error
        }
    }

    func shareSystemFieldsForResend(show: Show) async throws -> Data {
        guard let shareRecordName = show.companionShareRecordName else {
            throw CompanionSharingError.sessionNotFound
        }
        return try await service.loadShareSystemFields(shareRecordName: shareRecordName)
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
        } catch {
            lastErrorMessage = Self.userMessage(for: error)
        }
    }

    // MARK: Cancel / sync

    func cancelCompanion(for show: Show, in modelContext: ModelContext) async throws {
        if let recordName = show.companionCloudRecordName {
            do {
                let session = try await service.cancelSession(recordName: recordName)
                show.applyCompanionSession(session, isOwner: show.companionIsOwner ?? true)
            } catch CompanionSharingError.sessionNotFound {
                try show.cancelCompanion()
            } catch {
                // Still cancel locally so the user is not stuck; next sync may reconcile.
                try show.cancelCompanion()
                lastErrorMessage = Self.userMessage(for: error)
            }
        } else {
            try show.cancelCompanion()
        }
        try modelContext.save()
    }

    func refreshCompanion(for show: Show, in modelContext: ModelContext) async {
        guard let recordName = show.companionCloudRecordName else { return }
        do {
            let session = try await service.fetchSession(recordName: recordName)
            let isOwner = show.companionIsOwner ?? (session.show.showID == show.id.uuidString)
            show.applyCompanionSession(session, isOwner: isOwner)
            try modelContext.save()
            lastErrorMessage = nil
        } catch {
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

        if let existing = shows.first(where: { $0.companionCloudRecordName == session.recordName }) {
            existing.applyCompanionSession(session, isOwner: false)
            try modelContext.save()
            return
        }

        // Prefer matching an upcoming local show with the same name + day when possible.
        let calendar = Calendar.current
        if let match = shows.first(where: { candidate in
            candidate.name == session.show.showName
                && calendar.isDate(candidate.effectiveDate, inSameDayAs: session.show.showDate)
                && candidate.companionStatus == .none
        }) {
            match.applyCompanionSession(session, isOwner: false)
            try modelContext.save()
            return
        }

        let location = session.show.showLocation
        let parts = location?.split(separator: "·").map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        } ?? []
        let venue = parts.first
        let city = parts.count > 1 ? parts.last : nil

        let show = try Show(
            name: session.show.showName,
            date: session.show.showDate,
            startTime: session.show.showDate,
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
            }
        }
        if error is ShowCompanionMutationError {
            return "同行状态无法更新"
        }
        return "同行操作失败，请稍后重试"
    }
}

// MARK: - App delegate bridge for CloudKit share acceptance

final class BeforeShowAppDelegate: NSObject, UIApplicationDelegate {
    var companionCoordinator: CompanionSharingCoordinator?
    var modelContainer: ModelContainer?

    func application(
        _ application: UIApplication,
        userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata
    ) {
        guard let coordinator = companionCoordinator,
              let container = modelContainer else {
            return
        }
        let context = ModelContext(container)
        Task { @MainActor in
            await coordinator.handleAcceptedShare(
                metadata: cloudKitShareMetadata,
                participantDisplayName: nil,
                in: context
            )
        }
    }
}
