import AVFoundation
import Foundation
import UIKit

extension DynamicCoverMediaStore {
    /// Copies a validated staged video into the show directory. Staging remains
    /// until SwiftData saves the corresponding `DynamicCover` record.
    /// Also writes a `<video>-poster.jpg` first frame next to the video; poster
    /// generation failure never blocks the import (the path stays nil).
    func commit(
        draftID: UUID,
        showID: UUID,
        video: DynamicCoverMediaStagedVideo
    ) async throws -> DynamicCoverMediaCommittedVideo {
        guard Self.isValidStagingPath(video.stagedRelativePath, draftID: draftID) else {
            throw DynamicCoverMediaStoreError.invalidRelativePath
        }
        let source = location.url(for: video.stagedRelativePath)
        guard fileManager.fileExists(atPath: source.path) else {
            throw DynamicCoverMediaStoreError.storageUnavailable
        }
        let relativePath = "\(showID.uuidString)/\(source.lastPathComponent)"
        let destination = location.url(for: relativePath)
        try prepareRootDirectory()
        try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try replaceItem(at: destination, with: source)
        let posterRelativePath = await makePosterRelativePath(
            for: destination,
            videoRelativePath: relativePath
        )
        return DynamicCoverMediaCommittedVideo(
            id: video.id,
            relativePath: relativePath,
            posterRelativePath: posterRelativePath,
            contentTypeIdentifier: video.contentTypeIdentifier,
            videoDuration: video.videoDuration
        )
    }

    /// First-frame poster for a committed video, mirroring
    /// `MemoryFragmentMediaStore.makeVideoThumbnail`. Returns nil on any failure.
    private func makePosterRelativePath(for videoURL: URL, videoRelativePath: String) async -> String? {
        let posterRelativePath = Self.posterRelativePath(forVideoRelativePath: videoRelativePath)
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: videoURL))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 1_200, height: 1_200)
        guard let result = try? await generator.image(at: .zero),
              let data = UIImage(cgImage: result.image).jpegData(compressionQuality: 0.82),
              (try? data.write(to: location.url(for: posterRelativePath), options: .atomic)) != nil else {
            return nil
        }
        return posterRelativePath
    }

    nonisolated private static func isValidStagingPath(_ path: String, draftID: UUID) -> Bool {
        let components = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        return components.count == 3
            && components[0] == "Staging"
            && components[1] == draftID.uuidString
            && !components[2].isEmpty
            && !components.contains(where: { $0 == "." || $0 == ".." })
    }
}
