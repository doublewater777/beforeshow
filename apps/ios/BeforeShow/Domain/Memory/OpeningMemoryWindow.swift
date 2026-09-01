import Foundation

/// 现场中从开场时刻起的第一个小时。一场一次，用这场的开场时刻，不用每日场次钟点。
enum OpeningMemoryWindow {
    static let duration: TimeInterval = 60 * 60

    static func isActive(now: Date, showStart: Date, isLive: Bool) -> Bool {
        guard isLive else { return false }
        return now >= showStart && now < showStart.addingTimeInterval(duration)
    }

    /// 只在开场前预排；开场后才添加或已确认结束都不补发。
    static func notificationFireDate(now: Date, showStart: Date, hasConfirmedEnd: Bool) -> Date? {
        guard !hasConfirmedEnd else { return nil }
        guard now < showStart else { return nil }
        return showStart
    }
}
