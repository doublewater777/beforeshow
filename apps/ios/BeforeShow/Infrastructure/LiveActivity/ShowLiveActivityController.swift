@preconcurrency import ActivityKit
import Foundation

// MARK: - Live Activity Controller
// 把 LiveActivityPlanner.operations 翻译成 ActivityKit 调用,并把当前段的推送 token 交给云端计划。


actor ShowLiveActivityController {
    private var pushTokenTasks: [String: Task<Void, Never>] = [:]
    private var observedActivityIDs: [String: String] = [:]

    static let shared = ShowLiveActivityController()

    private struct PendingSync {
        let snapshot: WidgetShowSnapshot?
        let widgetCoverSource: String?
        let retainedCoverSources: Set<String>
        let now: Date
        let generation: UInt64
        let widgetReloadGeneration: UInt64
    }

    private init() {}

    private var latestGeneration: UInt64 = 0
    private var pendingSync: PendingSync?
    private var isProcessing = false
    private var lastWidgetReloadGeneration: UInt64 = 0
    private var artworkTask: Task<Void, Never>?
    private var boundaryTask: Task<Void, Never>?
    private var publishTail: Task<Void, Never>?

    func sync(
        snapshot: WidgetShowSnapshot?,
        widgetCoverSource: String?,
        retainedCoverSources: Set<String>,
        now: Date,
        generation: UInt64,
        widgetReloadGeneration: UInt64
    ) async {
        latestGeneration = max(latestGeneration, generation)
        guard generation == latestGeneration else { return }

        pendingSync = PendingSync(
            snapshot: snapshot,
            widgetCoverSource: widgetCoverSource,
            retainedCoverSources: retainedCoverSources,
            now: now,
            generation: generation,
            widgetReloadGeneration: widgetReloadGeneration
        )
        guard !isProcessing else { return }

        isProcessing = true
        defer { isProcessing = false }

        while let request = pendingSync {
            pendingSync = nil
            await process(request)
        }
    }

    private func process(_ request: PendingSync) async {
        guard request.generation == latestGeneration else { return }

        let snapshot = request.snapshot
        let now = request.now
        let focusedPerformanceID = LiveModeFocusStore.read()
        let desired = LiveActivityPlanner.desiredState(
            snapshot: snapshot,
            now: now,
            coverFilename: nil,
            focusedPerformanceID: focusedPerformanceID
        )

        artworkTask?.cancel()
        let normalizedWidgetSource = request.widgetCoverSource?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let hadWidgetCover = WidgetCoverCache.cachedCoverPath(matching: normalizedWidgetSource) != nil

        // 现场模式:主现场 / 同时在演 / 下一场的艺人头像与封面同一套缓存。
        let artistSources = desired == nil ? [] : LiveActivityPlanner.featuredArtistImageSources(
            snapshot: snapshot, now: now, focusedPerformanceID: focusedPerformanceID
        )
        let retained = request.retainedCoverSources.union(artistSources)
        await WidgetArtworkPreparation.prepareCached(sources: retained)
        guard request.generation == latestGeneration else { return }
        let hasWidgetCover = WidgetCoverCache.cachedCoverPath(matching: normalizedWidgetSource) != nil
        if request.widgetReloadGeneration > lastWidgetReloadGeneration || (!hadWidgetCover && hasWidgetCover) {
            lastWidgetReloadGeneration = request.widgetReloadGeneration
            await MainActor.run { BeforeShowWidgetKind.reloadAllTimelines() }
        }
        await publish(request, focusedPerformanceID: focusedPerformanceID)
        guard request.generation == latestGeneration else { return }
        await WidgetCoverCache.pruneCovers(keeping: retained)
        guard request.generation == latestGeneration else { return }

        // 到下一个场次边界用同一快照重新发布,实时活动才会换到下一位艺人。
        boundaryTask?.cancel()
        let boundaries = [
            LiveActivityPlanner.nextRefreshDate(snapshot: snapshot, now: now),
            LiveActivityPlanner.activationRetryDate(snapshot: snapshot, now: now),
        ]
        if let boundary = boundaries.compactMap({ $0 }).min() {
            boundaryTask = Task {
                try? await Task.sleep(for: .seconds(max(0, boundary.timeIntervalSinceNow) + 1))
                guard !Task.isCancelled else { return }
                await self.sync(
                    snapshot: request.snapshot,
                    widgetCoverSource: request.widgetCoverSource,
                    retainedCoverSources: request.retainedCoverSources,
                    now: Date(),
                    generation: request.generation,
                    widgetReloadGeneration: request.widgetReloadGeneration
                )
            }
        }

        // Downloads do not hold the sync queue: a new show/focus can publish immediately.
        artworkTask = Task {
            await WidgetArtworkPreparation.refresh(sources: retained) { source in
                await self.artworkReady(source, request: request, focusedPerformanceID: focusedPerformanceID)
            }
        }
    }

    private func artworkReady(_ source: String, request: PendingSync, focusedPerformanceID: UUID?) async {
        guard !Task.isCancelled, request.generation == latestGeneration else { return }
        if request.retainedCoverSources.contains(source) {
            await MainActor.run { BeforeShowWidgetKind.reloadAllTimelines() }
        }
        // 下载可能跨过交接点:按现在的时间重新规划,不能用发起同步时的 now。
        let fresh = PendingSync(
            snapshot: request.snapshot,
            widgetCoverSource: request.widgetCoverSource,
            retainedCoverSources: request.retainedCoverSources,
            now: Date(),
            generation: request.generation,
            widgetReloadGeneration: request.widgetReloadGeneration
        )
        await publish(fresh, focusedPerformanceID: focusedPerformanceID)
    }

    /// 同步与图片回调都会发布;串行执行,每次都重新读取 ActivityKit 状态,避免重复预约。
    private func publish(_ request: PendingSync, focusedPerformanceID: UUID?) async {
        let previous = publishTail
        let task = Task {
            await previous?.value
            await self.publishSerially(request, focusedPerformanceID: focusedPerformanceID)
        }
        publishTail = task
        await task.value
    }

    private func publishSerially(_ request: PendingSync, focusedPerformanceID: UUID?) async {
        guard request.generation == latestGeneration else { return }
        let snapshot = request.snapshot
        let activitiesEnabled = ActivityAuthorizationInfo().areActivitiesEnabled
        let liveSource = snapshot?.coverImageURL?.trimmingCharacters(in: .whitespacesAndNewlines)
        var coverFilename: String?
        if let liveSource, !liveSource.isEmpty {
            coverFilename = WidgetCoverCache.freshLiveActivityCoverFilename(for: liveSource)
        }

        let existing = Activity<ShowLiveActivityAttributes>.activities.map {
            LiveActivityExisting(
                id: $0.id,
                showID: $0.attributes.showID,
                segmentEnd: $0.attributes.segmentEnd,
                isPending: Self.isPending($0),
                state: $0.content.state
            )
        }
        let operations = activitiesEnabled
            ? LiveActivityPlanner.operations(
                snapshot: snapshot,
                now: request.now,
                existing: existing,
                coverFilename: coverFilename,
                focusedPerformanceID: focusedPerformanceID,
                artistImageFilename: WidgetCoverCache.freshLiveActivityCoverFilename(for:),
                supportsScheduling: Self.supportsScheduling
            )
            : existing.map { .end(id: $0.id) }

        guard request.generation == latestGeneration else { return }
        await perform(operations, snapshot: snapshot, now: request.now, generation: request.generation)
        guard request.generation == latestGeneration else { return }
        await updateOpeningCoverage(snapshot: snapshot, now: request.now)

        // 推送跟随当前段:进行中的优先,其次最早的预约段。
        guard request.generation == latestGeneration, let snapshot,
              let activity = Activity<ShowLiveActivityAttributes>.activities
                .filter({
                    $0.attributes.showID == snapshot.showID.uuidString
                        && ($0.activityState == .active || $0.activityState == .stale || Self.isPending($0))
                })
                .min(by: { Self.pushPriority($0) < Self.pushPriority($1) }) else { return }
        await registerPushTokenUpdates(for: activity, showID: snapshot.showID.uuidString, snapshot: snapshot, focusedPerformanceID: focusedPerformanceID)
    }

    private func perform(
        _ operations: [LiveActivityOperation],
        snapshot: WidgetShowSnapshot?,
        now: Date,
        generation: UInt64
    ) async {
        let showID = snapshot?.showID.uuidString ?? ""
        var endedNaturally = false
        for operation in operations {
            guard generation == latestGeneration else { return }
            switch operation {
            case .end(let id):
                await activity(id)?.end(nil, dismissalPolicy: .immediate)

            case .endNaturally(let id, let state, let dismissDate):
                let content = ActivityContent(state: state, staleDate: dismissDate)
                await activity(id)?.end(content, dismissalPolicy: .after(dismissDate))
                endedNaturally = true

            case .update(let id, let state):
                await activity(id)?.update(ActivityContent(state: state, staleDate: state.staleDate))

            case .request(let state, let segmentEnd):
                request(
                    attributes: ShowLiveActivityAttributes(showID: showID, segmentEnd: segmentEnd),
                    content: ActivityContent(state: state, staleDate: state.staleDate)
                )

            case .schedule(let state, let segmentEnd, let start, let isOpening):
                let opening = snapshot.flatMap {
                    LiveActivityPlanner.desiredState(snapshot: $0, now: now, coverFilename: nil)?.dayStart
                }
                let alert = isOpening
                    ? snapshot.flatMap { snapshot in
                        opening.map { LiveActivityAlertCopy.opening(snapshot: snapshot, opening: $0, start: start) }
                    }
                    : LiveActivityAlertCopy.handover(state: state)
                schedule(
                    attributes: ShowLiveActivityAttributes(showID: showID, segmentEnd: segmentEnd),
                    content: ActivityContent(state: state, staleDate: state.staleDate),
                    start: start,
                    alert: alert ?? LiveActivityAlertCopy.handover(state: state),
                    isSilent: !isOpening
                )
            }
        }
        if endedNaturally {
            await LiveActivityPushCoordinator.shared.revoke(showID: showID)
        }
    }

    private func activity(_ id: String) -> Activity<ShowLiveActivityAttributes>? {
        Activity<ShowLiveActivityAttributes>.activities.first { $0.id == id }
    }

    private func request(
        attributes: ShowLiveActivityAttributes,
        content: ActivityContent<ShowLiveActivityAttributes.ContentState>
    ) {
        do {
            _ = try Activity<ShowLiveActivityAttributes>.request(
                attributes: attributes,
                content: content,
                pushType: .token
            )
        } catch {
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
    }

    private func schedule(
        attributes: ShowLiveActivityAttributes,
        content: ActivityContent<ShowLiveActivityAttributes.ContentState>,
        start: Date,
        alert: LiveActivityAlertCopy,
        isSilent: Bool
    ) {
        guard #available(iOS 26, *) else { return }
        do {
            // 预约启动必带 alert;交接用无声音频,只亮屏不响。
            _ = try Activity<ShowLiveActivityAttributes>.request(
                attributes: attributes,
                content: content,
                pushType: .token,
                style: .standard,
                alertConfiguration: AlertConfiguration(
                    title: LocalizedStringResource(stringLiteral: alert.title),
                    body: LocalizedStringResource(stringLiteral: alert.body),
                    sound: isSilent ? .named(Self.silentAlertSound) : .default
                ),
                start: start
            )
        } catch {
            #if DEBUG
            print("[ShowLiveActivity] schedule failed: \(error)")
            #endif
        }
    }

    private static let silentAlertSound = "silence.caf"

    /// 开场段预约成功时,开场前的那条提醒交给它的 alert,本地通知让出。
    private func updateOpeningCoverage(snapshot: WidgetShowSnapshot?, now: Date) async {
        let opening = snapshot.flatMap { LiveActivityPlanner.openingSegment(snapshot: $0, now: now) }
        let isScheduled = opening.map { segment in
            Activity<ShowLiveActivityAttributes>.activities.contains {
                $0.attributes.showID == snapshot?.showID.uuidString
                    && Self.isPending($0) && $0.attributes.segmentEnd == segment.end
            }
        } ?? false
        let changed = LiveActivityOpeningCoverage().reconcile(
            liveShowID: snapshot?.showID, coveredOpening: isScheduled ? opening?.start : nil, now: now
        )
        if changed {
            _ = await LocalNotificationCenter.shared.reconcilePortfolio()
        }
    }

    private static var supportsScheduling: Bool {
        if #available(iOS 26, *) { return true }
        return false
    }

    private static func isPending(_ activity: Activity<ShowLiveActivityAttributes>) -> Bool {
        if #available(iOS 26, *) { return activity.activityState == .pending }
        return false
    }

    private static func pushPriority(_ activity: Activity<ShowLiveActivityAttributes>) -> (Int, Date) {
        (isPending(activity) ? 1 : 0, activity.attributes.segmentEnd ?? .distantFuture)
    }

    private func registerPushTokenUpdates(
        for activity: Activity<ShowLiveActivityAttributes>,
        showID: String,
        snapshot: WidgetShowSnapshot,
        focusedPerformanceID: UUID?
    ) async {
        await LiveActivityPushCoordinator.shared.updateSnapshot(snapshot, focusedPerformanceID: focusedPerformanceID)
        guard observedActivityIDs[showID] != activity.id else { return }
        pushTokenTasks[showID]?.cancel()
        observedActivityIDs[showID] = activity.id
        pushTokenTasks[showID] = Task {
            guard !Task.isCancelled else { return }
            var previousToken: Data?
            if let token = activity.pushToken {
                previousToken = token
                await LiveActivityPushCoordinator.shared.handleTokenUpdate(
                    token.map { String(format: "%02x", $0) }.joined(), for: showID
                )
            }
            for await tokenData in activity.pushTokenUpdates {
                guard !Task.isCancelled else { break }
                guard tokenData != previousToken else { continue }
                previousToken = tokenData
                let hexToken = tokenData.map { String(format: "%02x", $0) }.joined()
                await LiveActivityPushCoordinator.shared.handleTokenUpdate(hexToken, for: showID)
            }
        }
    }
}
