import Foundation
import SwiftData

struct CompanionAcceptedImportResult: Equatable {
    let showID: UUID
    let inserted: Bool
    let becameCurrent: Bool
    let wasHistorical: Bool
}

@MainActor
enum CompanionAcceptedSessionImporter {
    @discardableResult
    static func apply(
        _ session: CompanionSessionSnapshot,
        in modelContext: ModelContext,
        now: Date = Date()
    ) throws -> CompanionAcceptedImportResult {
        let descriptor = FetchDescriptor<Show>()
        var shows = try modelContext.fetch(descriptor)

        // Freeze unresolved legacy origins before an accepted share can mark a local show
        // as participant-side and make its original provenance ambiguous.
        ShowCreationOriginMigration.resolveUnresolvedOrigins(in: shows)

        if let existing = shows.first(where: {
            $0.companionCloudRecordName == session.sessionLocator.recordName
        }) {
            CompanionAcceptedShowMapping.mergeMissingData(from: session.show, into: existing)
            existing.applyCompanionSession(session, isOwner: false)
            let becameCurrent = selectAsCurrentIfNeeded(existing, among: shows, in: modelContext, now: now)
            try modelContext.save()
            return result(for: existing, inserted: false, becameCurrent: becameCurrent, now: now)
        }

        if let sourceID = UUID(uuidString: session.show.showID),
           let byID = shows.first(where: { $0.id == sourceID }) {
            CompanionAcceptedShowMapping.mergeMissingData(from: session.show, into: byID)
            byID.applyCompanionSession(session, isOwner: false)
            let becameCurrent = selectAsCurrentIfNeeded(byID, among: shows, in: modelContext, now: now)
            try modelContext.save()
            return result(for: byID, inserted: false, becameCurrent: becameCurrent, now: now)
        }

        let candidate = try CompanionAcceptedShowMapping.makeShow(from: session.show)
        let duplicateCandidates = shows.filter { existing in
            // One local Show owns at most one companion group. Never overwrite linkage
            // from an unrelated session just because the show metadata looks similar.
            guard existing.companionCloudRecordName == nil else { return false }
            return ShowDuplicateMatcher.isDuplicate(candidate, existing)
        }

        if duplicateCandidates.count == 1, let match = duplicateCandidates.first {
            CompanionAcceptedShowMapping.mergeMissingData(from: session.show, into: match)
            match.applyCompanionSession(session, isOwner: false)
            let becameCurrent = selectAsCurrentIfNeeded(match, among: shows, in: modelContext, now: now)
            try modelContext.save()
            return result(for: match, inserted: false, becameCurrent: becameCurrent, now: now)
        }

        // Ambiguous local matches are intentionally not overwritten. Persist the accepted
        // copy first, then RootView asks which existing Show (if any) should survive.
        candidate.applyCompanionSession(session, isOwner: false)
        modelContext.insert(candidate)
        shows.append(candidate)

        let state = CurrentShowTimeState(show: candidate, now: now)
        if isHistoricalPhase(state.kind) {
            // Post-show retention is still auto-selectable for ordinary Current Show logic,
            // but an invite accepted after the show has already ended belongs in footprints.
            candidate.markAddedAsHistorical()
        }

        let becameCurrent = selectAsCurrentIfNeeded(candidate, among: shows, in: modelContext, now: now)
        try modelContext.save()
        return result(for: candidate, inserted: true, becameCurrent: becameCurrent, now: now)
    }

    private static func selectAsCurrentIfNeeded(
        _ show: Show,
        among shows: [Show],
        in modelContext: ModelContext,
        now: Date
    ) -> Bool {
        // Production always has CurrentShowSelection. Lightweight recovery/test containers
        // sometimes model only Show; a selection failure must not roll back the accepted
        // Show itself, so this side effect is deliberately best-effort.
        let store = CurrentShowSelectionStore(modelContext: modelContext)
        let selection: CurrentShowSelection?
        do {
            selection = try store.canonicalSelection()
        } catch {
            return false
        }

        let current = CurrentShowSession().selectCurrentShow(
            from: shows,
            manualSelection: selection,
            now: now
        )
        guard current == nil,
              show.wasAddedAsHistorical != true,
              CurrentShowTimeState(show: show, now: now).isAutomaticallySelectable else {
            return false
        }
        do {
            _ = try store.select(showID: show.id)
            return true
        } catch {
            return false
        }
    }

    private static func result(
        for show: Show,
        inserted: Bool,
        becameCurrent: Bool,
        now: Date
    ) -> CompanionAcceptedImportResult {
        CompanionAcceptedImportResult(
            showID: show.id,
            inserted: inserted,
            becameCurrent: becameCurrent,
            wasHistorical: show.wasAddedAsHistorical == true
                || isHistoricalPhase(CurrentShowTimeState(show: show, now: now).kind)
        )
    }

    private static func isHistoricalPhase(_ kind: CurrentShowTimeKind) -> Bool {
        kind == .postShow || kind == .ended
    }
}
