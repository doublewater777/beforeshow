import Foundation
import PostHog

/// 产品分析唯一出口。关闭「产品数据分析」后 SDK 已 opt-out，这里不再判断。
enum ProductAnalytics {
    static func capture(_ event: AnalyticsEvent) {
        PostHogSDK.shared.capture(event.name, properties: event.properties)
    }

    /// 以 super properties 附在之后的每个事件上。
    static func register(_ context: AnalyticsContext) {
        for key in AnalyticsContext.keys where context.properties[key] == nil {
            PostHogSDK.shared.unregister(key)
        }
        PostHogSDK.shared.register(context.properties)
    }
}

/// 用户与当前现场的公共属性。
struct AnalyticsContext {
    enum Phase: String {
        case before
        case showDay = "show_day"
        case live
        case after
        case ended
        case canceled
        case postponed
        case none
    }

    static let keys = [
        "is_pro", "has_widget", "show_count", "footprint_count",
        "current_show_id", "current_show_phase", "current_show_days_until", "current_show_is_festival"
    ]

    var isPro: Bool
    var hasWidget: Bool
    var showCount: Int
    var footprintCount: Int
    var currentShowID: UUID?
    var phase: Phase
    var daysUntil: Int?
    var isFestival: Bool?

    @MainActor
    init(shows: [Show], currentShowID: UUID?, isPro: Bool, hasWidget: Bool, now: Date = Date()) {
        self.isPro = isPro
        self.hasWidget = hasWidget
        showCount = shows.count
        footprintCount = shows.filter { show in
            show.changeStatus != .canceled
                && (show.wasAddedAsHistorical == true
                    || CurrentShowTimeState(show: show, calendar: show.timingCalendar(), now: now).kind == .ended)
        }.count

        guard let current = shows.first(where: { $0.id == currentShowID }) else {
            self.currentShowID = nil
            phase = .none
            return
        }
        self.currentShowID = current.id
        isFestival = ShowFlavor.inferred(from: current) == .festival
        let state = CurrentShowTimeState(show: current, calendar: current.timingCalendar(), now: now)
        phase = Self.phase(of: state, now: now)
        if phase == .before { daysUntil = state.dayDistance }
    }

    static func phase(of state: CurrentShowTimeState, now: Date) -> Phase {
        switch state.kind {
        case .before:
            return .before
        case .today:
            if let start = state.effectiveStartTime, now < start { return .showDay }
            if let end = state.endBoundary, now >= end { return .after }
            return .live
        case .dayEnded, .postShow:
            return .after
        case .ended:
            return .ended
        case .canceled:
            return .canceled
        case .postponed:
            return .postponed
        }
    }

    var properties: [String: Any] {
        var properties: [String: Any] = [
            "is_pro": isPro,
            "has_widget": hasWidget,
            "show_count": showCount,
            "footprint_count": footprintCount,
            "current_show_phase": phase.rawValue
        ]
        if let currentShowID { properties["current_show_id"] = currentShowID.uuidString }
        if let daysUntil { properties["current_show_days_until"] = daysUntil }
        if let isFestival { properties["current_show_is_festival"] = isFestival }
        return properties
    }
}
