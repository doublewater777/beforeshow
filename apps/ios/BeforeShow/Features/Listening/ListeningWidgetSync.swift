import Foundation

/// Publishes listening state after preparing any artwork the app already has.
@MainActor
final class ListeningWidgetSync {
    private var task: Task<Void, Never>?
    private var needsReload = false

    func sync(_ snapshot: WidgetListeningSnapshot) {
        let previous = WidgetListeningStore.read()
        if previous == nil || !previous!.isContentEqual(to: snapshot) {
            needsReload = WidgetListeningStore.write(snapshot) || needsReload
        }
        task?.cancel()
        task = Task {
            let source = snapshot.coverImageURL
            let sources = Set([source].compactMap { $0 }.filter { !$0.isEmpty })
            let hadCover = WidgetCoverCache.cachedCoverPath(matching: source) != nil
            await WidgetArtworkPreparation.prepareCached(sources: sources)
            guard !Task.isCancelled else { return }
            if needsReload || (!hadCover && WidgetCoverCache.cachedCoverPath(matching: source) != nil) {
                needsReload = false
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
