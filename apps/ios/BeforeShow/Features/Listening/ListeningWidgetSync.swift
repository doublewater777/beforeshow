import Foundation

/// Writes the listening snapshot immediately. Cover preparation reloads the widget later.
/// Also keeps the current show's reminder discs, which 「今天这张」 follows.
@MainActor
final class ListeningWidgetSync {
    private var task: Task<Void, Never>?
    /// The disc that last played through. Until it plays again, the widget offers 「今天这张」.
    var finishedDiscID: String?
    private var reminders: (showID: UUID, discIDs: [String: String])?
    private var reminderTask: (showID: UUID, task: Task<Void, Never>)?
    private let readReminders: (UUID) async -> [String: String]

    init(readReminders: @escaping (UUID) async -> [String: String] = { await ListeningReminderDayDiscs.read(showID: $0) }) {
        self.readReminders = readReminders
    }

    func reminderDiscID(showID: UUID, on date: Date) -> String? {
        guard reminders?.showID == showID else { return nil }
        return reminders?.discIDs[ListeningDailyFeaturedDiscPolicy.dayKey(for: date)]
    }

    /// Reads the show's reminders once, or again when `force`; `onChange` runs only if they moved.
    func loadReminders(showID: UUID, force: Bool = false, onChange: @escaping @MainActor () -> Void) {
        guard force || (reminders?.showID != showID && reminderTask?.showID != showID) else { return }
        reminderTask?.task.cancel()
        let read = readReminders
        reminderTask = (showID, Task { [weak self] in
            let discIDs = await read(showID)
            guard !Task.isCancelled, let self else { return }
            let previous = self.reminders?.showID == showID ? self.reminders?.discIDs ?? [:] : [:]
            self.reminders = (showID, discIDs)
            self.reminderTask = nil
            if discIDs != previous { onChange() }
        })
    }

    func sync(_ snapshot: WidgetListeningSnapshot) {
        let previous = WidgetListeningStore.read()
        if previous == nil || !previous!.isContentEqual(to: snapshot),
           WidgetListeningStore.write(snapshot) {
            BeforeShowWidgetKind.reloadAllTimelines()
        }
        task?.cancel()
        task = Task {
            let covers = [snapshot.coverImageURL, snapshot.nextDisc?.coverImageURL]
            let sources = Set(covers.compactMap { $0 }.filter { !$0.isEmpty })
            let hadCovers = covers.map { WidgetCoverCache.cachedCoverPath(matching: $0) != nil }
            await WidgetArtworkPreparation.prepareCached(sources: sources)
            guard !Task.isCancelled else { return }
            if hadCovers != covers.map({ WidgetCoverCache.cachedCoverPath(matching: $0) != nil }) {
                BeforeShowWidgetKind.reloadAllTimelines()
            }
            await WidgetArtworkPreparation.refresh(sources: sources) { _ in
                guard !Task.isCancelled else { return }
                await MainActor.run { BeforeShowWidgetKind.reloadAllTimelines() }
            }
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        reminderTask?.task.cancel()
        reminderTask = nil
    }
}
