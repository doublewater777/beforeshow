import Foundation
import SwiftData

@Model
final class CurrentShowSelection {
    var id: UUID
    var selectedShowID: UUID?
    var updatedAt: Date

    init(id: UUID = UUID(), selectedShowID: UUID? = nil, updatedAt: Date = Date()) {
        self.id = id
        self.selectedShowID = selectedShowID
        self.updatedAt = updatedAt
    }

    func select(showID: UUID) {
        selectedShowID = showID
        updatedAt = Date()
    }

    func clearManualSelection() {
        selectedShowID = nil
        updatedAt = Date()
    }
}

struct CurrentShowSelector {
    let postShowRetentionDays: Int
    let calendar: Calendar

    init(postShowRetentionDays: Int = 3, calendar: Calendar = .current) {
        self.postShowRetentionDays = postShowRetentionDays
        self.calendar = calendar
    }

    func selectCurrentShow(
        from shows: [Show],
        manualSelection: CurrentShowSelection? = nil,
        now: Date = Date()
    ) -> Show? {
        // Manual selection wins only while the selected show is eligible for the
        // current focus. A show that has passed its estimated boundary remains
        // eligible until the user confirms its end.
        if let selectedShowID = manualSelection?.selectedShowID,
           let selectedShow = shows.first(where: { $0.id == selectedShowID }),
           isManuallySelectable(selectedShow, now: now) {
            return selectedShow
        }

        let automaticallySelectableShows = shows
            .map { show in
                (
                    show,
                    CurrentShowTimeState(
                        show: show,
                        calendar: calendar,
                        now: now,
                        retentionDays: postShowRetentionDays
                    )
                )
            }
            .filter { show, state in isAutomaticallySelectable(show, state: state) }
            .sorted { first, second in
                let firstRank = automaticSelectionRank(for: first.0, state: first.1, now: now)
                let secondRank = automaticSelectionRank(for: second.0, state: second.1, now: now)

                if firstRank != secondRank {
                    return firstRank < secondRank
                }

                let firstDistance = abs(first.1.dayDistance)
                let secondDistance = abs(second.1.dayDistance)

                if firstDistance == secondDistance {
                    return first.1.effectiveDate < second.1.effectiveDate
                }

                return firstDistance < secondDistance
            }
            .map { show, _ in show }

        return automaticallySelectableShows.first
    }

    func isAutomaticallySelectable(_ show: Show, now: Date = Date()) -> Bool {
        let state = timeState(for: show, now: now)
        return isAutomaticallySelectable(show, state: state)
    }

    func isManuallySelectable(_ show: Show, now: Date = Date()) -> Bool {
        let state = timeState(for: show, now: now)
        return isAutomaticallySelectable(show, state: state)
    }

    private func timeState(for show: Show, now: Date) -> CurrentShowTimeState {
        CurrentShowTimeState(
            show: show,
            calendar: calendar,
            now: now,
            retentionDays: postShowRetentionDays
        )
    }

    private func isAutomaticallySelectable(_ show: Show, state: CurrentShowTimeState) -> Bool {
        if state.kind == .ended {
            return show.endedAt == nil
        }
        return state.isAutomaticallySelectable
    }

    private func automaticSelectionRank(
        for show: Show,
        state: CurrentShowTimeState,
        now: Date
    ) -> Int {
        if isActuallyLive(state, now: now) {
            return 0
        }

        if state.kind == .dayEnded ||
            ((state.kind == .postShow || state.kind == .ended) && show.endedAt == nil) {
            return 1
        }

        switch state.kind {
        case .today, .before:
            return 2
        case .dayEnded:
            return 1
        case .postShow:
            return 3
        case .ended, .canceled, .postponed:
            return 4
        }
    }

    private func isActuallyLive(_ state: CurrentShowTimeState, now: Date) -> Bool {
        guard state.kind == .today,
              let start = state.effectiveStartTime,
              let boundary = state.endBoundary else {
            return false
        }
        return now >= start && now < boundary
    }
}
