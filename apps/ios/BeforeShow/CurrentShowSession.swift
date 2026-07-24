import Foundation

/// Read model for one 现场 under 当前现场 policy: selection result and phase.
struct CurrentShowSnapshot {
    let show: Show
    let phase: CurrentShowTimeState
}

/// Deep module for 当前现场 assembly.
///
/// Callers get show + phase (and selection) through one interface instead of
/// re-wiring `CurrentShowSelector` + `CurrentShowTimeState` at each site.
///
/// Deletion test: without this session, home / detail / list re-scatter selection,
/// phase clocks, and tool summary with inconsistent calendar/retention. The kernels
/// remain deep; this is the product-level seam that joins them.
struct CurrentShowSession {
    let postShowRetentionDays: Int
    let calendar: Calendar
    private let selector: CurrentShowSelector

    init(postShowRetentionDays: Int = 3, calendar: Calendar = .current) {
        self.postShowRetentionDays = postShowRetentionDays
        self.calendar = calendar
        self.selector = CurrentShowSelector(
            postShowRetentionDays: postShowRetentionDays,
            calendar: calendar
        )
    }

    // MARK: - Selection

    func selectCurrentShow(
        from shows: [Show],
        manualSelection: CurrentShowSelection? = nil,
        now: Date = Date()
    ) -> Show? {
        selector.selectCurrentShow(from: shows, manualSelection: manualSelection, now: now)
    }

    func isCurrent(
        _ show: Show,
        among shows: [Show],
        manualSelection: CurrentShowSelection? = nil,
        now: Date = Date()
    ) -> Bool {
        selectCurrentShow(from: shows, manualSelection: manualSelection, now: now)?.id == show.id
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

    /// Phase for a known 现场 (detail, content home).
    func snapshot(
        for show: Show,
        now: Date = Date()
    ) -> CurrentShowSnapshot {
        CurrentShowSnapshot(
            show: show,
            phase: phase(for: show, now: now)
        )
    }

    /// Select 当前现场 then build its snapshot (home entry).
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
        return snapshot(
            for: show,
            now: now
        )
    }
}
