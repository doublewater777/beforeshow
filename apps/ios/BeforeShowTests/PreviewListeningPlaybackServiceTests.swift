import AVFoundation
import MediaPlayer
import UIKit
import XCTest
@testable import BeforeShow

@MainActor
final class PreviewListeningPlaybackServiceTests: XCTestCase {
    private var url: URL!
    private var player: AVQueuePlayer!
    private var service: PreviewListeningPlaybackService!

    override func setUp() async throws {
        try await super.setUp()
        AppAudioSession.resetForTests()
        await AppAudioSession.waitForPendingOperations()
        url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".caf")
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 8_000, channels: 1))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 160_000))
        buffer.frameLength = buffer.frameCapacity
        buffer.floatChannelData?[0].initialize(repeating: 0, count: Int(buffer.frameLength))
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buffer)
        player = AVQueuePlayer()
        service = PreviewListeningPlaybackService(player: player)
    }

    override func tearDown() async throws {
        service.stop()
        service = nil
        player = nil
        try? FileManager.default.removeItem(at: url)
        AppAudioSession.resetForTests()
        await AppAudioSession.waitForPendingOperations()
        try await super.tearDown()
    }

    func testResumableInterruptionContinuesPreviewFromItsPosition() async throws {
        try await start()
        try await waitUntil { self.service.currentTime > 0.1 }
        let interruptedAt = service.currentTime
        let interruptedItem = player.currentItem
        beginInterruption()
        XCTAssertEqual(service.phase, .interrupted)

        endInterruption(shouldResume: true)

        try await waitUntil { self.service.phase == .playing }
        XCTAssertTrue(player.currentItem === interruptedItem)
        XCTAssertGreaterThanOrEqual(service.currentTime, interruptedAt - 0.01)
        try await waitUntil { self.service.currentTime > interruptedAt + 0.1 }
        XCTAssertEqual(service.currentSongID, "first")
    }

    func testResumeRequiresSystemPermissionAndNoUserPause() async throws {
        for scenario in ["system-denied", "paused-before", "paused-during", "paused-after"] {
            try await start()
            if scenario == "paused-before" { service.pause() }
            beginInterruption()
            if scenario == "paused-during" { service.pause() }

            endInterruption(shouldResume: scenario != "system-denied")
            if scenario == "paused-after" { service.pause() }
            await drainPlaybackRequests()

            XCTAssertEqual(player.rate, 0, scenario)
            XCTAssertEqual(service.phase, .paused, scenario)
        }
    }

    func testHeadphoneDisconnectAndReconnectDoNotAutoplay() async throws {
        try await start()
        beginInterruption(reason: .routeDisconnected)
        NotificationCenter.default.post(
            name: AVAudioSession.routeChangeNotification,
            object: AVAudioSession.sharedInstance(),
            userInfo: [AVAudioSessionRouteChangeReasonKey: AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue]
        )
        endInterruption(shouldResume: true)
        NotificationCenter.default.post(
            name: AVAudioSession.routeChangeNotification,
            object: AVAudioSession.sharedInstance(),
            userInfo: [AVAudioSessionRouteChangeReasonKey: AVAudioSession.RouteChangeReason.newDeviceAvailable.rawValue]
        )
        await drainPlaybackRequests()

        XCTAssertEqual(player.rate, 0)
        XCTAssertEqual(service.phase, .paused)
    }

    func testStopOrReplacementCannotBeRevivedByAnOldInterruption() async throws {
        for replacesQueue in [false, true] {
            try await start()
            beginInterruption()
            if replacesQueue {
                try await service.load([item("replacement")], startingAt: "replacement", at: 0)
            } else {
                service.stop()
            }

            endInterruption(shouldResume: true)
            await drainPlaybackRequests()

            XCTAssertEqual(player.rate, 0)
            XCTAssertFalse(service.phase.isActive)
            XCTAssertEqual(service.currentSongID, replacesQueue ? "replacement" : nil)
        }
    }

    func testPauseWinsWhilePlayIsWaitingForTheAudioSession() async throws {
        try await service.load([item("first")], startingAt: "first", at: 0)
        let pause = Task { @MainActor in self.service.pause() }

        try await service.play()
        await pause.value
        await drainPlaybackRequests()

        XCTAssertEqual(player.rate, 0)
        XCTAssertEqual(service.phase, .paused)
    }

    func testLoadingAnotherQueuePreparesItWithoutPlaying() async throws {
        try await start()

        try await service.load([item("replacement")], startingAt: "replacement", at: 0)

        XCTAssertEqual(service.currentSongID, "replacement")
        XCTAssertEqual(player.rate, 0)
        XCTAssertFalse(service.phase.isActive)
    }

    func testStoppingAnUnusedPreviewDoesNotReleaseAnotherMusicSession() async {
        AppAudioSession.lease(.listening)
        await AppAudioSession.waitForPendingOperations()

        service.stop()
        await AppAudioSession.waitForPendingOperations()

        XCTAssertEqual(AVAudioSession.sharedInstance().category, .playback)
    }

    func testAnotherOwnerSoundingPausesThePreviewForGood() async throws {
        try await start()
        let timetable = PreviewListeningPlaybackService(player: AVQueuePlayer(), owner: .timetablePreview)
        defer { timetable.stop() }
        try await timetable.load([item("other")], startingAt: "other", at: 0)

        try await timetable.play()
        XCTAssertEqual(player.rate, 0)
        XCTAssertEqual(service.phase, .paused)

        // Like iOS between apps, losing focus is not an interruption that resumes.
        beginInterruption()
        endInterruption(shouldResume: true)
        await drainPlaybackRequests()
        XCTAssertEqual(player.rate, 0)
    }

    func testPreviewOwnsOnlyItsOwnLease() async throws {
        AppAudioSession.lease(.listening)
        let timetable = PreviewListeningPlaybackService(player: AVQueuePlayer(), owner: .timetablePreview)
        try await timetable.load([item("other")], startingAt: "other", at: 0)
        try await timetable.play()

        timetable.stop()
        await AppAudioSession.waitForPendingOperations()

        XCTAssertEqual(AVAudioSession.sharedInstance().category, .playback)
    }

    func testResumePositionBeyondThePreviewStartsAtItsBeginning() async throws {
        try await service.load([item("first")], startingAt: "first", at: 42)
        XCTAssertEqual(service.currentTime, 0, accuracy: 0.01)

        try await service.load([item("first")], startingAt: "first", at: 5)
        XCTAssertEqual(service.currentTime, 5, accuracy: 0.1)
    }

    func testSystemQueueChangesReachObserversWithoutAVFoundationObservation() async throws {
        try await service.load([item("first"), item("second")], startingAt: "first", at: 0)
        var observedSong: String?
        let task = Task { @MainActor in
            for await id in BSObservationValues({ self.service.currentSongID }) {
                observedSong = id
            }
        }
        defer { task.cancel() }
        try await waitUntil { observedSong == "first" }

        // Simulate an automatic advance performed by the player, outside the service.
        player.advanceToNextItem()
        try await waitUntil { observedSong == "second" }
        player.removeAllItems()
        try await waitUntil { self.service.hasEnded }
    }

    private func start() async throws {
        try await service.load([item("first"), item("second")], startingAt: "first", at: 0)
        try await service.play()
        try await waitUntil { self.service.phase == .playing }
    }

    func testArtworkRequestHandlerRunsOffTheMainActor() async {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4)).image { _ in }
        let artwork = PreviewListeningPlaybackService.makeArtwork(image)
        // MPNowPlayingInfoCenter renders artwork on its own background queue.
        let rendered = await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                continuation.resume(returning: artwork.image(at: image.size) != nil)
            }
        }
        XCTAssertTrue(rendered)
    }

    private func item(_ id: String) -> ListeningPlaybackItem {
        ListeningPlaybackItem(songID: id, duration: 20, previewURL: url)
    }

    private func beginInterruption(reason: AVAudioSession.InterruptionReason = .default) {
        // AVPlayer pauses before the app handles the system notification.
        player.pause()
        NotificationCenter.default.post(
            name: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            userInfo: [
                AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.began.rawValue,
                AVAudioSessionInterruptionReasonKey: reason.rawValue
            ]
        )
    }

    private func endInterruption(shouldResume: Bool) {
        NotificationCenter.default.post(
            name: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            userInfo: [
                AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.ended.rawValue,
                AVAudioSessionInterruptionOptionKey: shouldResume ? AVAudioSession.InterruptionOptions.shouldResume.rawValue : 0
            ]
        )
    }

    private func drainPlaybackRequests() async {
        for _ in 0..<10 { await Task.yield() }
        await AppAudioSession.waitForPendingOperations()
    }
}
