import Foundation

// MARK: - Live Activity Lifecycle Planner
// 输入「现在 + 快照 + 现有活动」,输出按活动 id 的操作;controller 只负责翻译成 ActivityKit 调用。
// - 每段一个活动;当前段在窗口内则请求/更新,窗口外 iOS 26+ 预约。
// - 当天剩余各段同时预约好(App 被强杀后不会被唤醒补预约),到点由系统拉起;
//   App 被后台唤醒时结束上一段并接上推送。系统激活有数秒延迟,到点仍 pending 的段先等它。
// - 预约启动必带 alert:开场段替本地「开场前」提醒说话,后续段静音交接。
// - pending 的 start 在预约时固定:内容变了只能结束重建,不能 update。
// - 无现场 / 已取消 / 已过谢幕:全部结束;自然散场保留 15 分钟终态。

/// 现有活动的最小摘要(由 controller 从 ActivityKit 读取后传入)
struct LiveActivityExisting: Equatable {
    var id: String
    var showID: String
    var segmentEnd: Date? = nil
    var isPending: Bool
    var state: ShowLiveActivityAttributes.ContentState
}

enum LiveActivityOperation: Equatable {
    case end(id: String)
    case endNaturally(id: String, ShowLiveActivityAttributes.ContentState, dismissAt: Date)
    case update(id: String, ShowLiveActivityAttributes.ContentState)
    case request(ShowLiveActivityAttributes.ContentState, segmentEnd: Date)
    case schedule(ShowLiveActivityAttributes.ContentState, segmentEnd: Date, start: Date, isOpening: Bool)
}

extension LiveActivityPlanner {
    /// 预约段到点后系统激活的宽限期(真机实测约 3 秒)。
    static let pendingActivationGrace: TimeInterval = 60

    static func operations(
        snapshot: WidgetShowSnapshot?,
        now: Date,
        existing: [LiveActivityExisting],
        coverFilename: String?,
        focusedPerformanceID: UUID? = nil,
        artistImageFilename: (String) -> String? = { _ in nil },
        supportsScheduling: Bool = true
    ) -> [LiveActivityOperation] {
        guard let snapshot,
              snapshot.timing.changeStatus != .canceled,
              snapshot.timing.endedAt == nil,
              !(snapshot.timing.changeStatus == .postponed && snapshot.timing.postponedDate == nil) else {
            return existing.map { .end(id: $0.id) }
        }

        let showID = snapshot.showID.uuidString
        let mine = existing.filter { $0.showID == showID }
        var operations = existing.filter { $0.showID != showID }.map { LiveActivityOperation.end(id: $0.id) }

        func desired(at date: Date) -> (state: ShowLiveActivityAttributes.ContentState, activityEnd: Date, dayStart: Date)? {
            desiredState(
                snapshot: snapshot, now: date, coverFilename: coverFilename,
                focusedPerformanceID: focusedPerformanceID, artistImageFilename: artistImageFilename
            )
        }

        guard let current = desired(at: now) else {
            if let boundaries = naturalEndBoundary(snapshot: snapshot, now: now) {
                let dismissAt = boundaries.activityEnd.addingTimeInterval(dismissalGracePeriod)
                if now <= dismissAt {
                    let finalState = naturalFinalState(
                        snapshot: snapshot, dayStart: boundaries.dayStart,
                        activityEnd: boundaries.activityEnd, coverFilename: coverFilename
                    )
                    return operations + mine.map {
                        $0.isPending ? .end(id: $0.id) : .endNaturally(id: $0.id, finalState, dismissAt: dismissAt)
                    }
                }
            }
            return operations + mine.map { .end(id: $0.id) }
        }

        let segments = segments(snapshot: snapshot, desired: current)
        guard let index = segments.firstIndex(where: { now < $0.end }), let lastEnd = segments.last?.end else {
            return operations + mine.map { .end(id: $0.id) }
        }
        var claimed = Set<String>()
        var starts: [LiveActivityOperation] = []

        func activities(in segment: LiveActivitySegment) -> [LiveActivityExisting] {
            mine.filter { ($0.segmentEnd ?? lastEnd) == segment.end }
        }

        func schedule(_ segment: LiveActivitySegment, isOpening: Bool) {
            guard supportsScheduling,
                  segment.start.timeIntervalSince(now) <= scheduleHorizon,
                  let state = desired(at: segment.start)?.state else { return }
            // 旧版本预约的活动没有段信息、带着旧 alert:不保留。
            if let keeper = mine.first(where: { $0.isPending && $0.segmentEnd == segment.end && $0.state == state }) {
                claimed.insert(keeper.id)
            } else {
                starts.append(.schedule(state, segmentEnd: segment.end, start: segment.start, isOpening: isOpening))
            }
        }

        let segment = segments[index]
        if now >= segment.start {
            if let live = activities(in: segment).first(where: { !$0.isPending }) {
                claimed.insert(live.id)
                if live.state != current.state { starts.append(.update(id: live.id, current.state)) }
            } else if now < segment.start.addingTimeInterval(pendingActivationGrace),
                      let due = mine.first(where: {
                          $0.isPending && $0.segmentEnd == segment.end
                              && $0.state == desired(at: segment.start)?.state
                      }) {
                claimed.insert(due.id)
            } else {
                starts.append(.request(current.state, segmentEnd: segment.end))
            }
        } else {
            schedule(segment, isOpening: index == 0)
        }
        for later in segments.dropFirst(index + 1) {
            schedule(later, isOpening: false)
        }

        operations += mine.filter { !claimed.contains($0.id) }.map { .end(id: $0.id) }
        return operations + starts
    }

    /// 这一天的第一段:它的预约 alert 就是开场前的那条提醒。
    /// 段到点后宽限期内若还在等系统激活,宽限期一过要再规划一次。
    static func activationRetryDate(snapshot: WidgetShowSnapshot?, now: Date) -> Date? {
        guard let snapshot,
              let desired = desiredState(snapshot: snapshot, now: now, coverFilename: nil),
              let segment = segments(snapshot: snapshot, desired: desired)
                .last(where: { $0.start <= now }) else { return nil }
        let retry = segment.start.addingTimeInterval(pendingActivationGrace)
        return now < retry ? retry.addingTimeInterval(1) : nil
    }

    static func openingSegment(snapshot: WidgetShowSnapshot, now: Date) -> LiveActivitySegment? {
        desiredState(snapshot: snapshot, now: now, coverFilename: nil)
            .flatMap { segments(snapshot: snapshot, desired: $0).first }
    }
}
