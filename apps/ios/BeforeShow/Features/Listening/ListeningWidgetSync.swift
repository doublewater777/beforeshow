import Foundation

/// Writes the listening snapshot immediately. Cover preparation reloads the widget later.
@MainActor
final class ListeningWidgetSync {
    private var task: Task<Void, Never>?

    func sync(_ snapshot: WidgetListeningSnapshot) {
        let previous = WidgetListeningStore.read()
        if previous == nil || !previous!.isContentEqual(to: snapshot),
           WidgetListeningStore.write(snapshot) {
            BeforeShowWidgetKind.reloadAllTimelines()
        }
        task?.cancel()
        task = Task {
            let source = snapshot.coverImageURL
            let sources = Set([source].compactMap { $0 }.filter { !$0.isEmpty })
            let hadCover = WidgetCoverCache.cachedCoverPath(matching: source) != nil
            await WidgetArtworkPreparation.prepareCached(sources: sources)
            guard !Task.isCancelled else { return }
            if !hadCover && WidgetCoverCache.cachedCoverPath(matching: source) != nil {
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
    }
}
