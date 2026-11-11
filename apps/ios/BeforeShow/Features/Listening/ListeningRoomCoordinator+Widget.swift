import Foundation

@MainActor extension ListeningRoomCoordinator {
    /// A seated disc owns the widget, playing or paused; one that played through hands it back to 「今天这张」.
    var hasWidgetSession: Bool {
        guard let disc = loadedDisc else { return false }
        return deck.wantsPlayback || widgetSync.finishedDiscID != disc.id
    }

    func deckDidFinish() {
        if ListeningCutIn.returnSeatedDisc(afterFinishing: loadedDisc?.id, in: self) {
            syncWidgetListeningState()
            return
        }
        widgetSync.finishedDiscID = loadedDisc?.id
        advanceShuffle()
        syncWidgetListeningState()
    }

    /// 「今天这张」 for the current show on `date`'s local day.
    func todayDisc(on date: Date = Date()) -> ListeningDisc? {
        guard let show else { return nil }
        return ListeningTodayDiscPolicy.disc(
            showID: show.id,
            candidates: pickCandidates(),
            heardSongIDs: actualSongIDs,
            reminderDiscID: widgetSync.reminderDiscID(showID: show.id, on: date),
            on: date
        )
    }

    func syncWidgetListeningState(now: Date = Date()) {
        if deck.wantsPlayback { widgetSync.finishedDiscID = nil }
        if let showID = show?.id {
            widgetSync.loadReminders(showID: showID) { [weak self] in self?.syncWidgetListeningState() }
        }
        let seated = hasWidgetSession ? loadedDisc : nil
        let today = seated == nil ? todayDisc(on: now) : nil
        let calendar = Calendar.current
        let midnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))
        let tomorrow = today == nil ? nil : midnight.flatMap { todayDisc(on: $0) }
        widgetSync.sync(WidgetListeningProjection.make(.init(
            showID: show?.id,
            showName: show?.name ?? (WidgetSnapshotStore.read()?.name ?? ""),
            seatedDisc: seated,
            track: seated == nil ? nil : track,
            playerPhase: deck.phase,
            playPauseAction: playPauseAction,
            todayDisc: today,
            todayCanLoad: today.map { discPresentation(for: $0).canLoad } ?? false,
            tomorrowDisc: tomorrow.flatMap { discPresentation(for: $0).canLoad ? $0 : nil },
            tomorrowStartsAt: midnight
        )))
    }

    /// Back in the foreground or past midnight: the day may have turned and reminders may have moved.
    func refreshWidgetForDay() {
        if let showID = show?.id {
            widgetSync.loadReminders(showID: showID, force: true) { [weak self] in self?.syncWidgetListeningState() }
        }
        syncWidgetListeningState()
    }
}
