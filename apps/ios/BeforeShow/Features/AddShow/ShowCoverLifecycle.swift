import Foundation

// MARK: - Show Cover Lifecycle

enum ShowCoverLocalImageStore {
    static func directory() throws -> URL {
        guard let directory = ShowCoverReference.directory else { throw CocoaError(.fileNoSuchFile) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// Saves an imported cover and returns what the show stores for it.
    static func save(_ jpegData: Data) throws -> String {
        let fileName = "\(UUID().uuidString).jpg"
        try jpegData.write(to: try directory().appendingPathComponent(fileName), options: [.atomic])
        return ShowCoverReference.stored(fileName: fileName)
    }

    static func removeManagedLocalImage(at stored: String) {
        guard let name = ShowCoverReference.localFileName(stored),
              let directory = try? directory() else { return }
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
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
