import SwiftUI

// MARK: - Current Show Quick Actions

enum CurrentShowQuickAction: Hashable {
    case route
    case companion
    case ticket
    case timetable
    case memoryFragments
    case dispersal(completed: Bool)
    case endShow

    var title: String {
        switch self {
        case .route: return BSLocalization.text("路线")
        case .companion: return BSLocalization.text("同行")
        case .ticket: return BSLocalization.text("票根")
        case .timetable: return BSLocalization.text("时刻表")
        case .memoryFragments: return BSLocalization.text("记忆碎片")
        case .dispersal(let completed):
            return BSLocalization.text(completed ? "散场记录" : "记下感受")
        case .endShow: return BSLocalization.text("结束现场")
        }
    }

    var iconName: String {
        switch self {
        case .route: return "map"
        case .companion: return "person.2"
        case .ticket: return "ticket"
        case .timetable: return "list.bullet.rectangle"
        case .memoryFragments: return "photo.on.rectangle.angled"
        case .dispersal: return "rectangle.portrait.on.rectangle.portrait"
        case .endShow: return "flag.checkered"
        }
    }

    /// 快捷入口按生命周期排序:主行动已在卡片上,这里保留其余入口,
    /// 但把当前阶段次相关的动作后置,避免 ended 后路线/票根抢占记忆。
    /// `embedsRouteInLocation` 为真时路线收进倒计时地点,不再占一格。
    static func actions(
        for phase: HomeShowPhase,
        canRecordEnd: Bool = true,
        embedsRouteInLocation: Bool = false,
        isPostShowRetention: Bool = false,
        hasCompletedDispersalCeremony: Bool = false
    ) -> [Self] {
        let actions: [Self]
        switch phase {
        case .pre:
            actions = [.route, .ticket, .timetable, .companion, .memoryFragments]
        case .live:
            var live: [Self] = [.companion, .memoryFragments, .route, .ticket, .timetable]
            if canRecordEnd {
                live.insert(.endShow, at: 0)
            }
            actions = live
        case .ended:
            if isPostShowRetention {
                actions = [
                    .dispersal(completed: hasCompletedDispersalCeremony),
                    .memoryFragments,
                    .companion,
                    .ticket,
                    .timetable
                ]
            } else {
                actions = [.memoryFragments, .companion, .route, .ticket, .timetable]
            }
        case .inactive:
            actions = [.route, .companion, .ticket, .timetable, .memoryFragments]
        }
        return embedsRouteInLocation ? actions.filter { $0 != .route } : actions
    }
    /// 记录清单只接管主按钮没有承载的结束 / 散场入口，其余入口由清单按阶段给出。
    var recordKind: CurrentShowRecordKind? {
        switch self {
        case .endShow: return .endShow
        case .dispersal(let completed): return .dispersal(completed: completed)
        case .route, .companion, .ticket, .timetable, .memoryFragments: return nil
        }
    }

    /// 只移除与页面实际可见操作相同的快捷入口，不依赖文案或推荐候选。
    static func deduplicated(
        _ actions: [Self],
        primaryAction: HomeCountdownLockup.PrimaryAction?,
        hasInlineTimetableEntry: Bool = false
    ) -> [Self] {
        actions.filter { action in
            // 现场模式显示「完整时刻表」，即使它不是推荐主操作也不重复展示。
            if hasInlineTimetableEntry && action == .timetable { return false }
            switch primaryAction {
            case .some(.end(live: _)):
                return action != .endShow
            case .some(.memoryFragments):
                return action != .memoryFragments
            case .some(.memoryCreate), .none:
                // 新增记忆与查看现有记忆碎片是两个不同操作。
                return true
            case .some(.route):
                return action != .route
            case .some(.recommendation(let feature)):
                switch feature {
                case .companion: return action != .companion
                case .timetable: return action != .timetable
                case .memoryFragments: return action != .memoryFragments
                case .dispersal:
                    if case .dispersal = action { return false }
                    return true
                case .widget, .listen, .footprint, .nextShow, .addShow:
                    return true
                }
            }
        }
    }
}
