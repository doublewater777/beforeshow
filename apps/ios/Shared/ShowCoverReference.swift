import Foundation

/// A show's stored cover: a web address, or a picture the user imported into the app's `ShowCovers` folder.
/// Imported covers are stored as `ShowCovers/<name>` and found in Application Support each launch, so they survive
/// the app's container moving (a restore, a new phone). Earlier versions stored the whole `file://` URL; those find
/// their file by name in today's folder.
enum ShowCoverReference {
    static let directoryName = "ShowCovers"

    static let directory: URL? = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
        .appendingPathComponent(directoryName, isDirectory: true)

    static func stored(fileName: String) -> String { "\(directoryName)/\(fileName)" }

    /// Where to load a stored cover from.
    static func url(_ stored: String?) -> URL? {
        guard let stored = stored?.trimmingCharacters(in: .whitespacesAndNewlines), !stored.isEmpty else { return nil }
        if let name = localFileName(stored) {
            return directory?.appendingPathComponent(name, isDirectory: false)
        }
        if stored.hasPrefix(directoryName + "/") { return nil }
        return URL(string: stored)
    }

    /// The file name of an imported cover, stored either way; nil for anything else.
    static func localFileName(_ stored: String) -> String? {
        let stored = stored.trimmingCharacters(in: .whitespacesAndNewlines)
        let name: String
        if stored.hasPrefix(directoryName + "/") {
            name = String(stored.dropFirst(directoryName.count + 1))
        } else if let url = URL(string: stored), url.isFileURL,
                  url.deletingLastPathComponent().lastPathComponent == directoryName,
                  url.deletingLastPathComponent().deletingLastPathComponent().lastPathComponent == "Application Support" {
            name = url.lastPathComponent
        } else {
            return nil
        }
        guard !name.isEmpty, !name.contains("/"), name != ".", name != ".." else { return nil }
        return name
    }
}
