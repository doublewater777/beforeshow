import Foundation
import Observation

/// Plays one Apple Music preview for the artist linked to a timetable set.
@MainActor
@Observable
final class TimetablePreviewPlayback {
    private let playback = PreviewListeningPlaybackService()
    private let catalog = MusicKitListeningCatalogService()

    private(set) var isPlaying = false
    private(set) var isLoading = false
    private(set) var title: String?
    private(set) var isUnavailable = false
    private var loadedArtistID: String?

    func toggle(artistID: String) async {
        if loadedArtistID == artistID, !isLoading, title != nil {
            if isPlaying {
                playback.pause()
                isPlaying = false
            } else {
                await resume()
            }
            return
        }

        isLoading = true
        isUnavailable = false
        isPlaying = false
        title = nil
        defer { isLoading = false }

        if catalog.currentAuthorizationStatus() != .authorized {
            let status = await catalog.requestAuthorization()
            guard status == .authorized else {
                isUnavailable = true
                return
            }
        }

        do {
            let songs = try await catalog.fetchRuntimeSongs(artistID: artistID)
            guard let song = songs.first(where: { $0.previewURL?.isEmpty == false }),
                  let url = song.previewURL.flatMap(URL.init(string:)) else {
                isUnavailable = true
                return
            }
            let item = ListeningPlaybackItem(
                songID: song.songID,
                duration: song.duration,
                previewURL: url,
                title: song.title,
                artistName: song.artistName
            )
            try await playback.load([item], startingAt: song.songID, at: 0)
            try await playback.play()
            loadedArtistID = artistID
            title = song.title
            isPlaying = true
        } catch {
            isUnavailable = true
            isPlaying = false
        }
    }

    func stop() {
        playback.pause()
        isPlaying = false
    }

    private func resume() async {
        do {
            try await playback.play()
            isPlaying = true
            isUnavailable = false
        } catch {
            isUnavailable = true
            isPlaying = false
        }
    }
}
