import Foundation

// MARK: - Show Cover Lifecycle

enum ShowCoverLocalImageStore {
    static func directory() throws -> URL {
        let baseURL = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = baseURL.appendingPathComponent("ShowCovers", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    static func removeManagedLocalImage(at urlString: String) {
        guard let url = URL(string: urlString),
              url.isFileURL,
              let managedDirectory = try? directory().standardizedFileURL,
              url.standardizedFileURL.deletingLastPathComponent() == managedDirectory else {
            return
        }
        try? FileManager.default.removeItem(at: url)
    }

}

struct ShowCoverLifecycle {
    private let remove: (String) -> Void
    private var temporaryCoverURLs: Set<String> = []

    init(remove: @escaping (String) -> Void = ShowCoverLocalImageStore.removeManagedLocalImage(at:)) {
        self.remove = remove
    }

    /// A newly imported cover replaces `previous` (if it was temp) and is tracked as temp.
    mutating func register(previous: String, new: String) {
        if temporaryCoverURLs.contains(previous) {
            remove(previous)
            temporaryCoverURLs.remove(previous)
        }
        temporaryCoverURLs.insert(new)
    }

    /// Cancel: discard every temp cover.
    mutating func cancel() {
        for urlString in temporaryCoverURLs {
            remove(urlString)
        }
        temporaryCoverURLs.removeAll()
    }

    /// Commit on save: keep `keptURL`, discard every other temp, plus any
    /// `additionalDiscards` (e.g. an original cover replaced during edit).
    mutating func finalize(keeping keptURL: String?, additionalDiscards: [String] = []) {
        for urlString in temporaryCoverURLs where urlString != keptURL {
            remove(urlString)
        }
        for urlString in additionalDiscards where urlString != keptURL {
            remove(urlString)
        }
        temporaryCoverURLs.removeAll()
    }
}
