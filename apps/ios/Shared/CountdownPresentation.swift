import Foundation
import SwiftUI

// MARK: - Presentation
// 视图输入一次性算好;kind/phase 推导复用 Shared 的 CurrentShowTimeState + HomeShowPhase。

struct CountdownPresentation {
    enum Hero: Equatable {
        case far(days: Int)
        case near(start: Date)
        case live(start: Date)
        case ended
        /// 估算结束时间已过、用户尚未确认散场:不说「已落幕」,与首页「待确认」一致。
        case endUnconfirmed
        case inactive(title: String)
        case empty
    }

    let hero: Hero
    let identity: ShowIdentityCopy
    let startDate: Date?
    let endBoundary: Date?
    let calendar: Calendar
    let endedTitle: String
    /// 距开场的秒数(entry 时刻),给圆形进度环用
    let remainingSeconds: Int
    /// 有时刻表时的现场切片(主现场 / 下一场 / 第一场想看)。
    let festival: WidgetFestivalNow?

    /// 音乐节现场模式的状态;非 nil 时各尺寸换成现场版式。
    var festivalPhase: WidgetFestivalNow.Phase? { festival?.phase }

    var hasShow: Bool { hero != .empty }
    var showName: String { identity.title }

    init(entry: CountdownEntry) {
        guard let snapshot = entry.snapshot else {
            hero = .empty
            identity = ShowIdentityCopy(name: "")
            startDate = nil
            endBoundary = nil
            calendar = .current
            endedTitle = ""
            remainingSeconds = 0
            festival = nil
            return
        }

        festival = WidgetFestivalNow(snapshot: snapshot, now: entry.date)
        identity = ShowIdentityCopy(
            name: snapshot.name,
            venueName: snapshot.venueName,
            city: snapshot.city
        )

        let state = CurrentShowTimeState(timing: snapshot.timing, now: entry.date)
        calendar = snapshot.timing.eventCalendar(fallback: .current)
        endedTitle = state.kind == .dayEnded
            ? BSLocalization.text("今天结束了")
            : BSLocalization.text("已结束")
        startDate = state.effectiveStartTime
        endBoundary = state.endBoundary
        let remaining = state.effectiveStartTime
            .map { max(0, Int($0.timeIntervalSince(entry.date))) } ?? 0
        remainingSeconds = remaining

        switch HomeShowPhase(timeState: state, now: entry.date) {
        case .pre:
            // 与首页一致:是否进入「天」档仍按真实剩余时间 >24h 判断，
            // 但一旦展示 N 天，N 使用演出时区自然日差。
            // 因此 10/1 → 10/3 即使只剩约 40 小时仍显示 2 天；
            // 而 23:50 → 次日 00:10 仍会进入 near，不显示 1 天。
            if let days = ShowCountdownRule.dayCount(
                remainingSeconds: remaining,
                dayDistance: state.dayDistance
            ) {
                hero = .far(days: days)
            } else if let start = state.effectiveStartTime {
                hero = .near(start: start)
            } else {
                hero = .inactive(title: state.title)
            }
        case .live:
            if let start = state.effectiveStartTime {
                hero = .live(start: start)
            } else {
                hero = .inactive(title: state.title)
            }
        case .ended:
            // 无明确结束时间的演出,start+默认时长 只是估算边界:
            // 用户未确认 endedAt 前不算「已落幕」。dayEnded 是单日循环内部态,仍按已落幕处理。
            if CurrentShowTimeState.isUnconfirmedEstimatedEnd(
                kind: state.kind,
                hasConfirmedEnd: snapshot.timing.endedAt != nil
            ) {
                hero = .endUnconfirmed
            } else {
                hero = .ended
            }
        case .inactive:
            hero = .inactive(title: state.title)
        }
    }

    var dateLine: String {
        guard let startDate else { return "" }
        let components = calendar.dateComponents([.month, .day, .hour, .minute], from: startDate)
        return String(
            format: BSLocalization.text("%d月%d日 %02d:%02d"),
            components.month ?? 0, components.day ?? 0, components.hour ?? 0, components.minute ?? 0
        )
    }

    /// 背景氛围随阶段变色:红 = 现在，金 = 等开场，夜蓝 = 今日已结束。
    var bloomTone: WidgetPhaseBloom.Tone {
        if let phase = festivalPhase {
            switch phase {
            case .live: return .live
            case .between, .firstSet, .finished: return .gold
            case .dayEnded: return .night
            }
        }
        switch hero {
        case .live: return .live
        case .near: return .gold
        case .far, .ended, .endUnconfirmed, .inactive, .empty: return .neutral
        }
    }

    /// 「今天开场」仅用于当日开场;`<24h` 但跨日仍使用「即将开场」。
    var isStartToday: Bool {
        guard let startDate else { return false }
        return calendar.isDateInToday(startDate)
    }

    /// 顶部时期标签只在 Hero 是数字(far/near)时出现;
    /// Hero 已是状态文字(live/ended/inactive)时 kicker 消失,避免同状态说两遍。
    var showsPhaseTag: Bool {
        switch hero {
        case .far, .near:
            return true
        case .live, .ended, .endUnconfirmed, .inactive, .empty:
            return false
        }
    }

    var phaseTag: String {
        switch hero {
        case .far:
            return BSLocalization.text("距离开场")
        case .near:
            return isStartToday
                ? BSLocalization.text("今天开场")
                : BSLocalization.text("即将开场")
        case .live, .ended, .endUnconfirmed, .inactive, .empty:
            return ""
        }
    }
}
