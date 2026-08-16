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
    static let widgetKind = BeforeShowWidgetKind.homeCountdown
    static let lockScreenWidgetKind = BeforeShowWidgetKind.lockScreenCountdown

    /// generation 在 MainActor(SwiftUI 调用方所在隔离域)预分配,
    /// 保证多次连续 sync 的版本顺序 = 调用顺序;actor 只认最大版本。
    @MainActor private static var syncGeneration: UInt64 = 0

    @MainActor
    @discardableResult
    static func sync(
        shows: [Show],
        manualSelection: CurrentShowSelection?,
        now: Date = Date()
    ) -> Bool {
        syncGeneration &+= 1
        let generation = syncGeneration

        let session = CurrentShowSession()
        let show = session.selectCurrentShow(from: shows, manualSelection: manualSelection, now: now)
        let snapshot = show.map { WidgetShowSnapshot(show: $0, generatedAt: now) }

        let previous = WidgetSnapshotStore.read()
        var didStoreSnapshot = true
        if contentChanged(from: previous, to: snapshot) {
            didStoreSnapshot = WidgetSnapshotStore.write(snapshot)
            if didStoreSnapshot {
                BeforeShowWidgetKind.reloadAllTimelines()
            }
        }

        // Show 是 SwiftData @Model(非 Sendable),跨并发边界只传值类型快照
        Task {
            await ShowLiveActivityController.shared.sync(
                snapshot: snapshot,
                now: now,
                generation: generation
            )
        }
        return didStoreSnapshot
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

// MARK: - Live Activity runtime selection

/// ActivityKit 对象不进入测试层;先投影为纯值记录,再决定唯一 keeper。
struct LiveActivityRuntimeRecord: Equatable {
    let id: String
    let showID: String
    let isPending: Bool
    let state: ShowLiveActivityAttributes.ContentState
}

enum LiveActivityRuntimeSelection {
    /// `.keep` 只允许保留一个完全一致的 pending。找不到时返回 nil,调用方应全部结束。
    static func pendingKeeperID(
        in records: [LiveActivityRuntimeRecord],
        showID: String?,
        state: ShowLiveActivityAttributes.ContentState
    ) -> String? {
        records.first(where: {
            $0.showID == showID && $0.isPending && $0.state == state
        })?.id
    }

    /// 同场去重优先级:目标 active → 目标 pending → ActivityKit 返回的第一条。
    static func duplicateKeeperID(
        in records: [LiveActivityRuntimeRecord],
        showID: String?,
        preferredState: ShowLiveActivityAttributes.ContentState?
    ) -> String? {
        let matching = records.filter { $0.showID == showID }
        guard !matching.isEmpty else { return nil }

        if let preferredState {
            if let active = matching.first(where: {
                !$0.isPending && $0.state == preferredState
            }) {
                return active.id
            }
            if let pending = matching.first(where: {
                $0.isPending && $0.state == preferredState
            }) {
                return pending.id
            }
        }
        return matching.first?.id
    }
}

// MARK: - Live Activity Controller

/// 决策全部在 Shared/LiveActivityPlanner(纯逻辑,可单测);
/// actor 只负责把动作翻译成 ActivityKit 调用并串行化。
actor ShowLiveActivityController {
    static let shared = ShowLiveActivityController()

    private struct PendingSync {
        let snapshot: WidgetShowSnapshot?
        let now: Date
        let generation: UInt64
    }

    private init() {}

    /// 已进入 actor 的最大 generation;小于它的 sync 全部丢弃。
    private var latestGeneration: UInt64 = 0
    /// actor 会在 await 处重入;新请求只覆盖待处理值,不会另起一条 ActivityKit mutation 链。
    private var pendingSync: PendingSync?
    private var isProcessing = false

    func sync(snapshot: WidgetShowSnapshot?, now: Date, generation: UInt64) async {
        latestGeneration = max(latestGeneration, generation)
        guard generation == latestGeneration else { return }

        pendingSync = PendingSync(snapshot: snapshot, now: now, generation: generation)
        guard !isProcessing else { return }

        isProcessing = true
        defer { isProcessing = false }

        // 单一 worker 串行执行 ActivityKit 副作用。actor 重入期间的新 sync 只更新
        // pendingSync;旧 mutation 完成后再按最新快照纠正,不会出现新旧 end/update 交叉。
        while let request = pendingSync {
            pendingSync = nil
            await process(request)
        }
    }

    private func process(_ request: PendingSync) async {
        guard request.generation == latestGeneration else { return }

        let snapshot = request.snapshot
        let now = request.now
        let activitiesEnabled = ActivityAuthorizationInfo().areActivitiesEnabled

        // 封面在窗口内或需要 schedule 时才拉取(LA 小图规格)。
        // 若下载期间来了更新请求,跳过旧请求的 prune / ActivityKit 副作用。
        let desired = LiveActivityPlanner.desiredState(
            snapshot: snapshot,
            now: now,
            coverFilename: nil
        )
        var coverFilename: String?
        if desired != nil, let source = snapshot?.coverImageURL {
            // App 侧下载是可靠路径;成功后若封面从无到有,主动 reload widget,
            // 避免 extension 下载被掐断后占位图挂到下一次 12h timeline。
            let hadWidgetCover = WidgetCoverCache.cachedCoverPath(matching: source) != nil
            await WidgetCoverCache.refresh(for: source)
            guard request.generation == latestGeneration else { return }
            coverFilename = WidgetCoverCache.freshLiveActivityCoverFilename(for: source)
            WidgetCoverCache.pruneCovers(except: source)
            let hasWidgetCover = WidgetCoverCache.cachedCoverPath(matching: source) != nil
            if !hadWidgetCover, hasWidgetCover {
                await MainActor.run {
                    BeforeShowWidgetKind.reloadAllTimelines()
                }
            }
        } else {
            // 无封面，或已无可展示现场(取消/结束/nil)时都清理历史缓存。
            guard request.generation == latestGeneration else { return }
            WidgetCoverCache.pruneCovers(except: nil)
        }

        guard request.generation == latestGeneration else { return }

        // 封面下载可能耗时；必须在所有 await 之后重新读取 ActivityKit，避免用过期列表决策。
        let existing: [LiveActivityExisting] = activitiesEnabled
            ? Activity<ShowLiveActivityAttributes>.activities.map {
                LiveActivityExisting(
                    showID: $0.attributes.showID,
                    isPending: Self.isPending($0),
                    state: $0.content.state
                )
            }
            : []

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

        guard request.generation == latestGeneration else { return }
        await perform(
            action,
            showID: snapshot?.showID.uuidString,
            generation: request.generation
        )
    }

    /// mutation 链由 sync 的单一 worker 串行化。generation 检查用于在新请求到达后
    /// 尽早停止剩余旧动作;已经发出的 ActivityKit 调用完成后,worker 会处理最新请求。
    private func perform(_ action: LiveActivityAction, showID: String?, generation: UInt64) async {
        func isCurrent() -> Bool { generation == latestGeneration }

        switch action {
        case .none:
            await endActivities(
                matching: { $0.attributes.showID != showID },
                generation: generation
            )
            guard isCurrent() else { return }
            await endDuplicates(
                keepingShowID: showID,
                preferring: nil,
                generation: generation
            )

        case .keep(let state):
            // 只留一个 pending + 完全一致的 ContentState;同场重复/stale 与其它场全部 end。
            await keepOnlyPending(
                showID: showID,
                state: state,
                generation: generation
            )

        case .update(let state):
            await endActivities(
                matching: { $0.attributes.showID != showID },
                generation: generation
            )
            guard isCurrent() else { return }
            await endDuplicates(
                keepingShowID: showID,
                preferring: state,
                generation: generation
            )
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
            await endAll(generation: generation)
            guard isCurrent() else { return }
            let content = ActivityContent(state: state, staleDate: state.endDate ?? state.startDate)
            request(attributes: ShowLiveActivityAttributes(showID: showID ?? ""), content: content)

        case .schedule(let state, let start):
            await endAll(generation: generation)
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
            await endAll(generation: generation)
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

    private static func isPending(_ activity: Activity<ShowLiveActivityAttributes>) -> Bool {
        if #available(iOS 26.0, *) {
            return activity.activityState == .pending
        }
        return false
    }

    private static func runtimeRecords(
        from activities: [Activity<ShowLiveActivityAttributes>]
    ) -> [LiveActivityRuntimeRecord] {
        activities.map {
            LiveActivityRuntimeRecord(
                id: $0.id,
                showID: $0.attributes.showID,
                isPending: isPending($0),
                state: $0.content.state
            )
        }
    }

    private func endActivities(
        matching predicate: (Activity<ShowLiveActivityAttributes>) -> Bool,
        generation: UInt64
    ) async {
        let activities = Activity<ShowLiveActivityAttributes>.activities
        for activity in activities where predicate(activity) {
            guard generation == latestGeneration else { return }
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    /// `.keep` 必须只保留一个正确 pending。两个完全相同的 pending 也要去重,
    /// 找不到正确 pending 时则全部结束,避免 Activity 状态变化后留下 stale 项。
    private func keepOnlyPending(
        showID: String?,
        state: ShowLiveActivityAttributes.ContentState,
        generation: UInt64
    ) async {
        let activities = Activity<ShowLiveActivityAttributes>.activities
        let keeperID = LiveActivityRuntimeSelection.pendingKeeperID(
            in: Self.runtimeRecords(from: activities),
            showID: showID,
            state: state
        )

        for activity in activities where activity.id != keeperID {
            guard generation == latestGeneration else { return }
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    /// 同一 showID 只留一个:优先 ContentState 与目标一致的(active 优于 pending),
    /// 避免 ActivityKit 返回顺序下误删正确 pending、留下旧 start。
    private func endDuplicates(
        keepingShowID showID: String?,
        preferring preferred: ShowLiveActivityAttributes.ContentState?,
        generation: UInt64
    ) async {
        let activities = Activity<ShowLiveActivityAttributes>.activities
        let matching = activities.filter { $0.attributes.showID == showID }
        guard matching.count > 1 else { return }

        guard let keeperID = LiveActivityRuntimeSelection.duplicateKeeperID(
            in: Self.runtimeRecords(from: matching),
            showID: showID,
            preferredState: preferred
        ) else {
            return
        }

        for activity in matching where activity.id != keeperID {
            guard generation == latestGeneration else { return }
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    private func endAll(generation: UInt64) async {
        let activities = Activity<ShowLiveActivityAttributes>.activities
        for activity in activities {
            guard generation == latestGeneration else { return }
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }
}
