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
            var live: [Self] = [.memoryFragments, .companion, .route, .timetable, .ticket]
            if canRecordEnd {
                live.append(.endShow)
            }
            actions = live
        case .ended:
            if isPostShowRetention {
                actions = [
                    .dispersal(completed: hasCompletedDispersalCeremony),
                    .memoryFragments,
                    .ticket,
                    .companion,
                    .timetable
                ]
            } else {
                // 散场后路线已经用不上。
                actions = [.memoryFragments, .ticket, .companion, .timetable]
            }
        case .inactive:
            actions = [.route, .companion, .timetable, .memoryFragments, .ticket]
        }
        return embedsRouteInLocation ? actions.filter { $0 != .route } : actions
    }
    /// 主按钮已经是路线时，不再重复路线入口。
    static func deduplicated(
        _ actions: [Self],
        primaryAction: HomeCountdownLockup.PrimaryAction?
    ) -> [Self] {
        primaryAction == .route ? actions.filter { $0 != .route } : actions
    }
}
