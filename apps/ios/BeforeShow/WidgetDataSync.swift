import ActivityKit
import Foundation
import WidgetKit

// MARK: - Widget Data Sync
// 「当前现场」变化时的单一出口:写 App Group 快照 → 刷新 widget timeline →
// 对齐 Live Activity 生命周期。RootView 在 shows/selections 变化与回到前台时调用。

enum WidgetDataSync {
    static let widgetKind = "BeforeShowCountdownWidget"

    static func sync(shows: [Show], manualSelection: CurrentShowSelection?, now: Date = Date()) {
        let session = CurrentShowSession()
        let show = session.selectCurrentShow(from: shows, manualSelection: manualSelection, now: now)
        let snapshot = show.map { WidgetShowSnapshot(show: $0, generatedAt: now) }
        let previous = WidgetSnapshotStore.read()
        WidgetSnapshotStore.write(snapshot)
        if previous != snapshot {
            WidgetCenter.shared.reloadTimelines(ofKind: widgetKind)
        }

        // Show 是 SwiftData @Model(非 Sendable),跨并发边界只传值类型快照
        Task {
            await ShowLiveActivityController.shared.sync(snapshot: snapshot, now: now)
        }
    }
}

extension WidgetShowSnapshot {
    init(show: Show, generatedAt: Date) {
        self.init(
            showID: show.id,
            name: show.name,
            city: show.city,
            venueName: show.venueName,
            coverImageURL: show.coverImageURL,
            timing: show.timingFields,
            generatedAt: generatedAt
        )
    }
}

// MARK: - Live Activity Controller

/// 生命周期:在「预计谢幕前最多 8 小时」窗口内启动/保持(平台活跃上限 8h),
/// 越过预计谢幕结束。可编辑字段走 ContentState,同一 show 延期/改场馆可 update。
/// actor 串行化 request/update/end,避免并发 sync 竞态。
actor ShowLiveActivityController {
    static let shared = ShowLiveActivityController()

    /// ActivityKit:活跃最长 8 小时(之后最多再在锁屏保留 4 小时,但已从灵动岛移除)。
    static let maxActiveDuration: TimeInterval = 8 * 3_600

    /// 单调版本号:丢弃过期的并发 sync。
    private var syncGeneration: UInt64 = 0

    func sync(snapshot: WidgetShowSnapshot?, now: Date) async {
        syncGeneration &+= 1
        let generation = syncGeneration

        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            await endAll()
            return
        }

        guard let snapshot,
              snapshot.timing.changeStatus != .canceled else {
            await endAll()
            return
        }

        let state = CurrentShowTimeState(timing: snapshot.timing, now: now)
        guard let start = state.effectiveStartTime else {
            await endAll()
            return
        }
        let activityEnd = state.endBoundary ?? start.addingTimeInterval(
            TimeInterval(CurrentShowTimeState.defaultDurationHours) * 3_600
        )

        guard now < activityEnd else {
            await endAll()
            return
        }

        let earliestStart = WidgetTimelinePlanner.liveActivityEarliestStart(
            activityEnd: activityEnd,
            maxActiveDuration: Self.maxActiveDuration
        )
        let inWindow = now >= earliestStart
        let showID = snapshot.showID.uuidString

        // 窗口外:结束已有活动(含本场旧数据)。iOS 26+ 可 schedule;更早系统需窗口内打开 app。
        if !inWindow {
            await endAll()
            guard generation == syncGeneration else { return }
            if #available(iOS 26.0, *) {
                // fall through to schedule
            } else {
                return
            }
        }

        await WidgetCoverCache.refresh(for: snapshot.coverImageURL)
        guard generation == syncGeneration else { return }

        let coverFilename = snapshot.coverImageURL.flatMap { WidgetCoverCache.freshCoverFilename(for: $0) }
        let phase: ShowLiveActivityPhase = now >= start ? .live : .countdown
        let contentState = ShowLiveActivityAttributes.ContentState(
            phase: phase,
            showName: snapshot.name,
            city: snapshot.city,
            venueName: snapshot.venueName,
            startDate: start,
            endDate: state.endBoundary,
            coverImageFilename: coverFilename
        )
        // 倒计时阶段 stale 在开场;live 阶段 stale 在谢幕
        let staleDate = now >= start ? activityEnd : start
        let content = ActivityContent(state: contentState, staleDate: staleDate)
        let attributes = ShowLiveActivityAttributes(showID: showID)

        // 清理非目标与重复
        let matching = Activity<ShowLiveActivityAttributes>.activities.filter {
            $0.attributes.showID == showID
        }
        for activity in Activity<ShowLiveActivityAttributes>.activities where activity.attributes.showID != showID {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        if matching.count > 1 {
            for activity in matching.dropFirst() {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
        guard generation == syncGeneration else { return }

        if inWindow, let existing = matching.first {
            await existing.update(content)
            return
        }

        // 窗口外已 endAll,matching 应为空;窗口内无 existing 则 request
        guard generation == syncGeneration else { return }

        do {
            if inWindow {
                _ = try Activity.request(
                    attributes: attributes,
                    content: content,
                    pushType: nil
                )
            } else if #available(iOS 26.0, *) {
                // 在活跃窗口起点 schedule,无需用户在窗口内再打开 app
                let alert = AlertConfiguration(
                    title: "开场前",
                    body: LocalizedStringResource(stringLiteral: "\(snapshot.name) 倒计时已开始"),
                    sound: .default
                )
                _ = try Activity.request(
                    attributes: attributes,
                    content: content,
                    pushType: nil,
                    style: .standard,
                    alertConfiguration: alert,
                    start: earliestStart
                )
            }
        } catch {
            #if DEBUG
            print("[ShowLiveActivity] request failed: \(error)")
            #endif
        }
    }

    private func endAll() async {
        for activity in Activity<ShowLiveActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }
}
