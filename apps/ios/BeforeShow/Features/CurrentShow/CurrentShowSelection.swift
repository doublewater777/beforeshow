import Foundation
import SwiftData

@Model
final class CurrentShowSelection {
    var id: UUID
    var selectedShowID: UUID?
    /// Kept optional for lightweight repair of existing development stores.
    /// nil is treated as a legacy manual choice; new automatic writes store false.
    var isManual: Bool?
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        selectedShowID: UUID? = nil,
        isManual: Bool = true,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.selectedShowID = selectedShowID
        self.isManual = isManual
        self.updatedAt = updatedAt
    }

    func select(showID: UUID) {
        selectedShowID = showID
        isManual = true
        updatedAt = Date()
    }

    /// Automatic ownership follows lifecycle changes. Explicit user choices use select(showID:).
    func selectAutomatically(showID: UUID?) {
        guard selectedShowID != showID || isManual != false else { return }
        selectedShowID = showID
        isManual = false
        updatedAt = Date()
    }

    func clearSelection() {
        selectedShowID = nil
        isManual = true
        updatedAt = Date()
    }
}

/// Automatic Current Show: never supersedes a manual choice. Retains an ongoing
/// or just-finished selected show, otherwise prioritizes a live show and then the
/// nearest upcoming one. Historical imports do not participate.
struct InitialCurrentShowPolicy {
    let calendar: Calendar

    init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    func candidate(
        from shows: [Show],
        retaining selectedShowID: UUID? = nil,
        now: Date = Date()
    ) -> Show? {
        let projected = shows.compactMap { show -> (show: Show, state: CurrentShowTimeState)? in
            guard show.wasAddedAsHistorical != true,
                  show.changeStatus != .canceled,
                  !(show.changeStatus == .postponed && show.postponedDate == nil) else {
                return nil
            }
            return (
                show: show,
                state: CurrentShowTimeState(show: show, calendar: calendar, now: now)
            )
        }

        let retained = projected.first { $0.show.id == selectedShowID }
        func isLive(_ entry: (show: Show, state: CurrentShowTimeState)) -> Bool {
            guard entry.show.endedAt == nil,
                  entry.state.kind == .today,
                  let start = entry.state.effectiveStartTime,
                  let end = entry.state.endBoundary else { return false }
            return start <= now && now < end
        }

        // When two shows overlap, keep the one already on screen.
        if let retained, isLive(retained) { return retained.show }
        let live = projected.filter(isLive).sorted {
            let left = $0.state.effectiveStartTime ?? .distantPast
            let right = $1.state.effectiveStartTime ?? .distantPast
            if left != right { return left > right }
            return $0.show.id.uuidString < $1.show.id.uuidString
        }
        if let active = live.first { return active.show }

        // The festival stays current between days, and the post-show experience
        // stays for up to three days unless another show is actually live.
        if let retained,
           retained.state.kind == .dayEnded || retained.state.kind == .postShow {
            return retained.show
        }

        let future = projected.filter {
            guard let start = $0.state.effectiveStartTime else { return false }
            return start > now && $0.state.kind != .ended
        }.sorted {
            let left = $0.state.effectiveStartTime ?? .distantFuture
            let right = $1.state.effectiveStartTime ?? .distantFuture
            if left != right { return left < right }
            return $0.show.id.uuidString < $1.show.id.uuidString
        }
        if let upcoming = future.first { return upcoming.show }

        // No future show: preserve an eligible after-show or festival break.
        return projected.filter {
            $0.state.kind == .postShow || $0.state.kind == .dayEnded
        }.sorted {
            let left = $0.state.effectiveEndTime ?? $0.state.effectiveDate
            let right = $1.state.effectiveEndTime ?? $1.state.effectiveDate
            if left != right { return left > right }
            return $0.show.id.uuidString < $1.show.id.uuidString
        }.first?.show
    }
}

/// The only mutation seam for the singleton-like `CurrentShowSelection` record.
/// The model itself cannot express singleton uniqueness, so every write first
/// normalizes malformed duplicate rows deterministically.
@MainActor
struct CurrentShowSelectionStore {
    let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    static func canonical(in selections: [CurrentShowSelection]) -> CurrentShowSelection? {
        selections.sorted(by: canonicalOrder).first
    }

    func canonicalSelection() throws -> CurrentShowSelection? {
        try normalizeDuplicates()
    }

    @discardableResult
    func normalizeDuplicates() throws -> CurrentShowSelection? {
        let selections = try modelContext.fetch(FetchDescriptor<CurrentShowSelection>())
            .sorted(by: Self.canonicalOrder)
        guard let canonical = selections.first else { return nil }
        for duplicate in selections.dropFirst() {
            modelContext.delete(duplicate)
        }
        return canonical
    }

    @discardableResult
    func select(showID: UUID) throws -> CurrentShowSelection {
        let selection: CurrentShowSelection
        if let existing = try normalizeDuplicates() {
            selection = existing
        } else {
            selection = CurrentShowSelection()
            modelContext.insert(selection)
        }
        selection.select(showID: showID)
        return selection
    }

    @discardableResult
    func clear() throws -> CurrentShowSelection? {
        guard let selection = try normalizeDuplicates() else { return nil }
        selection.clearSelection()
        return selection
    }

    /// Reconcile automatic ownership while preserving any valid manual selection.
    @discardableResult
    func bootstrapIfNeeded(
        shows: [Show],
        now: Date = Date(),
        policy: InitialCurrentShowPolicy = InitialCurrentShowPolicy()
    ) throws -> CurrentShowSelection? {
        let selection = try normalizeDuplicates()
        // Old records without an explicit mode are treated as manual for migration safety.
        if selection?.isManual != false,
           let selectedShowID = selection?.selectedShowID,
           shows.contains(where: { $0.id == selectedShowID }) {
            return selection
        }

        let retainedID = selection?.isManual == false ? selection?.selectedShowID : nil
        let candidate = policy.candidate(
            from: shows,
            retaining: retainedID,
            now: now
        )
        if selection == nil && candidate == nil { return nil }
        let record: CurrentShowSelection
        if let selection {
            record = selection
        } else {
            record = CurrentShowSelection()
            modelContext.insert(record)
        }
        record.selectAutomatically(showID: candidate?.id)
        return record
    }

    private static func canonicalOrder(
        _ lhs: CurrentShowSelection,
        _ rhs: CurrentShowSelection
    ) -> Bool {
        if lhs.updatedAt != rhs.updatedAt {
            return lhs.updatedAt > rhs.updatedAt
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}
