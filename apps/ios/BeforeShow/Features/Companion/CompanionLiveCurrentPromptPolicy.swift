import Foundation

enum CompanionLiveCurrentPromptPolicy {
    static func shouldOffer(
        importResult: CompanionAcceptedImportResult,
        show: Show,
        selectedShowID: UUID?,
        now: Date = Date()
    ) -> Bool {
        guard !importResult.becameCurrent,
              !importResult.wasHistorical,
              let selectedShowID,
              selectedShowID != show.id else {
            return false
        }

        let state = CurrentShowTimeState(show: show, now: now)
        guard state.kind == .today,
              let start = state.effectiveStartTime,
              let end = state.endBoundary else {
            return false
        }
        return now >= start && now < end
    }
}
