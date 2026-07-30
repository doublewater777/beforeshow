import Foundation

// MARK: - Live Activity Planner
// 生命周期决策的纯逻辑,与 ActivityKit 解耦:输入「现在 + 快照 + 现有活动摘要」,
// 输出动作。actor 只负责把动作翻译成 ActivityKit 调用。
// 规则(评审定稿):
// - 活跃窗口 = 预计谢幕前最多 8h(平台活跃上限)
// - 窗口外:iOS 26+ 可 schedule;pending 内容未变时保留,不重复 schedule
// - 无现场 / 已取消 / 已过谢幕:结束全部

/// 现有活动的最小摘要(由 actor 从 ActivityKit 读取后传入)
struct LiveActivityExisting: Equatable {
    var showID: String
    var isPending: Bool
    var state: ShowLiveActivityAttributes.ContentState
}

enum LiveActivityAction: Equatable {
    /// 目标与现状一致,无需动作(pending 保留)
    case none
    /// 窗口内,更新现有活动
    case update(ShowLiveActivityAttributes.ContentState)
    /// 窗口内,无现有活动 → 立即启动
    case request(ShowLiveActivityAttributes.ContentState)
    /// 窗口外(iOS 26+),在活跃窗口起点调度启动
    case schedule(ShowLiveActivityAttributes.ContentState, start: Date)
    /// 无现场 / 已取消 / 已过谢幕 / 无权限 → 结束全部
    case endAll
}

enum LiveActivityPlanner {
    /// 平台活跃上限:8h(之后最多再在锁屏保留 4h,但已从灵动岛移除)
    static let maxActiveDuration: TimeInterval = 8 * 3_600

    /// schedule 视野:pending 也占系统 Live Activity 配额,
    /// 不为几个月后的现场长期占位;更远等下一次前台同步再安排。
    static let scheduleHorizon: TimeInterval = 7 * 86_400

    /// 由快照推导目标内容态;nil = 不应有活动(无现场/已取消/无确定开场/已过谢幕)
    static func desiredState(
        snapshot: WidgetShowSnapshot?,
        now: Date,
        coverFilename: String?
    ) -> (state: ShowLiveActivityAttributes.ContentState, activityEnd: Date)? {
        guard let snapshot,
              snapshot.timing.changeStatus != .canceled else {
            return nil
        }
        let timeState = CurrentShowTimeState(timing: snapshot.timing, now: now)
        guard let start = timeState.effectiveStartTime else {
            return nil
        }
        let activityEnd = timeState.endBoundary ?? start.addingTimeInterval(
            TimeInterval(CurrentShowTimeState.defaultDurationHours) * 3_600
        )
        guard now < activityEnd else {
            return nil
        }
        return (
            ShowLiveActivityAttributes.ContentState(
                showName: snapshot.name,
                city: snapshot.city,
                venueName: snapshot.venueName,
                startDate: start,
                endDate: timeState.endBoundary,
                coverImageFilename: coverFilename
            ),
            activityEnd
        )
    }

    /// 活跃窗口起点:保证活跃时长 ≤ maxActiveDuration;
    /// 跨天/超 8h 现场则钳到开场时刻——「开场前」活动绝不能排到开场之后,
    /// 接受这类现场的活动在谢幕前被系统结束。
    static func earliestStart(activityStart: Date, activityEnd: Date) -> Date {
        min(activityStart, activityEnd.addingTimeInterval(-maxActiveDuration))
    }

    static func action(
        snapshot: WidgetShowSnapshot?,
        now: Date,
        existing: [LiveActivityExisting],
        coverFilename: String?,
        canSchedule: Bool
    ) -> LiveActivityAction {
        guard let desired = desiredState(snapshot: snapshot, now: now, coverFilename: coverFilename),
              let snapshot else {
            return .endAll
        }

        let showID = snapshot.showID.uuidString
        let matching = existing.filter { $0.showID == showID }
        let earliest = earliestStart(activityStart: desired.state.startDate, activityEnd: desired.activityEnd)
        let inWindow = now >= earliest

        if inWindow {
            return matching.isEmpty ? .request(desired.state) : .update(desired.state)
        }

        // 窗口外:pending 内容未变则保留,不重复 schedule(每次回前台重建会消耗系统配额)
        if canSchedule {
            if matching.contains(where: { $0.isPending && $0.state == desired.state }) {
                return .none
            }
            // 超出视野不 schedule:pending 也占配额,等临近后的前台同步再安排
            if earliest.timeIntervalSince(now) > scheduleHorizon {
                return .none
            }
            return .schedule(desired.state, start: earliest)
        }

        return .endAll
    }
}
