@preconcurrency import ActivityKit
import Foundation
import WidgetKit

// MARK: - Widget / Live Activity Sync
// Widget and Live Activity both follow the durable user-owned Current Show.
// Both surfaces share the cover cache, so pruning keeps the union of their sources.

enum WidgetDataSync {
    static let widgetKind = BeforeShowWidgetKind.homeCountdown
    static let lockScreenWidgetKind = BeforeShowWidgetKind.lockScreenCountdown

    @MainActor private static var syncGeneration: UInt64 = 0
    @MainActor private static var widgetReloadGeneration: UInt64 = 0

    @MainActor
    @discardableResult
    static func sync(
        shows: [Show],
        manualSelection: CurrentShowSelection?,
        now: Date = Date()
    ) -> Bool {
        let validShows = shows.filter { $0.modelContext != nil }
        syncGeneration &+= 1
        let generation = syncGeneration

        let session = CurrentShowSession()
        let currentShow = session.selectCurrentShow(
            from: validShows,
            manualSelection: manualSelection,
            now: now
        )
        let liveActivityShow = LiveActivityShowResolver().resolve(
            shows: validShows,
            currentShow: currentShow,
            now: now
        )

        let widgetSnapshot = currentShow.map { WidgetShowSnapshot(show: $0, generatedAt: now) }
        let liveActivitySnapshot = liveActivityShow.map { WidgetShowSnapshot(show: $0, generatedAt: now) }
        var retainedCoverSources = Set(
            [widgetSnapshot?.coverImageURL, liveActivitySnapshot?.coverImageURL]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        )

        let previous = WidgetSnapshotStore.read()
        var didStoreSnapshot = true
        if contentChanged(from: previous, to: widgetSnapshot) {
            didStoreSnapshot = WidgetSnapshotStore.write(widgetSnapshot)
            if didStoreSnapshot {
                let currentListening = WidgetListeningStore.read()
                if currentListening?.showID != currentShow?.id {
                    if let currentShow {
                        let baselineListening = WidgetListeningSnapshot(
                            showID: currentShow.id,
                            showName: currentShow.name,
                            artistName: currentShow.artists.first?.name,
                            discTitle: nil,
                            trackTitle: nil,
                            coverImageURL: nil,
                            trackCount: nil,
                            isPlaying: false,
                            generatedAt: now
                        )
                        WidgetListeningStore.write(baselineListening)
                    } else {
                        WidgetListeningStore.write(nil)
                    }
                }
                widgetReloadGeneration = generation
            }
        }

        if let listening = WidgetListeningStore.read(), listening.showID == currentShow?.id,
           let cover = listening.coverImageURL, !cover.isEmpty {
            retainedCoverSources.insert(cover)
        }

        let reloadGeneration = widgetReloadGeneration
        // SwiftData Show is not Sendable; only immutable value snapshots cross actors.
        Task {
            await ShowLiveActivityController.shared.sync(
                snapshot: liveActivitySnapshot,
                widgetCoverSource: widgetSnapshot?.coverImageURL,
                retainedCoverSources: retainedCoverSources,
                now: now,
                generation: generation,
                widgetReloadGeneration: reloadGeneration
            )
        }
        return didStoreSnapshot
    }

    private static func contentChanged(
        from previous: WidgetShowSnapshot?,
        to snapshot: WidgetShowSnapshot?
    ) -> Bool {
        switch (previous, snapshot) {
        case (nil, nil): return false
        case (nil, .some), (.some, nil): return true
        case let (a?, b?): return !a.isContentEqual(to: b)
        }
    }
}


extension WidgetShowSnapshot {
    @MainActor
    init(show: Show, generatedAt: Date) {
        let timetableSnapshot: WidgetTimetableSnapshot?
        if let timetable = show.lifecycleTimetable {
            let days = timetable.orderedDays.map { day in
                let perfs = day.stages.flatMap { stage in
                    stage.performances.map { p in
                        WidgetTimetablePerformance(
                            id: p.id,
                            artistName: p.artistName,
                            stageID: stage.id,
                            stageName: stage.name,
                            startsAt: p.startsAt,
                            endsAt: p.endsAt,
                            isInterested: p.isInterested,
                            artistImageURL: ArtistAvatarResolver.shared.displayURL(for: p)?.absoluteString
                        )
                    }
                }
                return WidgetTimetableDay(id: day.id, date: day.date, performances: perfs)
            }
            timetableSnapshot = WidgetTimetableSnapshot(days: days)
        } else {
            timetableSnapshot = nil
        }

        self.init(
            showID: show.id,
            name: show.name,
            city: show.city,
            venueName: show.venueName,
            coverImageURL: show.coverImageURL,
            timing: show.timingFields,
            generatedAt: generatedAt,
            timetable: timetableSnapshot
        )
    }
}

// MARK: - Live Activity runtime selection

struct LiveActivityRuntimeRecord: Equatable {
    let id: String
    let showID: String
    let isPending: Bool
    let state: ShowLiveActivityAttributes.ContentState
}

enum LiveActivityRuntimeSelection {
    static func pendingKeeperID(
        in records: [LiveActivityRuntimeRecord],
        showID: String?,
        state: ShowLiveActivityAttributes.ContentState
    ) -> String? {
        records.first(where: {
            $0.showID == showID && $0.isPending && $0.state == state
        })?.id
    }

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

actor ShowLiveActivityController {
    private var pushTokenTasks: [String: Task<Void, Never>] = [:]

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
        if let boundary = LiveActivityPlanner.nextRefreshDate(snapshot: snapshot, now: now) {
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
        await publish(request, focusedPerformanceID: focusedPerformanceID)
    }

    private func publish(_ request: PendingSync, focusedPerformanceID: UUID?) async {
        guard request.generation == latestGeneration else { return }
        let snapshot = request.snapshot
        let activitiesEnabled = ActivityAuthorizationInfo().areActivitiesEnabled
        let liveSource = snapshot?.coverImageURL?.trimmingCharacters(in: .whitespacesAndNewlines)
        var coverFilename: String?
        if let liveSource, !liveSource.isEmpty {
            coverFilename = WidgetCoverCache.freshLiveActivityCoverFilename(for: liveSource)
        }

        guard request.generation == latestGeneration else { return }

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
            action = LiveActivityPlanner.action(
                snapshot: snapshot,
                now: request.now,
                existing: existing,
                coverFilename: coverFilename,
                focusedPerformanceID: focusedPerformanceID,
                artistImageFilename: WidgetCoverCache.freshLiveActivityCoverFilename(for:),
                supportsScheduling: Self.supportsScheduling
            )
        } else {
            action = .endAll
        }

        guard request.generation == latestGeneration else { return }
        await perform(
            action,
            snapshot: snapshot,
            generation: request.generation
        )
    }

    private func perform(_ action: LiveActivityAction, snapshot: WidgetShowSnapshot?, generation: UInt64) async {
        func isCurrent() -> Bool { generation == latestGeneration }
        let showID = snapshot?.showID.uuidString

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
            let content = ActivityContent(state: state, staleDate: state.staleDate)
            if let target {
                await target.update(content)
                if let snapshot {
                    await LiveActivityPushCoordinator.shared.updateSnapshot(snapshot)
                }
            } else {
                guard isCurrent() else { return }
                request(attributes: ShowLiveActivityAttributes(showID: showID ?? ""), content: content, snapshot: snapshot)
            }

        case .request(let state):
            await endAll(generation: generation)
            guard isCurrent() else { return }
            let content = ActivityContent(state: state, staleDate: state.staleDate)
            request(attributes: ShowLiveActivityAttributes(showID: showID ?? ""), content: content, snapshot: snapshot)

        case .schedule(let state, let start):
            await endAll(generation: generation)
            guard isCurrent(), #available(iOS 26, *) else { return }
            let content = ActivityContent(state: state, staleDate: state.staleDate)
            do {
                let alert = AlertConfiguration(
                    title: "开场前",
                    body: LocalizedStringResource("\(state.showName) 倒计时已开始"),
                    sound: .default
                )
                let activity = try Activity<ShowLiveActivityAttributes>.request(
                    attributes: ShowLiveActivityAttributes(showID: showID ?? ""),
                    content: content,
                    pushType: .token,
                    style: .standard,
                    alertConfiguration: alert,
                    start: start
                )
                registerPushTokenUpdates(for: activity, showID: showID ?? "", snapshot: snapshot)
            } catch {
                #if DEBUG
                print("[ShowLiveActivity] schedule failed: \(error)")
                #endif
            }

        case .endNaturally(let state, let dismissDate):
            await endActivities(matching: { $0.attributes.showID != showID }, generation: generation)
            guard isCurrent() else { return }
            let matching = Activity<ShowLiveActivityAttributes>.activities.filter { $0.attributes.showID == showID }
            let content = ActivityContent(state: state, staleDate: dismissDate)
            for activity in matching {
                guard isCurrent() else { return }
                await activity.end(content, dismissalPolicy: .after(dismissDate))
            }
            if let showID {
                await LiveActivityPushCoordinator.shared.revoke(showID: showID)
            }

        case .endAll:
            await endAll(generation: generation)
        }
    }

    private func request(
        attributes: ShowLiveActivityAttributes,
        content: ActivityContent<ShowLiveActivityAttributes.ContentState>,
        snapshot: WidgetShowSnapshot?
    ) {
        do {
            let activity = try Activity<ShowLiveActivityAttributes>.request(
                attributes: attributes,
                content: content,
                pushType: .token
            )
            registerPushTokenUpdates(for: activity, showID: attributes.showID, snapshot: snapshot)
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

    private static var supportsScheduling: Bool {
        if #available(iOS 26, *) { return true }
        return false
    }

    private static func isPending(_ activity: Activity<ShowLiveActivityAttributes>) -> Bool {
        if #available(iOS 26, *) { return activity.activityState == .pending }
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

    private func registerPushTokenUpdates(
        for activity: Activity<ShowLiveActivityAttributes>,
        showID: String,
        snapshot: WidgetShowSnapshot?
    ) {
        guard let snapshot else { return }
        Task {
            await LiveActivityPushCoordinator.shared.updateSnapshot(snapshot)
        }
        pushTokenTasks[showID]?.cancel()
        pushTokenTasks[showID] = Task { [self] in
            for await tokenData in activity.pushTokenUpdates {
                guard !Task.isCancelled else { break }
                let hexToken = tokenData.map { String(format: "%02x", $0) }.joined()
                await LiveActivityPushCoordinator.shared.handleTokenUpdate(hexToken, for: showID)
            }
        }
    }
}
