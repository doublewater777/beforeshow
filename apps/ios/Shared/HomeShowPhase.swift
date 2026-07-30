import Foundation

// MARK: - Home Show Phase
// 首页三态（设计稿 pre / live / ended）从 CurrentShowTimeState 推导：
// - pre: 开场前（含当天未到开场时间）
// - live: 开场中（越过开场时间，未到谢幕边界）
// - ended: 谢幕后（停留期与已结束）
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
        case .postShow, .ended:
            self = .ended
        case .canceled, .postponed:
            self = .inactive
        }
    }

    /// Hero kicker 文案；inactive 由调用方回退到 timeState.title（已取消 / 时间待定）。
    func kickerText(city: String?) -> String {
        let trimmed = city?.trimmingCharacters(in: .whitespacesAndNewlines)
        let stop = trimmed.flatMap { $0.isEmpty ? nil : $0 }
        switch self {
        case .pre:
            return stop.map { "即将开场 · \($0)站" } ?? "即将开场"
        case .live:
            return "LIVE · 开场中"
        case .ended:
            return stop.map { "已落幕 · \($0)站" } ?? "已落幕"
        case .inactive:
            return ""
        }
    }
}
