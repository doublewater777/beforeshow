import Foundation

// MARK: - Home Show Phase
// 首页三态（设计稿 pre / live / ended）从 CurrentShowTimeState 推导：
// - pre: 开场前（含当天未到开场时间）
// - live: 开场中（越过开场时间，未到谢幕边界）
// - ended: 谢幕后（停留期、多日「今日已落幕」、已结束）
// - inactive: 已取消 / 待定，卡片回退为文本态
// app 首页与 widget 共用同一套 phase 推导与 kicker 文案。
enum HomeShowPhase: Equatable {
    case pre
    case live
    case ended
    case inactive

    init(timeState: CurrentShowTimeState, now: Date = Date()) {
        switch timeState.kind {
        case .before:
            self = .pre
        case .today:
            if let start = timeState.effectiveStartTime, now >= start {
                self = .live
            } else {
                self = .pre
            }
        case .dayEnded, .postShow, .ended:
            // dayEnded 视觉同 ended，文案由调用方用 timeState.title / kind 区分「今日已落幕」。
            self = .ended
        case .canceled, .postponed:
            self = .inactive
        }
    }

    /// Hero kicker 文案；inactive 由调用方回退到 timeState.title（已取消 / 时间待定）。
    /// 多日中间日落幕请传 `timeState`，优先显示「今日已落幕」。
    func kickerText(city: String?, timeState: CurrentShowTimeState? = nil) -> String {
        if timeState?.kind == .dayEnded {
            return BSLocalization.text("今日已落幕")
        }
        let trimmed = city?.trimmingCharacters(in: .whitespacesAndNewlines)
        let stop = trimmed.flatMap { $0.isEmpty ? nil : $0 }
        switch self {
        case .pre:
            return stop.map { BSLocalization.format("即将开场 · %@站", $0) }
                ?? BSLocalization.text("即将开场")
        case .live:
            return BSLocalization.text("LIVE · 开场中")
        case .ended:
            return stop.map { BSLocalization.format("已落幕 · %@站", $0) }
                ?? BSLocalization.text("已落幕")
        case .inactive:
            return ""
        }
    }
}
