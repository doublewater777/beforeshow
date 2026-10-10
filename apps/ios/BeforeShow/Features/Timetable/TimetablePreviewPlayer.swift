import Foundation
import Observation

@MainActor
@Observable
final class TimetablePreviewPlayer {
    static let shared = TimetablePreviewPlayer()

    private(set) var activePerformanceID: UUID?
    private(set) var isPlaying = false
    private(set) var isLoading = false
    private(set) var failedPerformanceID: UUID?
    private(set) var failureMessage: String?
    private(set) var activeTrackTitle: String?

    // Transient song toast for the active performance
    private(set) var toastPerformanceID: UUID?
    private(set) var toastTrackTitle: String?

    @ObservationIgnored private let playback = PreviewListeningPlaybackService()
    @ObservationIgnored private var cache: [String: ListeningPlaybackItem] = [:]
    @ObservationIgnored private var activeTask: Task<Void, Never>?
    @ObservationIgnored private var toastTask: Task<Void, Never>?

    private init() {}

    func isPlaying(performanceID: UUID) -> Bool {
        activePerformanceID == performanceID && isPlaying
    }

    func isLoading(performanceID: UUID) -> Bool {
        activePerformanceID == performanceID && isLoading
    }

    func currentTrackTitle(for performanceID: UUID) -> String? {
        if activePerformanceID == performanceID, let activeTrackTitle {
            return activeTrackTitle
        }
        return nil
    }

    func toggle(performanceID: UUID, artistName: String, artistID: String?) {
        if activePerformanceID == performanceID {
            if isLoading {
                stop()
            } else if isPlaying {
                playback.pause()
                isPlaying = false
                dismissToast()
            } else {
                activeTask?.cancel()
                isLoading = true
                if let title = activeTrackTitle {
                    showToast(for: performanceID, title: title)
                }
                activeTask = Task { await playAndMonitor(performanceID: performanceID) }
            }
            return
        }

        stop()
        activePerformanceID = performanceID
        isLoading = true
        activeTask = Task {
            do {
                guard let item = try await resolvePreview(artistName: artistName, artistID: artistID) else {
                    try Task.checkCancellation()
                    fail(performanceID: performanceID, message: "暂无试听")
                    return
                }
                try Task.checkCancellation()
                activeTrackTitle = item.title
                showToast(for: performanceID, title: item.title ?? artistName)
                try await playback.load([item], startingAt: item.songID, at: 0)
                try Task.checkCancellation()
                await playAndMonitor(performanceID: performanceID)
            } catch {
                guard !Task.isCancelled else { return }
                fail(performanceID: performanceID, message: "暂时无法播放")
            }
        }
    }

    func stop() {
        activeTask?.cancel()
        activeTask = nil
        dismissToast()
        playback.stop()
        activePerformanceID = nil
        isPlaying = false
        isLoading = false
        failedPerformanceID = nil
        failureMessage = nil
        activeTrackTitle = nil
    }

    private func showToast(for performanceID: UUID, title: String) {
        toastTask?.cancel()
        toastPerformanceID = performanceID
        toastTrackTitle = title
        toastTask = Task {
            try? await Task.sleep(for: .milliseconds(1800))
            guard !Task.isCancelled else { return }
            if self.toastPerformanceID == performanceID {
                self.toastPerformanceID = nil
                self.toastTrackTitle = nil
            }
        }
    }

    private func dismissToast() {
        toastTask?.cancel()
        toastTask = nil
        toastPerformanceID = nil
        toastTrackTitle = nil
    }

    private func playAndMonitor(performanceID: UUID) async {
        do {
            try await playback.play()
            while !Task.isCancelled {
                if playback.failure != nil {
                    fail(performanceID: performanceID, message: "暂时无法播放")
                    return
                }
                if playback.hasEnded {
                    stop()
                    return
                }
                isPlaying = playback.phase == .playing
                isLoading = playback.phase == .waiting
                try await Task.sleep(for: .milliseconds(100))
            }
        } catch {
            guard !Task.isCancelled else { return }
            fail(performanceID: performanceID, message: "暂时无法播放")
        }
    }

    private func fail(performanceID: UUID, message: String) {
        stop()
        failedPerformanceID = performanceID
        failureMessage = message
    }

    private func resolvePreview(artistName: String, artistID: String?) async throws -> ListeningPlaybackItem? {
        let name = artistName.trimmingCharacters(in: .whitespacesAndNewlines)
        let id = artistID.flatMap { $0.isEmpty ? nil : $0 }
        guard id != nil || !name.isEmpty else { return nil }
        let key = id.map { "id:\($0)" } ?? "name:\(ArtistNameMatching.normalized(name))"
        if let cached = cache[key] { return cached }

        var components = URLComponents(string: "https://itunes.apple.com/\(id == nil ? "search" : "lookup")")!
        components.queryItems = [
            URLQueryItem(name: id == nil ? "term" : "id", value: id ?? name),
            URLQueryItem(name: "entity", value: "song"),
            URLQueryItem(name: "limit", value: "25"),
            URLQueryItem(name: "country", value: "CN")
        ]
        guard let url = components.url else { return nil }
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        let decoded = try JSONDecoder().decode(TimetablePreviewSearchResponse.self, from: data)
        try Task.checkCancellation()
        let item = decoded.preview(artistName: name, artistID: id)
        if let item { cache[key] = item }
        return item
    }
}
