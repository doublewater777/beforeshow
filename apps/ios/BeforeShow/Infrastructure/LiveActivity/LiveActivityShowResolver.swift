import Foundation

// MARK: - Live Activity Show Resolver (ADR 0037)

/// Live Activity 只展示当前现场：当前现场正在进行或还没开场时才有活动，
/// 不会替其他现场开活动（ADR 0037）。
struct LiveActivityShowResolver {
    let calendar: Calendar

    init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    func resolve(
        shows: [Show],
        currentShow: Show?,
        now: Date = Date()
    ) -> Show? {
        guard let currentShow,
              shows.contains(where: { $0.id == currentShow.id }),
              currentShow.wasAddedAsHistorical != true,
              currentShow.changeStatus != .canceled,
              currentShow.endedAt == nil,
              !(currentShow.changeStatus == .postponed && currentShow.postponedDate == nil) else {
            return nil
        }
        if isActuallyLive(currentShow, now: now) {
            return currentShow
        }
        guard let start = startTime(for: currentShow, now: now), start > now else { return nil }
        return currentShow
    }

    private func startTime(for show: Show, now: Date) -> Date? {
        CurrentShowTimeState(show: show, calendar: calendar, now: now).effectiveStartTime
    }

    private func isActuallyLive(_ show: Show, now: Date) -> Bool {
        let state = CurrentShowTimeState(show: show, calendar: calendar, now: now)
        guard state.kind == .today,
              let start = state.effectiveStartTime,
              let end = state.endBoundary else {
            return false
        }
        return now >= start && now < end
    }
}
