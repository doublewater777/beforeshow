import SwiftData
import XCTest
@testable import BeforeShow

@MainActor
final class ListeningPlaybackControllerTests: XCTestCase {
    func testControllerDrivesStateAndPersistsFullPlaybackEvidence() async throws {
        let container = try ModelContainerFactory.make(isStoredInMemoryOnly: true)
        defer { withExtendedLifetime(container) {} }
        let context = container.mainContext
        let service = PlaybackServiceStub()
        let controller = ListeningPlaybackController(
            service: service,
            evidenceCoordinator: try ListeningPlaybackEvidenceCoordinator(modelContext: context)
        )
        let item = ListeningPlaybackItem(songID: "song-a", duration: 100, previewURL: nil)

        try await controller.prepare(items: [item], source: .fullCatalog, now: time(0))
        XCTAssertEqual(
            controller.state,
            .ready(songID: "song-a", source: .fullCatalog, currentTime: 0, duration: 100)
        )

        try await controller.play(now: time(0))
        service.currentTime = 51
        _ = try controller.refresh(now: time(51))

        XCTAssertEqual(
            controller.state,
            .playing(songID: "song-a", source: .fullCatalog, currentTime: 51, duration: 100)
        )
        let record = try XCTUnwrap(context.fetch(FetchDescriptor<SongFamiliarityRecord>()).first)
        XCTAssertEqual(record.actualListeningAt, time(51))
    }

    func testControllerPreviewPlaybackNeverPersistsActualEvidence() async throws {
        let container = try ModelContainerFactory.make(isStoredInMemoryOnly: true)
        defer { withExtendedLifetime(container) {} }
        let context = container.mainContext
        let service = PlaybackServiceStub()
        let controller = ListeningPlaybackController(
            service: service,
            evidenceCoordinator: try ListeningPlaybackEvidenceCoordinator(modelContext: context)
        )
        let item = ListeningPlaybackItem(
            songID: "song-a",
            duration: 30,
            previewURL: URL(string: "https://example.com/preview.m4a")
        )

        try await controller.prepare(items: [item], source: .preview, now: time(0))
        try await controller.play(now: time(0))
        service.currentTime = 30
        _ = try controller.refresh(now: time(30))

        XCTAssertTrue(try context.fetch(FetchDescriptor<SongFamiliarityRecord>()).isEmpty)
    }

    func testSeekCapturesPlayedTimeThenBreaksContinuity() async throws {
        let container = try ModelContainerFactory.make(isStoredInMemoryOnly: true)
        defer { withExtendedLifetime(container) {} }
        let context = container.mainContext
        let service = PlaybackServiceStub()
        let controller = ListeningPlaybackController(
            service: service,
            evidenceCoordinator: try ListeningPlaybackEvidenceCoordinator(modelContext: context)
        )
        let item = ListeningPlaybackItem(songID: "song-a", duration: 100, previewURL: nil)

        try await controller.prepare(items: [item], source: .fullCatalog, now: time(0))
        try await controller.play(now: time(0))
        service.currentTime = 49
        try controller.seek(to: 90, now: time(49))
        service.currentTime = 91
        _ = try controller.refresh(now: time(50))

        XCTAssertTrue(try context.fetch(FetchDescriptor<SongFamiliarityRecord>()).isEmpty)
        service.currentTime = 92
        _ = try controller.refresh(now: time(51))
        XCTAssertTrue(try context.fetch(FetchDescriptor<SongFamiliarityRecord>()).isEmpty)
        service.currentTime = 93
        _ = try controller.refresh(now: time(52))
        XCTAssertEqual(try context.fetch(FetchDescriptor<SongFamiliarityRecord>()).count, 1)
    }

    func testFailedResourceStillStopsTransport() async throws {
        let container = try ModelContainerFactory.make(isStoredInMemoryOnly: true)
        defer { withExtendedLifetime(container) {} }
        let service = PlaybackServiceStub()
        let controller = ListeningPlaybackController(service: service,
            evidenceCoordinator: try ListeningPlaybackEvidenceCoordinator(modelContext: container.mainContext))
        try await controller.prepare(items: [ListeningPlaybackItem(songID: "failed", duration: 100, previewURL: nil)], source: .fullCatalog)
        try await controller.play()
        service.failure = .songUnavailable("failed")
        XCTAssertThrowsError(try controller.refresh())
        XCTAssertEqual(controller.state, .failed)
        XCTAssertThrowsError(try controller.stop())
        XCTAssertTrue(service.didStop)
        XCTAssertEqual(controller.state, .idle)
    }

    private func time(_ value: TimeInterval) -> Date {
        Date(timeIntervalSince1970: value)
    }
}

@MainActor
private final class PlaybackServiceStub: ListeningPlaybackServicing {
    var failure: ListeningPlaybackError?
    var didStop = false
    private var item: ListeningPlaybackItem?
    private var source: ListeningPlaybackSource = .fullCatalog
    private(set) var preparedItems: [ListeningPlaybackItem] = []
    var currentTime: TimeInterval = 0
    private var isPlaying = false

    func prepare(
        items: [ListeningPlaybackItem],
        source: ListeningPlaybackSource,
        startingAtSongID: String?
    ) async throws {
        preparedItems = items
        guard let selected = items.first(where: { $0.songID == startingAtSongID }) ?? items.first else {
            throw ListeningPlaybackError.emptyQueue
        }
        item = selected
        self.source = source
        currentTime = 0
        isPlaying = false
    }

    func play() async throws { isPlaying = true }
    func pause() { isPlaying = false }
    func skipToNext() async throws { throw ListeningPlaybackError.queueBoundary }
    func skipToPrevious() async throws { throw ListeningPlaybackError.queueBoundary }
    func seek(to time: TimeInterval) { currentTime = time }

    func snapshot(observedAt: Date) -> ListeningPlaybackSample? {
        guard let item else { return nil }
        return ListeningPlaybackSample(
            songID: item.songID,
            source: source,
            currentTime: currentTime,
            duration: item.duration,
            isPlaying: isPlaying,
            observedAt: observedAt
        )
    }

    func stop() {
        didStop = true
        item = nil
        isPlaying = false
    }
}
