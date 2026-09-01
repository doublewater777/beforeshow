import AVFoundation
import Foundation

enum DynamicCoverAudioTrackProbe {
    static func hasAudioTrack(at url: URL) async -> Bool {
        let asset = AVURLAsset(url: url)
        do {
            let audioTracks = try await asset.loadTracks(withMediaType: .audio)
            return !audioTracks.isEmpty
        } catch {
            return false
        }
    }
}
