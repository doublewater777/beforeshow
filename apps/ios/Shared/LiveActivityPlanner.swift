import Foundation

// MARK: - Live Activity Planner
// 生命周期决策的纯逻辑,与 ActivityKit 解耦:输入「现在 + 快照 + 现有活动摘要」,
// 输出动作。actor 只负责把动作翻译成 ActivityKit 调用。
// 规则(评审定稿):
// - 活跃窗口 = 预计谢幕前最多 8h(平台活跃上限)
// - 窗口外:iOS 26+ 可 schedule;pending 内容未变时保留,不重复 schedule
// - pending 的 start 在 request/schedule 时固定,update 无法改启动时刻
//   → 内容变了必须 end + request/schedule(或超出视野则 end),不能 .update / .none 保留
// - 无现场 / 已取消 / 已过谢幕:结束全部

/// 现有活动的最小摘要(由 actor 从 ActivityKit 读取后传入)
struct LiveActivityExisting: Equatable {
    var showID: String
    var isPending: Bool
    var state: ShowLiveActivityAttributes.ContentState
}

enum LiveActivityAction: Equatable {
    /// 无需新建;携带目标 ContentState 时:只保留「pending 且 state 完全一致」的活动,
    /// 同 show 的 stale pending / 其它 show 全部结束(解决双 pending 竞态)。
    case keep(ShowLiveActivityAttributes.ContentState)
    /// 无任何活动需要保留或创建(无现场残留已清 / 超视野且无匹配)
    case none
    /// 窗口内,更新现有活动(仅 active;pending 内容变了不能走这条)
    case update(ShowLiveActivityAttributes.ContentState)
    /// 窗口内,无现有活动 / pending 内容已变 → 立即启动(perform 会先 endAll)
    case request(ShowLiveActivityAttributes.ContentState)
    /// 窗口外(iOS 26+),在活跃窗口起点调度启动(perform 会先 endAll)
    case schedule(ShowLiveActivityAttributes.ContentState, start: Date)
    /// 无现场 / 已取消 / 已过谢幕 / 无权限 / 过期 pending 需清掉 → 结束全部
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
                timeZoneSecondsFromGMT: snapshot.timing.timeZoneSecondsFromGMT,
                endTimeZoneSecondsFromGMT: snapshot.timing.endTimeZoneSecondsFromGMT,
                timeZoneIdentifier: snapshot.timing.timeZoneIdentifier,
                endTimeZoneIdentifier: snapshot.timing.endTimeZoneIdentifier,
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
        let pending = matching.filter(\.isPending)
        let hasStalePending = pending.contains { $0.state != desired.state }
        let hasUnchangedPending = pending.contains { $0.state == desired.state }

        if inWindow {
            // pending 的启动时刻在 schedule/request 时已固定,update 改不了 startDate。
            // 内容变了(改开场时间等)→ end + 立即 request,否则会按旧时间启动。
            if hasStalePending || matching.isEmpty {
                return .request(desired.state)
            }
            return .update(desired.state)
        }

        // 窗口外
        if canSchedule {
            // 至少有一个内容正确的 pending:keep 会清掉同场 stale 残留,不重复 schedule
            if hasUnchangedPending {
                return .keep(desired.state)
            }

            // 超出视野:不得保留「旧 start」的 pending;有残留就清掉
            if earliest.timeIntervalSince(now) > scheduleHorizon {
                return matching.isEmpty ? .none : .endAll
            }

            // 内容变了或尚无 pending → endAll + 按新 earliest schedule
            return .schedule(desired.state, start: earliest)
        }

        // 不能 schedule 的系统:窗口外无法纠正 pending,清掉等下次窗口内打开
        return .endAll
    }
}
