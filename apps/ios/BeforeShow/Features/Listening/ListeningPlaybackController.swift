import Foundation

@MainActor
final class ListeningPlaybackController {
    private let service: ListeningPlaybackServicing
    private let evidenceCoordinator: ListeningPlaybackEvidenceCoordinator
    private var stateMachine = ListeningPlaybackStateMachine()

    var state: ListeningPlaybackState { stateMachine.state }

    init(
        service: ListeningPlaybackServicing,
        evidenceCoordinator: ListeningPlaybackEvidenceCoordinator
    ) {
        self.service = service
        self.evidenceCoordinator = evidenceCoordinator
    }

    func prepare(
        queue: [ListeningQueueEntry],
        catalogSongs: [CatalogSong],
        source: ListeningPlaybackSource,
        startingAtSongID: String? = nil,
        now: Date = Date()
    ) async throws {
        let songsByID = Dictionary(
            catalogSongs.map { ($0.appleMusicSongID, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let items = queue.compactMap { entry -> ListeningPlaybackItem? in
            guard let song = songsByID[entry.songID] else { return nil }
            return ListeningPlaybackItem(
                songID: song.appleMusicSongID,
                duration: song.duration,
                previewURL: song.previewURL.flatMap(URL.init(string:))
            )
        }
        try await prepare(
            items: items,
            source: source,
            startingAtSongID: startingAtSongID,
            now: now
        )
    }

    func prepare(
        items: [ListeningPlaybackItem],
        source: ListeningPlaybackSource,
        startingAtSongID: String? = nil,
        now: Date = Date()
    ) async throws {
        stateMachine.handle(.prepareStarted(source: source))
        do {
            try await service.prepare(
                items: items,
                source: source,
                startingAtSongID: startingAtSongID
            )
            guard service.snapshot(observedAt: now) != nil else {
                throw ListeningPlaybackError.songUnavailable(startingAtSongID ?? items.first?.songID ?? "")
            }
            _ = try refresh(now: now)
        } catch {
            stateMachine.handle(.failed)
            throw error
        }
    }

    func play(now: Date = Date()) async throws {
        do {
            try await service.play()
            _ = try refresh(now: now)
        } catch {
            stateMachine.handle(.failed)
            throw error
        }
    }

    func pause(now: Date = Date()) throws {
        service.pause()
        _ = try refresh(now: now)
    }

    func skipToNext(now: Date = Date()) async throws {
        _ = try refresh(now: now)
        try await service.skipToNext()
        evidenceCoordinator.breakContinuity()
        _ = try refresh(now: now)
    }

    func skipToPrevious(now: Date = Date()) async throws {
        _ = try refresh(now: now)
        try await service.skipToPrevious()
        evidenceCoordinator.breakContinuity()
        _ = try refresh(now: now)
    }

    func seek(to time: TimeInterval, now: Date = Date()) throws {
        _ = try refresh(now: now)
        service.seek(to: time)
        evidenceCoordinator.breakContinuity()
    }

    @discardableResult
    func refresh(now: Date = Date()) throws -> ListeningPlaybackState {
        guard let sample = service.snapshot(observedAt: now) else {
            return state
        }
        stateMachine.handle(.sample(sample))
        _ = try evidenceCoordinator.ingest(sample, at: now)
        return state
    }

    func stop(now: Date = Date()) throws {
        _ = try refresh(now: now)
        service.stop()
        evidenceCoordinator.breakContinuity()
        stateMachine.handle(.reset)
    }
}
