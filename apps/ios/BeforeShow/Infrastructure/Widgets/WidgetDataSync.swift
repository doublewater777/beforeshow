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
                WidgetListeningStore.adoptShowChange(
                    showID: currentShow?.id,
                    showName: currentShow?.name,
                    generatedAt: now
                )
                widgetReloadGeneration = generation
            }
        }

        if let listening = WidgetListeningStore.read(),
           listening.hasSession || listening.showID == currentShow?.id {
            for cover in [listening.coverImageURL, listening.nextDisc?.coverImageURL].compactMap({ $0 }) where !cover.isEmpty {
                retainedCoverSources.insert(cover)
            }
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
