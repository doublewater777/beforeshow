import Foundation
import SwiftData

@MainActor extension ListeningRoomCoordinator {
    func playbackEvidenceCoordinatorForUse() throws -> ListeningPlaybackEvidenceCoordinator {
        if let playbackEvidenceCoordinator {
            return playbackEvidenceCoordinator
        }
        let created = try evidenceCoordinatorFactory(context)
        playbackEvidenceCoordinator = created
        return created
    }

    func applyDeckEvidence(
        _ result: ListeningPlaybackEvidenceDrainResult,
        representDismissedAlert: Bool
    ) {
        if result.committedAny {
            refreshPlaybackEvidenceProjection()
        }
        if result.hasFailure {
            handlePlaybackEvidenceFailure(representDismissedAlert: representDismissedAlert)
        }
    }

    func applyPlaybackEvidenceDrainResult(
        _ result: ListeningPlaybackEvidenceDrainResult
    ) {
        if result.committedAny {
            refreshPlaybackEvidenceProjection()
        }
        if result.hasFailure {
            handlePlaybackEvidenceFailure()
        } else {
            handlePlaybackEvidenceRecovery()
        }
    }

    func dismissError() {
        errorText = nil
        evidenceFailure.noteGeneralDismissed()
    }

    var playbackEvidenceFailureMessage: String {
        BSLocalization.text("保存失败，请重试")
    }

    func handlePlaybackEvidenceFailure(
        representDismissedAlert: Bool = true
    ) {
        var generalError = errorText
        evidenceFailure.present(
            into: &generalError,
            message: playbackEvidenceFailureMessage,
            representDismissedAlert: representDismissedAlert
        )
        errorText = generalError
        schedulePlaybackEvidenceRetry()
    }

    func handlePlaybackEvidenceRecovery() {
        var generalError = errorText
        evidenceFailure.recover(
            generalError: &generalError,
            expectedMessage: playbackEvidenceFailureMessage
        )
        errorText = generalError
    }

    func retryPendingPlaybackEvidence() {
        guard let playbackEvidenceCoordinator else { return }
        do {
            applyPlaybackEvidenceDrainResult(
                try playbackEvidenceCoordinator.flushPending()
            )
        } catch {
            handlePlaybackEvidenceFailure()
        }
    }

    func schedulePlaybackEvidenceRetry() {
        guard evidenceRetryTask == nil else { return }
        evidenceRetryTask = Task { @MainActor [weak self] in
            defer { self?.evidenceRetryTask = nil }
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(1))
                } catch {
                    return
                }
                guard let self, let evidence = self.playbackEvidenceCoordinator else { return }
                do {
                    let result = try evidence.flushPending()
                    if result.committedAny {
                        self.refreshPlaybackEvidenceProjection()
                    }
                    if result.hasFailure {
                        continue
                    }
                    self.handlePlaybackEvidenceRecovery()
                    return
                } catch {
                    continue
                }
            }
        }
    }
}
