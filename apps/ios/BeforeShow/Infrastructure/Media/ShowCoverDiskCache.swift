import Foundation
import UIKit

struct ShowCoverDiskCache: Sendable {
    let directoryURL: URL

    static var application: ShowCoverDiskCache {
        let cachesURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return ShowCoverDiskCache(
            directoryURL: cachesURL.appendingPathComponent("ShowCovers", isDirectory: true)
        )
    }

    func image(from sourceURL: URL) -> UIImage? {
        let fileURL = fileURL(for: sourceURL)
        return UIImage(contentsOfFile: fileURL.path)
    }

    func store(_ data: Data, for sourceURL: URL) {
        guard !sourceURL.isFileURL else { return }
        do {
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            try data.write(to: cachedFileURL(for: sourceURL), options: .atomic)
        } catch {
            #if DEBUG
            print("[ShowCoverDiskCache] store failed: \(error)")
            #endif
        }
    }

    func fileURL(for sourceURL: URL) -> URL {
        sourceURL.isFileURL ? sourceURL : cachedFileURL(for: sourceURL)
    }

    private func cachedFileURL(for sourceURL: URL) -> URL {
        directoryURL.appendingPathComponent(
            WidgetCoverCache.filename(for: sourceURL.absoluteString),
            isDirectory: false
        )
    }
}
