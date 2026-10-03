import SwiftData

@MainActor
enum CompanionInvitationPreparation {
    static func run(
        service: any CompanionSharingService,
        show: Show,
        preferredParticipantName: String?,
        ownerDisplayName: String?,
        in modelContext: ModelContext
    ) async throws -> CompanionPreparedShare {
        let attempt = CompanionAnalyticsAttempt(.invitation, source: "create")
        do {
            let prepared = try await prepare(
                service: service, show: show,
                preferredParticipantName: preferredParticipantName,
                ownerDisplayName: ownerDisplayName,
                in: modelContext, attempt: attempt
            )
            attempt.linkSession(prepared.session.recordName)
            attempt.finish(.succeeded)
            return prepared
        } catch {
            attempt.linkSession(show.companionCloudRecordName)
            attempt.finish(.failed, error: error)
            throw error
        }
    }

    private static func prepare(
        service: any CompanionSharingService,
        show: Show,
        preferredParticipantName: String?,
        ownerDisplayName: String?,
        in modelContext: ModelContext,
        attempt: CompanionAnalyticsAttempt
    ) async throws -> CompanionPreparedShare {
        let snapshotBefore = show.companionStateSnapshot()
        let cloudBefore = show.companionCloudLinkageSnapshot()

        if show.companionStatus == .canceled, show.companionShareLocator != nil {
            throw CompanionSharingError.conflict
        }

        attempt.stage = "local_pending"
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
            attempt.stage = "cloud_prepare"
            let prepared = try await attempt.withCloudDiagnostics {
                try await service.prepareInvitation(
                    show: CompanionShowSnapshot(show: show),
                    ownerDisplayName: ownerDisplayName,
                    preferredParticipantName: preferredParticipantName
                )
            }
            attempt.linkSession(prepared.session.recordName)
            attempt.stage = "local_link"
            show.applyCompanionSession(
                prepared.session,
                isOwner: true,
                preferredName: preferredParticipantName
            )
            try modelContext.save()
            return prepared
        } catch {
            // Preserve the failed phase unless recovery itself cannot be persisted.
            let failure: Error
            do {
                failure = try CompanionInvitePreparationRecovery.resolve(
                    error, show: show, preferredName: preferredParticipantName,
                    previousState: snapshotBefore, previousLinkage: cloudBefore,
                    in: modelContext
                )
            } catch {
                attempt.stage = "local_recovery"
                throw error
            }
            throw failure
        }
    }
}
