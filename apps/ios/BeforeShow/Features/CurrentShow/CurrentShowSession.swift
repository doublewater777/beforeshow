import Foundation

/// Read model for one 现场 under 当前现场 policy: durable selection result and phase.
struct CurrentShowSnapshot {
    let show: Show
    let phase: CurrentShowTimeState
}

/// Product-level read seam for the user-owned Current Show.
///
/// The selected show remains current until an explicit user choice changes it or
/// the selected record no longer exists. Time progression affects only `phase`.
struct CurrentShowSession {
    let postShowRetentionDays: Int
    let calendar: Calendar

    init(postShowRetentionDays: Int = 3, calendar: Calendar = .current) {
        self.postShowRetentionDays = postShowRetentionDays
        self.calendar = calendar
    }

    // MARK: - Selection

    func selectCurrentShow(
        from shows: [Show],
        manualSelection: CurrentShowSelection? = nil,
        now _: Date = Date()
    ) -> Show? {
        guard let selectedShowID = manualSelection?.selectedShowID else { return nil }
        return shows.first(where: { $0.id == selectedShowID })
    }

    func isCurrent(
        _ show: Show,
        among shows: [Show],
        manualSelection: CurrentShowSelection? = nil,
        now: Date = Date()
    ) -> Bool {
        selectCurrentShow(from: shows, manualSelection: manualSelection, now: now)?.id == show.id
    }

    /// Any persisted show can be chosen by the user, regardless of lifecycle state.
    func isManuallySelectable(_ show: Show, now _: Date = Date()) -> Bool {
        _ = show
        return true
    }

    // MARK: - Phase

    func phase(for show: Show, now: Date = Date()) -> CurrentShowTimeState {
        CurrentShowTimeState(
            show: show,
            calendar: calendar,
            now: now,
            retentionDays: postShowRetentionDays
        )
    }

    func snapshot(
        for show: Show,
        now: Date = Date()
    ) -> CurrentShowSnapshot {
        CurrentShowSnapshot(
            show: show,
            phase: phase(for: show, now: now)
        )
    }

    func resolve(
        shows: [Show],
        manualSelection: CurrentShowSelection? = nil,
        now: Date = Date()
    ) -> CurrentShowSnapshot? {
        guard let show = selectCurrentShow(
            from: shows,
            manualSelection: manualSelection,
            now: now
        ) else {
            return nil
        }
        return snapshot(for: show, now: now)
    }
}
