import Foundation

/// 记忆碎片在创建时固化的现场位置。外显分组标题固定为这三词。
enum MemoryFragmentPhase: String, Codable, CaseIterable, Equatable, Sendable {
    case before
    case live
    case after

    var title: String {
        switch self {
        case .before: return "开场前"
        case .live: return "进行中"
        case .after: return "散场后"
        }
    }

    /// 时间流组序：散场后 → 进行中 → 开场前。
    static let timelineDisplayOrder: [MemoryFragmentPhase] = [.after, .live, .before]

    /// 用记录时刻对照现场时间边界解析阶段。取消 / 延期待定兜底为进行中。
    static func resolved(
        at createdAt: Date,
        timing: ShowTimingFields,
        calendar: Calendar = .current
    ) -> MemoryFragmentPhase {
        let state = CurrentShowTimeState(timing: timing, calendar: calendar, now: createdAt)
        switch HomeShowPhase(timeState: state, now: createdAt) {
        case .pre:
            return .before
        case .live:
            return .live
        case .ended:
            return .after
        case .inactive:
            return .live
        }
    }
}

enum MemoryFragmentRelativeTime {
    static func format(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        let diff = max(0, now.timeIntervalSince(date))
        if calendar.isDate(date, inSameDayAs: now) {
            if diff < 60 { return "刚刚" }
            if diff < 3_600 {
                return "\(max(1, Int(diff / 60))) 分钟前"
            }
            return "\(max(1, Int(diff / 3_600))) 小时前"
        }

        if let yesterday = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: now)),
           calendar.isDate(date, inSameDayAs: yesterday) {
            return "昨天 \(clockText(date, calendar: calendar))"
        }

        return exact(date, now: now, calendar: calendar)
    }

    static func exact(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        let time = clockText(date, calendar: calendar)
        let month = calendar.component(.month, from: date)
        let day = calendar.component(.day, from: date)
        if calendar.component(.year, from: date) == calendar.component(.year, from: now) {
            return "\(month)月\(day)日 \(time)"
        }
        let year = calendar.component(.year, from: date)
        return "\(year)年\(month)月\(day)日 \(time)"
    }

    private static func clockText(_ date: Date, calendar: Calendar) -> String {
        let hour = calendar.component(.hour, from: date)
        let minute = calendar.component(.minute, from: date)
        return String(format: "%02d:%02d", hour, minute)
    }
}
