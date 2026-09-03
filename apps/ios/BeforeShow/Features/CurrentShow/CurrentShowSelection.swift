import Foundation
import SwiftData

@Model
final class CurrentShowSelection {
    var id: UUID
    var selectedShowID: UUID?
    /// Kept optional for lightweight repair of existing development stores.
    /// New writes always represent an explicit, durable user-owned selection.
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

    func clearSelection() {
        selectedShowID = nil
        isManual = true
        updatedAt = Date()
    }
}

/// Chooses an initial current show only when no durable selection exists.
/// Runtime time progression never calls this policy to replace an existing choice.
struct InitialCurrentShowPolicy {
    let calendar: Calendar

    init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    func candidate(from shows: [Show], now: Date = Date()) -> Show? {
        let eligible = shows.filter { show in
            guard show.wasAddedAsHistorical != true,
                  show.changeStatus != .canceled else {
                return false
            }
            if show.changeStatus == .postponed, show.postponedDate == nil {
                return false
            }
            return true
        }

        let projected = eligible.map { show in
            (
                show: show,
                state: CurrentShowTimeState(show: show, calendar: calendar, now: now)
            )
        }

        let live = projected
            .filter { entry in
                guard entry.state.kind == .today,
                      let start = entry.state.effectiveStartTime,
                      let end = entry.state.endBoundary else {
                    return false
                }
                return now >= start && now < end
            }
            .sorted { lhs, rhs in
                let lhsStart = lhs.state.effectiveStartTime ?? .distantPast
                let rhsStart = rhs.state.effectiveStartTime ?? .distantPast
                if lhsStart != rhsStart { return lhsStart > rhsStart }
                return lhs.show.id.uuidString < rhs.show.id.uuidString
            }
        if let show = live.first?.show {
            return show
        }

        let future = projected
            .filter { entry in
                guard let start = entry.state.effectiveStartTime else { return false }
                return start > now
            }
            .sorted { lhs, rhs in
                let lhsStart = lhs.state.effectiveStartTime ?? .distantFuture
                let rhsStart = rhs.state.effectiveStartTime ?? .distantFuture
                if lhsStart != rhsStart { return lhsStart < rhsStart }
                return lhs.show.id.uuidString < rhs.show.id.uuidString
            }
        if let show = future.first?.show {
            return show
        }

        return projected
            .filter { $0.show.endedAt == nil }
            .sorted { lhs, rhs in
                let lhsStart = lhs.state.effectiveStartTime ?? lhs.state.effectiveDate
                let rhsStart = rhs.state.effectiveStartTime ?? rhs.state.effectiveDate
                if lhsStart != rhsStart { return lhsStart > rhsStart }
                return lhs.show.id.uuidString < rhs.show.id.uuidString
            }
            .first?
            .show
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

    /// Establishes a Current Show only when the canonical selection has no valid
    /// target. Existing valid choices are never replaced because time has passed.
    @discardableResult
    func bootstrapIfNeeded(
        shows: [Show],
        now: Date = Date(),
        policy: InitialCurrentShowPolicy = InitialCurrentShowPolicy()
    ) throws -> CurrentShowSelection? {
        let selection = try normalizeDuplicates()
        if let selectedShowID = selection?.selectedShowID,
           shows.contains(where: { $0.id == selectedShowID }) {
            return selection
        }

        guard let candidate = policy.candidate(from: shows, now: now) else {
            selection?.clearSelection()
            return selection
        }
        return try select(showID: candidate.id)
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
