import Foundation

/// 现场中从开场时刻起的第一个小时。一场一次，用这场的开场时刻，不用每日场次钟点。
enum OpeningMemoryWindow {
    static let duration: TimeInterval = 60 * 60
    static let backfillDelay: TimeInterval = 10 * 60

    static func isActive(now: Date, showStart: Date, isLive: Bool) -> Bool {
        guard isLive else { return false }
        return now >= showStart && now < showStart.addingTimeInterval(duration)
    }

    /// 预排用开场时刻；窗内才添加则延迟 10 分钟；窗外或已确认结束不排。
    static func notificationFireDate(now: Date, showStart: Date, hasConfirmedEnd: Bool) -> Date? {
        guard !hasConfirmedEnd else { return nil }
        if now < showStart {
            return showStart
        }
        if isActive(now: now, showStart: showStart, isLive: true) {
            return now.addingTimeInterval(backfillDelay)
        }
        return nil
    }
}
