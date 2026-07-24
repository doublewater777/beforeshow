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
        // Manual selection wins, but a canceled现场 must not stay current
        // (see ShowDetailView copy: 取消后"不会出现在当前现场"). Fall through to automatic.
        if let selectedShowID = manualSelection?.selectedShowID,
           let selectedShow = shows.first(where: { $0.id == selectedShowID }),
           selectedShow.changeStatus != .canceled {
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
            .filter { _, state in state.isAutomaticallySelectable }
            .sorted { first, second in
                let firstRank = automaticSelectionRank(for: first.1)
                let secondRank = automaticSelectionRank(for: second.1)

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
        CurrentShowTimeState(
            show: show,
            calendar: calendar,
            now: now,
            retentionDays: postShowRetentionDays
        )
        .isAutomaticallySelectable
    }

    private func automaticSelectionRank(for state: CurrentShowTimeState) -> Int {
        switch state.kind {
        case .today:
            return 0
        case .postShow:
            return 1
        case .before:
            return 2
        case .ended, .canceled, .postponed:
            return 3
        }
    }
}
