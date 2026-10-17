import Foundation

/// Bridges the app's original-image cache to WidgetKit and ActivityKit small images.
enum WidgetArtworkPreparation {
    static func prepareCached(sources: Set<String>) async {
        for source in sources {
            guard !Task.isCancelled else { return }
            guard !isReady(source), let url = URL(string: source) else { continue }
            let file = ShowCoverDiskCache.application.fileURL(for: url)
            let data = await Task.detached(priority: .userInitiated) {
                try? Data(contentsOf: file)
            }.value
            guard !Task.isCancelled else { return }
            if let data { await WidgetCoverCache.store(data, for: source) }
        }
    }

    static func refresh(
        sources: Set<String>,
        onReady: @Sendable (String) async -> Void
    ) async {
        await withTaskGroup(of: String?.self) { group in
            for source in sources where !isReady(source) {
                group.addTask {
                    guard !Task.isCancelled else { return nil }
                    await WidgetCoverCache.refresh(for: source)
                    return !Task.isCancelled && isReady(source) ? source : nil
                }
            }
            for await source in group {
                guard !Task.isCancelled else { group.cancelAll(); return }
                if let source { await onReady(source) }
            }
        }
    }

    private static func isReady(_ source: String) -> Bool {
        WidgetCoverCache.freshCoverFilename(for: source) != nil
            && WidgetCoverCache.freshLiveActivityCoverFilename(for: source) != nil
    }
}
