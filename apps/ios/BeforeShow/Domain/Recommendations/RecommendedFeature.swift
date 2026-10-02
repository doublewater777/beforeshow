import Foundation

/// 通知推荐节点与倒计时信息卡推荐主操作能带用户进入的功能（ADR 0037）。
/// 票根、动态封面和 Pro 不进入推荐。
enum RecommendedFeature: String, CaseIterable, Codable, Sendable {
    case widget
    case companion
    case listen
    case timetable
    case dispersal
    case memoryFragments
    case footprint
    case nextShow
    case addShow
}

/// 推荐位：每个通知推荐节点、每个主卡阶段各有固定的候选顺序。
enum FeatureRecommendationSlot: Equatable, Sendable {
    case addedFollowUp
    case fourteenDaysBefore
    case sevenDaysBefore
    case threeDaysBefore
    /// 主卡：开场前超过 7 天。
    case cardFarBefore
    /// 主卡：开场前 7 天内（当天之前）。
    case cardNearBefore
    /// 主卡：已确认散场、仍在停留期。
    case cardPostShow
    /// 主卡：已确认散场、停留期已过。
    case cardAfterRetention
    /// 通知：散场后第 3 天。
    case footprintArrival

    func chain(isFestival: Bool, hasFutureShow: Bool) -> [RecommendedFeature] {
        let next: RecommendedFeature = hasFutureShow ? .nextShow : .addShow
        switch self {
        case .addedFollowUp:
            return [.widget, .companion]
        case .fourteenDaysBefore:
            return [.listen, .companion]
        case .sevenDaysBefore:
            return [.companion, .listen]
        case .threeDaysBefore, .cardNearBefore:
            return isFestival ? [.timetable, .listen] : [.listen]
        case .cardFarBefore:
            return [.companion, .widget, .listen]
        case .cardPostShow:
            return [.dispersal, .memoryFragments]
        case .cardAfterRetention, .footprintArrival:
            return [.footprint, next]
        }
    }
}
