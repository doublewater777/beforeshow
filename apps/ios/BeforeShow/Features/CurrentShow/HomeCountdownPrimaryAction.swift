import Foundation

// MARK: Primary action：单一主行动随生命周期切换
// 开场前 → 功能推荐；当天开场前 → 路线；live → 记一段记忆；
// 超过预计散场且未确认 → 确认已结束；确认散场后 → 功能推荐（ADR 0037）。

extension HomeCountdownLockup {
    enum PrimaryAction: Equatable {
        case end(live: Bool)
        case memoryFragments
        case memoryCreate
        case route
        case recommendation(RecommendedFeature)

        var title: String {
            switch self {
            case .end(live: true): return BSLocalization.text("结束现场")
            case .end(live: false): return BSLocalization.text("确认已结束")
            case .memoryFragments, .memoryCreate: return BSLocalization.text("记一段记忆")
            case .route: return BSLocalization.text("看路线")
            case .recommendation(let feature): return feature.cardTitle
            }
        }

        var accessibilityHint: String {
            switch self {
            case .end: return BSLocalization.text("打开结束现场确认")
            case .memoryFragments: return BSLocalization.text("打开记忆碎片")
            case .memoryCreate: return BSLocalization.text("打开新增记忆")
            case .route: return BSLocalization.text("打开路线")
            case .recommendation: return ""
            }
        }

        /// 现场中与收尾用现场色；开场前的路线和功能推荐用舞台金。
        var usesLiveTint: Bool {
            switch self {
            case .end, .memoryFragments, .memoryCreate: return true
            case .route, .recommendation: return false
            }
        }
    }

    nonisolated static func primaryAction(
        phase: HomeShowPhase,
        timeState: CurrentShowTimeState,
        hasConfirmedEnd: Bool,
        hasEndHandler: Bool,
        hasRouteHandler: Bool = false,
        recommendation: RecommendedFeature? = nil
    ) -> PrimaryAction? {
        if hasConfirmedEnd {
            switch timeState.kind {
            case .postShow, .ended: return recommendation.map(PrimaryAction.recommendation)
            default: return nil
            }
        }
        switch phase {
        case .pre:
            if timeState.kind == .today {
                return hasRouteHandler ? .route : nil
            }
            return recommendation.map(PrimaryAction.recommendation)
        case .live:
            return .memoryCreate
        case .ended:
            if timeState.kind == .postShow || timeState.kind == .ended {
                return hasEndHandler ? .end(live: false) : nil
            }
            return .memoryFragments
        case .inactive:
            return nil
        }
    }

    nonisolated static func endActionTitle(
        phase: HomeShowPhase,
        timeState: CurrentShowTimeState,
        now: Date,
        showStart: Date,
        hasConfirmedEnd: Bool,
        hasEndHandler: Bool
    ) -> String? {
        guard let action = primaryAction(
            phase: phase,
            timeState: timeState,
            hasConfirmedEnd: hasConfirmedEnd,
            hasEndHandler: hasEndHandler
        ) else { return nil }
        guard case let .end(live) = action else { return nil }
        return live ? BSLocalization.text("结束现场") : BSLocalization.text("确认已结束")
    }
}

extension RecommendedFeature {
    var cardTitle: String {
        switch self {
        case .widget: return BSLocalization.text("把小组件放到主屏幕")
        case .companion: return BSLocalization.text("邀请同行")
        case .listen: return BSLocalization.text("去听几首")
        case .timetable: return BSLocalization.text("存一张时刻表")
        case .dispersal: return BSLocalization.text("记下感受")
        case .memoryFragments: return BSLocalization.text("整理记忆碎片")
        case .footprint: return BSLocalization.text("去足迹看这一场")
        case .nextShow: return BSLocalization.text("切到下一场")
        case .addShow: return BSLocalization.text("添加下一场")
        }
    }
}
