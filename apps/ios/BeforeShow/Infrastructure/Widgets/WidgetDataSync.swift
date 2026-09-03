import ActivityKit
import Foundation
import WidgetKit

// MARK: - Widget / Live Activity Sync
// Widget follows the durable user-owned Current Show. Live Activity independently
// follows an actually live or nearest upcoming show. Both surfaces share the cover
// cache, so pruning keeps the union of their sources.

enum WidgetDataSync {
    static let widgetKind = BeforeShowWidgetKind.homeCountdown
    static let lockScreenWidgetKind = BeforeShowWidgetKind.lockScreenCountdown

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
        let currentShow = session.selectCurrentShow(
            from: shows,
            manualSelection: manualSelection,
            now: now
        )
        let liveActivityShow = LiveActivityShowResolver().resolve(
            shows: shows,
            currentShow: currentShow,
            now: now
        )

        let widgetSnapshot = currentShow.map { WidgetShowSnapshot(show: $0, generatedAt: now) }
        let liveActivitySnapshot = liveActivityShow.map { WidgetShowSnapshot(show: $0, generatedAt: now) }
        let retainedCoverSources = Set(
            [widgetSnapshot?.coverImageURL, liveActivitySnapshot?.coverImageURL]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        )

        let previous = WidgetSnapshotStore.read()
        var didStoreSnapshot = true
        if contentChanged(from: previous, to: widgetSnapshot) {
            didStoreSnapshot = WidgetSnapshotStore.write(widgetSnapshot)
            if didStoreSnapshot {
                BeforeShowWidgetKind.reloadAllTimelines()
            }
        }

        // SwiftData Show is not Sendable; only immutable value snapshots cross actors.
        Task {
            await ShowLiveActivityController.shared.sync(
                snapshot: liveActivitySnapshot,
                widgetCoverSource: widgetSnapshot?.coverImageURL,
                retainedCoverSources: retainedCoverSources,
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
        case (nil, nil): return false
        case (nil, .some), (.some, nil): return true
        case let (a?, b?): return !a.isContentEqual(to: b)
        }
    }
}

/// Live Activity is a time-sensitive surface, not another representation of Current Show.
struct LiveActivityShowResolver {
    let calendar: Calendar

    init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    func resolve(
        shows: [Show],
        currentShow: Show?,
        now: Date = Date()
    ) -> Show? {
        let eligible = shows.filter { show in
            guard show.wasAddedAsHistorical != true,
                  show.changeStatus != .canceled,
                  show.endedAt == nil else {
                return false
            }
            if show.changeStatus == .postponed, show.postponedDate == nil {
                return false
            }
            return true
        }

        if let currentShow,
           eligible.contains(where: { $0.id == currentShow.id }),
           isActuallyLive(currentShow, now: now) {
            return currentShow
        }

        let live = eligible
            .filter { isActuallyLive($0, now: now) }
            .sorted { lhs, rhs in
                let lhsStart = startTime(for: lhs, now: now) ?? .distantPast
                let rhsStart = startTime(for: rhs, now: now) ?? .distantPast
                if lhsStart != rhsStart { return lhsStart > rhsStart }
                return lhs.id.uuidString < rhs.id.uuidString
            }
        if let show = live.first {
            return show
        }

        return eligible
            .compactMap { show -> (Show, Date)? in
                guard let start = startTime(for: show, now: now), start > now else { return nil }
                return (show, start)
            }
            .sorted { lhs, rhs in
                if lhs.1 != rhs.1 { return lhs.1 < rhs.1 }
                return lhs.0.id.uuidString < rhs.0.id.uuidString
            }
            .first?
            .0
    }

    private func startTime(for show: Show, now: Date) -> Date? {
        CurrentShowTimeState(show: show, calendar: calendar, now: now).effectiveStartTime
    }

    private func isActuallyLive(_ show: Show, now: Date) -> Bool {
        let state = CurrentShowTimeState(show: show, calendar: calendar, now: now)
        guard state.kind == .today,
              let start = state.effectiveStartTime,
              let end = state.endBoundary else {
            return false
        }
        return now >= start && now < end
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
    static let shared = ShowLiveActivityController()

    private struct PendingSync {
        let snapshot: WidgetShowSnapshot?
        let widgetCoverSource: String?
        let retainedCoverSources: Set<String>
        let now: Date
        let generation: UInt64
    }

    private init() {}

    private var latestGeneration: UInt64 = 0
    private var pendingSync: PendingSync?
    private var isProcessing = false

    func sync(
        snapshot: WidgetShowSnapshot?,
        widgetCoverSource: String?,
        retainedCoverSources: Set<String>,
        now: Date,
        generation: UInt64
    ) async {
        latestGeneration = max(latestGeneration, generation)
        guard generation == latestGeneration else { return }

        pendingSync = PendingSync(
            snapshot: snapshot,
            widgetCoverSource: widgetCoverSource,
            retainedCoverSources: retainedCoverSources,
            now: now,
            generation: generation
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
        let activitiesEnabled = ActivityAuthorizationInfo().areActivitiesEnabled
        let desired = LiveActivityPlanner.desiredState(
            snapshot: snapshot,
            now: now,
            coverFilename: nil
        )

        let normalizedWidgetSource = request.widgetCoverSource?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let liveSource = snapshot?.coverImageURL?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let hadWidgetCover = WidgetCoverCache.cachedCoverPath(matching: normalizedWidgetSource) != nil

        for source in request.retainedCoverSources.sorted() {
            await WidgetCoverCache.refresh(for: source)
            guard request.generation == latestGeneration else { return }
        }
        WidgetCoverCache.pruneCovers(keeping: request.retainedCoverSources)

        let hasWidgetCover = WidgetCoverCache.cachedCoverPath(matching: normalizedWidgetSource) != nil
        if !hadWidgetCover, hasWidgetCover {
            await MainActor.run {
                BeforeShowWidgetKind.reloadAllTimelines()
            }
        }

        var coverFilename: String?
        if desired != nil, let liveSource, !liveSource.isEmpty {
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
            let content = ActivityContent(state: state, staleDate: staleDate(for: state))
            if let target {
                await target.update(content)
            } else {
                guard isCurrent() else { return }
                request(attributes: ShowLiveActivityAttributes(showID: showID ?? ""), content: content)
            }

        case .request(let state):
            await endAll(generation: generation)
            guard isCurrent() else { return }
            let content = ActivityContent(state: state, staleDate: staleDate(for: state))
            request(attributes: ShowLiveActivityAttributes(showID: showID ?? ""), content: content)

        case .schedule(let state, let start):
            await endAll(generation: generation)
            guard isCurrent() else { return }
            let content = ActivityContent(state: state, staleDate: staleDate(for: state))
            if #available(iOS 26.0, *) {
                do {
                    let alert = AlertConfiguration(
                        title: "开场前",
                        body: LocalizedStringResource("\(state.showName) 倒计时已开始"),
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

    private func staleDate(for state: ShowLiveActivityAttributes.ContentState) -> Date? {
        state.startDate > Date() ? state.startDate : state.endDate
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
}
