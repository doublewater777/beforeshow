import Foundation
import PostHog

/// 产品分析唯一出口。关闭「产品数据分析」后 SDK 已 opt-out，这里不再判断。
enum ProductAnalytics {
    /// 首次完成后调用一次，把匿名事件和稳定安装 ID 关联，使留存 / 漏斗按人而非按设备聚合。
    static func identify() {
        guard let installID = AnalyticsInstallID.current() else { return }
        PostHogSDK.shared.identify(installID)
    }

    static func capture(_ event: AnalyticsEvent) {
        PostHogSDK.shared.capture(event.name, properties: event.properties)
    }

    /// 把公共上下文同步为 person properties，使 Person 页面可按维度筛选、留存可按人。
    /// 在 `register`（super properties）之外独立维护。
    static func setPersonProperties(_ context: AnalyticsContext) {
        for key in AnalyticsContext.keys where context.properties[key] == nil {
            PostHogSDK.shared.unregister(key)
        }
        PostHogSDK.shared.setPersonProperties(userPropertiesToSet: context.properties)
    }

    /// 以 super properties 附在之后的每个事件上。
    static func register(_ context: AnalyticsContext) {
        for key in AnalyticsContext.keys where context.properties[key] == nil {
            PostHogSDK.shared.unregister(key)
        }
        PostHogSDK.shared.register(context.properties)
    }

    /// 把一次展示的实验分组同步为 super property。
    ///
    /// flag 未命中 / 未加载时**注销**该 key：否则先前注册过的分组会继续
    /// 附着在后续事件上，让 UI 已回到默认文案的事件仍带旧分组。
    static func registerExperiment(_ experiment: WinbackCopyExperiment) {
        let key = "$feature/\(experiment.superPropertyKey)"
        guard experiment.isFlagResolved else {
            PostHogSDK.shared.unregister(key)
            return
        }
        PostHogSDK.shared.register([key: experiment.superPropertyValue])
    }

    /// 营收事件：`proPurchaseCompleted` 带金额，使 PostHog 营收仪表盘与 LTV 可用。
    static func captureRevenue(_ amount: Decimal, currency: String) {
        PostHogSDK.shared.capture("$revenue", properties: [
            "$amount": amount,
            "$currency": currency
        ])
    }

    /// 屏幕浏览。`$screen` 是 PostHog 系统事件，不是产品事件，故不走 `capture(_:)`。
    /// 名字会作为 `$screen_name` 附着到后续每个事件上。
    static func screen(_ name: String) {
        PostHogSDK.shared.screen(name)
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
