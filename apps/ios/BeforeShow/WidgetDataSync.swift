import ActivityKit
import Foundation
import WidgetKit

// MARK: - Widget Data Sync
// 「当前现场」变化时的单一出口:内容变化才写 App Group 快照 + reload widget →
// 对齐 Live Activity 生命周期。RootView 在 shows/selections 变化与回到前台时调用。
//
// Live Activity 产品口径(无 push,评审定稿):
// - 活跃窗口 = 预计谢幕前最多 8h(平台活跃上限),窗口内打开过 app 才会启动;
//   iOS 26+ 额外在窗口起点 schedule,不依赖窗口内打开
// - 谢幕时不承诺准点结束:staleDate 标记过期,下一次 app 运行时 end;
//   UI 为中性文案,越过谢幕也不会显示「LIVE」

enum WidgetDataSync {
    static let widgetKind = "BeforeShowCountdownWidget"

    /// generation 在 MainActor(SwiftUI 调用方所在隔离域)预分配,
    /// 保证多次连续 sync 的版本顺序 = 调用顺序;actor 只认最大版本。
    @MainActor private static var syncGeneration: UInt64 = 0

    @MainActor
    static func sync(shows: [Show], manualSelection: CurrentShowSelection?, now: Date = Date()) {
        syncGeneration &+= 1
        let generation = syncGeneration

        let session = CurrentShowSession()
        let show = session.selectCurrentShow(from: shows, manualSelection: manualSelection, now: now)
        let snapshot = show.map { WidgetShowSnapshot(show: $0, generatedAt: now) }

        let previous = WidgetSnapshotStore.read()
        if contentChanged(from: previous, to: snapshot) {
            WidgetSnapshotStore.write(snapshot)
            WidgetCenter.shared.reloadTimelines(ofKind: widgetKind)
        }

        // Show 是 SwiftData @Model(非 Sendable),跨并发边界只传值类型快照
        Task {
            await ShowLiveActivityController.shared.sync(
                snapshot: snapshot,
                now: now,
                generation: generation
            )
        }
    }

    private static func contentChanged(
        from previous: WidgetShowSnapshot?,
        to snapshot: WidgetShowSnapshot?
    ) -> Bool {
        switch (previous, snapshot) {
        case (nil, nil):
            return false
        case (nil, .some), (.some, nil):
            return true
        case let (a?, b?):
            return !a.isContentEqual(to: b)
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

/// 决策全部在 Shared/LiveActivityPlanner(纯逻辑,可单测);
/// actor 只负责把动作翻译成 ActivityKit 调用并串行化。
actor ShowLiveActivityController {
    static let shared = ShowLiveActivityController()

    private init() {}

    /// 已进入 actor 的最大 generation;小于它的 sync 全部丢弃。
    private var latestGeneration: UInt64 = 0

    func sync(snapshot: WidgetShowSnapshot?, now: Date, generation: UInt64) async {
        latestGeneration = max(latestGeneration, generation)
        guard generation == latestGeneration else { return }

        let activitiesEnabled = ActivityAuthorizationInfo().areActivitiesEnabled
        let existing: [LiveActivityExisting] = activitiesEnabled
            ? Activity<ShowLiveActivityAttributes>.activities.map {
                LiveActivityExisting(
                    showID: $0.attributes.showID,
                    isPending: isPending($0),
                    state: $0.content.state
                )
            }
            : []

        // 封面在窗口内或需要 schedule 时才拉取(LA 小图规格);
        // prune 只在 generation 仍有效时执行,避免旧 sync 删掉新场封面。
        let desired = LiveActivityPlanner.desiredState(
            snapshot: snapshot,
            now: now,
            coverFilename: nil
        )
        var coverFilename: String?
        if desired != nil, let source = snapshot?.coverImageURL {
            await WidgetCoverCache.refresh(for: source)
            guard generation == latestGeneration else { return }
            coverFilename = WidgetCoverCache.freshLiveActivityCoverFilename(for: source)
            WidgetCoverCache.pruneCovers(except: source)
        } else if desired != nil {
            guard generation == latestGeneration else { return }
            WidgetCoverCache.pruneCovers(except: nil)
        }

        let action: LiveActivityAction
        if activitiesEnabled {
            let canSchedule: Bool
            if #available(iOS 26.0, *) {
                canSchedule = true
            } else {
                canSchedule = false
            }
            action = LiveActivityPlanner.action(
                snapshot: snapshot,
                now: now,
                existing: existing,
                coverFilename: coverFilename,
                canSchedule: canSchedule
            )
        } else {
            action = .endAll
        }

        guard generation == latestGeneration else { return }
        await perform(action, showID: snapshot?.showID.uuidString, generation: generation)
    }

    /// actor 在每个 await 上允许重入:任何副作用(尤其 request/schedule)前
    /// 都必须重新确认自己还是最新 generation,否则旧动作会后至覆盖新状态。
    private func perform(_ action: LiveActivityAction, showID: String?, generation: UInt64) async {
        func isCurrent() -> Bool { generation == latestGeneration }

        switch action {
        case .none:
            // pending 保留;只清理非目标/重复
            await endActivities(matching: { $0.attributes.showID != showID })
            guard isCurrent() else { return }
            await endDuplicates(keepingShowID: showID)

        case .update(let state):
            await endActivities(matching: { $0.attributes.showID != showID })
            guard isCurrent() else { return }
            await endDuplicates(keepingShowID: showID)
            guard isCurrent() else { return }
            let target = Activity<ShowLiveActivityAttributes>.activities
                .first(where: { $0.attributes.showID == showID })
            let content = ActivityContent(state: state, staleDate: state.endDate ?? state.startDate)
            if let target {
                await target.update(content)
            } else {
                guard isCurrent() else { return }
                request(attributes: ShowLiveActivityAttributes(showID: showID ?? ""), content: content)
            }

        case .request(let state):
            await endAll()
            guard isCurrent() else { return }
            let content = ActivityContent(state: state, staleDate: state.endDate ?? state.startDate)
            request(attributes: ShowLiveActivityAttributes(showID: showID ?? ""), content: content)

        case .schedule(let state, let start):
            await endAll()
            guard isCurrent() else { return }
            let content = ActivityContent(state: state, staleDate: state.endDate ?? state.startDate)
            if #available(iOS 26.0, *) {
                do {
                    let alert = AlertConfiguration(
                        title: "开场前",
                        body: LocalizedStringResource(stringLiteral: "\(state.showName) 倒计时已开始"),
                        sound: .default
                    )
                    _ = try Activity<ShowLiveActivityAttributes>.request(
                        attributes: ShowLiveActivityAttributes(showID: showID ?? ""),
                        content: content,
                        pushType: nil,
                        style: .standard,
                        alertConfiguration: alert,
                        start: start
                    )
                } catch {
                    #if DEBUG
                    print("[ShowLiveActivity] schedule failed: \(error)")
                    #endif
                }
            }

        case .endAll:
            await endAll()
        }
    }

    private func request(
        attributes: ShowLiveActivityAttributes,
        content: ActivityContent<ShowLiveActivityAttributes.ContentState>
    ) {
        do {
            _ = try Activity<ShowLiveActivityAttributes>.request(
                attributes: attributes,
                content: content,
                pushType: nil
            )
        } catch {
            #if DEBUG
            print("[ShowLiveActivity] request failed: \(error)")
            #endif
        }
    }

    private func isPending(_ activity: Activity<ShowLiveActivityAttributes>) -> Bool {
        if #available(iOS 26.0, *) {
            return activity.activityState == .pending
        }
        return false
    }

    private func endActivities(
        matching predicate: (Activity<ShowLiveActivityAttributes>) -> Bool
    ) async {
        for activity in Activity<ShowLiveActivityAttributes>.activities where predicate(activity) {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    /// 同一 showID 只保留第一个,清掉历史并发残留的重复活动。
    private func endDuplicates(keepingShowID showID: String?) async {
        let matching = Activity<ShowLiveActivityAttributes>.activities
            .filter { $0.attributes.showID == showID }
        for activity in matching.dropFirst() {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    private func endAll() async {
        for activity in Activity<ShowLiveActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }
}
