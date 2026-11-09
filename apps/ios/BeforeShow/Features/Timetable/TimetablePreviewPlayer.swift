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
    private(set) var toastIsError: Bool = false

    @ObservationIgnored private let playback = PreviewListeningPlaybackService(owner: .timetablePreview)
    @ObservationIgnored private var cache: [String: ListeningPlaybackItem] = [:]
    @ObservationIgnored private var activeTask: Task<Void, Never>?
    @ObservationIgnored private var toastTask: Task<Void, Never>?
    @ObservationIgnored private var interruptedListening: InterruptedListening?
    @ObservationIgnored private var focusObserver: NSObjectProtocol?

    private init() {
        focusObserver = AppAudioSession.observeFocusLoss(of: .timetablePreview) { [weak self] in
            // Another in-app source won focus: do not resurrect the old session.
            self?.interruptedListening = nil
        }
    }

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

        stop(resumeListening: false)
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

    func stop(resumeListening: Bool = true) {
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
        if resumeListening {
            restoreInterruptedListening()
        }
    }

    private func rememberInterruptedListening() {
        if interruptedListening == nil { interruptedListening = InterruptedListening.capture() }
    }

    private func restoreInterruptedListening() {
        defer { interruptedListening = nil }
        interruptedListening?.resume()
    }

    private func showToast(for performanceID: UUID, title: String, isError: Bool = false) {
        toastTask?.cancel()
        toastPerformanceID = performanceID
        toastTrackTitle = title
        toastIsError = isError
        toastTask = Task {
            try? await Task.sleep(for: .milliseconds(isError ? 2200 : 1800))
            guard !Task.isCancelled else { return }
            if self.toastPerformanceID == performanceID {
                self.toastPerformanceID = nil
                self.toastTrackTitle = nil
                self.toastIsError = false
            }
        }
    }

    private func dismissToast() {
        toastTask?.cancel()
        toastTask = nil
        toastPerformanceID = nil
        toastTrackTitle = nil
        toastIsError = false
    }

    private func playAndMonitor(performanceID: UUID) async {
        do {
            rememberInterruptedListening()
            try await playback.play()
            let changes = BSObservationValues { [playback] in
                (phase: playback.phase, failed: playback.failure != nil, ended: playback.hasEnded)
            }
            for await state in changes {
                guard !Task.isCancelled else { return }
                if state.failed {
                    fail(performanceID: performanceID, message: "暂时无法播放")
                    return
                }
                if state.ended {
                    stop()
                    return
                }
                isPlaying = state.phase == .playing
                isLoading = state.phase == .waiting
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
        showToast(for: performanceID, title: message, isError: true)
    }

    private func resolvePreview(artistName: String, artistID: String?) async throws -> ListeningPlaybackItem? {
        let name = artistName.trimmingCharacters(in: .whitespacesAndNewlines)
        let id = artistID.flatMap { $0.isEmpty ? nil : $0 }
        guard id != nil || !name.isEmpty else { return nil }
        let key = id.map { "id:\($0)" } ?? "name:\(ArtistNameMatching.normalized(name))"
        if let cached = cache[key] { return cached }

        let country = await AppleMusicArtistSearchService.currentFallbackCountry(preferred: nil)
        var components = URLComponents(string: "https://itunes.apple.com/\(id == nil ? "search" : "lookup")")!
        components.queryItems = [
            URLQueryItem(name: id == nil ? "term" : "id", value: id ?? name),
            URLQueryItem(name: "entity", value: "song"),
            URLQueryItem(name: "limit", value: "25"),
            URLQueryItem(name: "country", value: country)
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

