import Foundation

/// 通知推荐节点能带用户进入的功能（ADR 0037）。
/// 票根和 Pro 不进入推荐。
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

/// 推荐位：每个通知推荐节点各有固定的候选顺序。
enum FeatureRecommendationSlot: Equatable, Sendable {
    case sevenDaysBefore
    case threeDaysBefore
    /// 通知：散场后第 3 天。
    case footprintArrival

    func chain(isFestival: Bool, hasFutureShow: Bool) -> [RecommendedFeature] {
        let next: RecommendedFeature = hasFutureShow ? .nextShow : .addShow
        switch self {
        case .sevenDaysBefore:
            return [.companion, .listen]
        case .threeDaysBefore:
            return isFestival ? [.timetable, .listen] : [.listen]
        case .footprintArrival:
            return [.footprint, next]
        }
    }
}
