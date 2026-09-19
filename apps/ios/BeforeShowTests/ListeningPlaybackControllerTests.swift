import AVFoundation
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

    func testEvidenceChangeCallbackRunsAfterPersistenceAndFinalPauseStateIsPublished() async throws {
        let container = try ModelContainerFactory.make(isStoredInMemoryOnly: true)
        defer { withExtendedLifetime(container) {} }
        let context = container.mainContext
        let service = PlaybackServiceStub()
        var projectedStates: [ListeningPlaybackState] = []
        var evidenceCallbackSawPersistedRecord = false
        let controller = ListeningPlaybackController(
            service: service,
            evidenceCoordinator: try ListeningPlaybackEvidenceCoordinator(modelContext: context),
            stateDidChange: { projectedStates.append($0) },
            evidenceDidChange: {
                evidenceCallbackSawPersistedRecord = (try? context.fetch(FetchDescriptor<SongFamiliarityRecord>())
                    .contains { $0.songID == "threshold-song" && $0.actualListeningAt != nil }) == true
            }
        )
        let item = ListeningPlaybackItem(songID: "threshold-song", duration: 4, previewURL: nil)

        try await controller.prepare(items: [item], source: .fullCatalog, now: time(0))
        try await service.play()
        _ = try controller.refresh(now: time(0))
        service.currentTime = 1.4
        _ = try controller.refresh(now: time(1))
        XCTAssertFalse(evidenceCallbackSawPersistedRecord)

        service.currentTime = 2.1
        try controller.pause(now: time(2))

        XCTAssertEqual(
            controller.state,
            .paused(songID: "threshold-song", source: .fullCatalog, currentTime: 2.1, duration: 4)
        )
        XCTAssertEqual(projectedStates.last, controller.state)
        XCTAssertTrue(evidenceCallbackSawPersistedRecord)
        let record = try XCTUnwrap(context.fetch(FetchDescriptor<SongFamiliarityRecord>())
            .first { $0.songID == "threshold-song" })
        XCTAssertNotNil(record.actualListeningAt)
    }

    func testEvidencePersistenceFailureKeepsTransportPublishedAndRetries() async throws {
        let container = try ModelContainerFactory.make(isStoredInMemoryOnly: true)
        defer { withExtendedLifetime(container) {} }
        let context = container.mainContext
        let service = PlaybackServiceStub()
        var shouldFail = true
        var evidenceFailureCount = 0
        var evidenceChangeCount = 0
        var projectedStates: [ListeningPlaybackState] = []
        let evidence = try ListeningPlaybackEvidenceCoordinator(
            modelContext: context,
            persistActualFamiliarity: { songID, date in
                _ = try ListeningRepository(modelContext: context)
                    .confirmActualFamiliarity(songID: songID, at: date)
                if shouldFail {
                    shouldFail = false
                    throw ControllerEvidencePersistenceTestError.expectedFailure
                }
                try context.save()
            }
        )
        let controller = ListeningPlaybackController(
            service: service,
            evidenceCoordinator: evidence,
            stateDidChange: { projectedStates.append($0) },
            evidenceDidChange: { evidenceChangeCount += 1 },
            evidenceDidFail: { evidenceFailureCount += 1 }
        )
        let item = ListeningPlaybackItem(songID: "retry-song", duration: 4, previewURL: nil)

        try await controller.prepare(items: [item], source: .fullCatalog, now: time(0))
        try await service.play()
        _ = try controller.refresh(now: time(0))
        service.currentTime = 1.4
        _ = try controller.refresh(now: time(1))
        service.currentTime = 2.1
        _ = try controller.refresh(now: time(2))

        XCTAssertEqual(
            controller.state,
            .playing(songID: "retry-song", source: .fullCatalog, currentTime: 2.1, duration: 4)
        )
        XCTAssertEqual(projectedStates.last, controller.state)
        XCTAssertEqual(evidenceFailureCount, 1)
        XCTAssertEqual(evidenceChangeCount, 0)
        XCTAssertTrue(try context.fetch(FetchDescriptor<SongFamiliarityRecord>()).isEmpty)

        _ = try controller.refresh(now: time(3))

        XCTAssertEqual(
            controller.state,
            .playing(songID: "retry-song", source: .fullCatalog, currentTime: 2.1, duration: 4)
        )
        XCTAssertEqual(evidenceFailureCount, 1)
        XCTAssertEqual(evidenceChangeCount, 1)
        let record = try XCTUnwrap(
            context.fetch(FetchDescriptor<SongFamiliarityRecord>())
                .first { $0.songID == "retry-song" }
        )
        XCTAssertNotNil(record.actualListeningAt)
    }

    func testPendingEvidenceFailureDoesNotBlockNextTrackAccumulation() async throws {
        let container = try ModelContainerFactory.make(isStoredInMemoryOnly: true)
        defer { withExtendedLifetime(container) {} }
        let context = container.mainContext
        let service = PlaybackServiceStub()
        var persistenceAvailable = false
        var evidenceFailureCount = 0
        var evidenceChangeCount = 0
        let evidence = try ListeningPlaybackEvidenceCoordinator(
            modelContext: context,
            persistActualFamiliarity: { songID, date in
                _ = try ListeningRepository(modelContext: context)
                    .confirmActualFamiliarity(songID: songID, at: date)
                guard persistenceAvailable else {
                    throw ControllerEvidencePersistenceTestError.expectedFailure
                }
                try context.save()
            }
        )
        let controller = ListeningPlaybackController(
            service: service,
            evidenceCoordinator: evidence,
            evidenceDidChange: { evidenceChangeCount += 1 },
            evidenceDidFail: { evidenceFailureCount += 1 }
        )
        let items = [
            ListeningPlaybackItem(songID: "song-a", duration: 100, previewURL: nil),
            ListeningPlaybackItem(songID: "song-b", duration: 100, previewURL: nil)
        ]

        try await controller.prepare(
            items: items,
            source: .fullCatalog,
            startingAtSongID: "song-a",
            now: time(0)
        )
        try await service.play()
        _ = try controller.refresh(now: time(0))

        service.currentTime = 51
        _ = try controller.refresh(now: time(51))
        XCTAssertEqual(evidenceFailureCount, 1)

        try service.selectSongForTesting("song-b")
        _ = try controller.refresh(now: time(52))
        service.currentTime = 51
        _ = try controller.refresh(now: time(103))

        XCTAssertEqual(
            controller.state,
            .playing(songID: "song-b", source: .fullCatalog, currentTime: 51, duration: 100)
        )
        XCTAssertEqual(evidenceFailureCount, 3)
        XCTAssertEqual(evidenceChangeCount, 0)
        XCTAssertTrue(try context.fetch(FetchDescriptor<SongFamiliarityRecord>()).isEmpty)

        persistenceAvailable = true
        _ = try controller.refresh(now: time(104))

        XCTAssertEqual(
            controller.state,
            .playing(songID: "song-b", source: .fullCatalog, currentTime: 51, duration: 100)
        )
        XCTAssertEqual(evidenceChangeCount, 1)
        let records = try context.fetch(FetchDescriptor<SongFamiliarityRecord>())
        XCTAssertEqual(
            Set(records.compactMap { $0.actualListeningAt == nil ? nil : $0.songID }),
            ["song-a", "song-b"]
        )
    }

    func testStopDrainsAllPendingEvidenceInSingleFinalRefresh() async throws {
        let container = try ModelContainerFactory.make(isStoredInMemoryOnly: true)
        defer { withExtendedLifetime(container) {} }
        let context = container.mainContext
        let service = PlaybackServiceStub()
        var persistenceAvailable = false
        var evidenceChangeCount = 0
        let evidence = try ListeningPlaybackEvidenceCoordinator(
            modelContext: context,
            persistActualFamiliarity: { songID, date in
                _ = try ListeningRepository(modelContext: context)
                    .confirmActualFamiliarity(songID: songID, at: date)
                guard persistenceAvailable else {
                    throw ControllerEvidencePersistenceTestError.expectedFailure
                }
                try context.save()
            }
        )
        var controller: ListeningPlaybackController? = ListeningPlaybackController(
            service: service,
            evidenceCoordinator: evidence,
            evidenceDidChange: { evidenceChangeCount += 1 }
        )
        let items = [
            ListeningPlaybackItem(songID: "song-a", duration: 100, previewURL: nil),
            ListeningPlaybackItem(songID: "song-b", duration: 100, previewURL: nil)
        ]

        try await controller?.prepare(
            items: items,
            source: .fullCatalog,
            startingAtSongID: "song-a",
            now: time(0)
        )
        try await service.play()
        _ = try controller?.refresh(now: time(0))
        service.currentTime = 51
        _ = try controller?.refresh(now: time(51))

        try service.selectSongForTesting("song-b")
        _ = try controller?.refresh(now: time(52))
        service.currentTime = 51
        _ = try controller?.refresh(now: time(103))
        XCTAssertTrue(try context.fetch(FetchDescriptor<SongFamiliarityRecord>()).isEmpty)

        persistenceAvailable = true
        try controller?.stop(now: time(104))
        controller = nil

        XCTAssertEqual(evidenceChangeCount, 1)
        XCTAssertTrue(service.didStop)
        let records = try context.fetch(FetchDescriptor<SongFamiliarityRecord>())
        XCTAssertEqual(
            Set(records.compactMap { $0.actualListeningAt == nil ? nil : $0.songID }),
            ["song-a", "song-b"]
        )
    }

    func testPreparePreservesWholeQueueAndStartingTrack() async throws {
        let container = try ModelContainerFactory.make(isStoredInMemoryOnly: true)
        defer { withExtendedLifetime(container) {} }
        let service = PlaybackServiceStub()
        let controller = ListeningPlaybackController(
            service: service,
            evidenceCoordinator: try ListeningPlaybackEvidenceCoordinator(modelContext: container.mainContext)
        )
        let items = [
            ListeningPlaybackItem(songID: "song-a", duration: 100, previewURL: nil),
            ListeningPlaybackItem(songID: "song-b", duration: 120, previewURL: nil),
            ListeningPlaybackItem(songID: "song-c", duration: 90, previewURL: nil)
        ]

        try await controller.prepare(
            items: items,
            source: .fullCatalog,
            startingAtSongID: "song-b",
            now: time(0)
        )

        XCTAssertEqual(service.preparedItems, items)
        XCTAssertEqual(service.preparedStartingSongID, "song-b")
        XCTAssertEqual(
            controller.state,
            .ready(songID: "song-b", source: .fullCatalog, currentTime: 0, duration: 120)
        )
    }

    func testVisibilityNeverOwnsListeningTransport() {
        XCTAssertFalse(
            ListeningVisibilityPolicy.mustPause(
                tabVisible: false,
                foreground: true,
                source: .fullCatalog
            )
        )
        XCTAssertFalse(
            ListeningVisibilityPolicy.mustPause(
                tabVisible: true,
                foreground: false,
                source: .fullCatalog
            )
        )
        XCTAssertFalse(
            ListeningVisibilityPolicy.mustPause(
                tabVisible: false,
                foreground: false,
                source: .preview
            )
        )
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
        XCTAssertEqual(try controller.refresh(), .failed)
        XCTAssertEqual(controller.state, .failed)
        XCTAssertNoThrow(try controller.stop())
        XCTAssertTrue(service.didStop)
        XCTAssertEqual(controller.state, .idle)
    }

    func testRemoteCommandPlayRestartsFinishedPreviewQueue() async throws {
        let container = try ModelContainerFactory.make(isStoredInMemoryOnly: true)
        defer { withExtendedLifetime(container) {} }
        let player = AVQueuePlayer()
        let service = PreviewListeningPlaybackService(player: player)
        let controller = ListeningPlaybackController(
            service: service,
            evidenceCoordinator: try ListeningPlaybackEvidenceCoordinator(modelContext: container.mainContext)
        )
        let items = [
            ListeningPlaybackItem(
                songID: "song-1",
                duration: 30,
                previewURL: URL(string: "https://example.com/1.m4a"),
                title: "Track 1",
                artistName: "Artist"
            ),
            ListeningPlaybackItem(
                songID: "song-2",
                duration: 30,
                previewURL: URL(string: "https://example.com/2.m4a"),
                title: "Track 2",
                artistName: "Artist"
            )
        ]

        try await controller.prepare(items: items, source: .preview, startingAtSongID: "song-2")
        try await controller.play()

        // Simulate natural queue completion by clearing player items
        player.removeAllItems()
        _ = try controller.refresh()
        XCTAssertEqual(
            controller.state,
            .finished(songID: "song-2", source: .preview, duration: 30)
        )

        // Invoke lock-screen / Control Center remote play
        try await ListeningRemoteCommandBridge.shared.playForTesting()
        XCTAssertEqual(
            controller.state,
            .playing(songID: "song-2", source: .preview, currentTime: 0, duration: 30)
        )
        XCTAssertNotNil(player.currentItem)

        try controller.stop()
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
    private(set) var preparedStartingSongID: String?
    var currentTime: TimeInterval = 0
    private var isPlaying = false

    func prepare(
        items: [ListeningPlaybackItem],
        source: ListeningPlaybackSource,
        startingAtSongID: String?
    ) async throws {
        preparedItems = items
        preparedStartingSongID = startingAtSongID
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

    func selectSongForTesting(_ songID: String) throws {
        guard let selected = preparedItems.first(where: { $0.songID == songID }) else {
            throw ListeningPlaybackError.songUnavailable(songID)
        }
        item = selected
        currentTime = 0
    }

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

private enum ControllerEvidencePersistenceTestError: Error {
    case expectedFailure
}
