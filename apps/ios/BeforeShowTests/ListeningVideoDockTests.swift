import AVFoundation
import XCTest
@testable import BeforeShow

@MainActor
final class ListeningVideoDockTests: XCTestCase {
    private struct NoStreamSearch: ArtistVideoSearching {
        func videos(for artist: String) async throws -> [ArtistVideo] { [] }
        func stream(for bvid: String) async throws -> ArtistVideoStream { throw CancellationError() }
    }

    private func openedDock() -> ListeningVideoDock {
        let dock = ListeningVideoDock(search: NoStreamSearch())
        let video = ArtistVideo(bvid: "BV1", title: "Live", author: "a", playCount: 0, duration: "3:00", coverURL: nil)
        dock.open(ListeningVideoSelection(artist: "a", video: video, related: []))
        return dock
    }

    override func tearDown() async throws {
        AppAudioSession.resetForTests()
        await AppAudioSession.waitForPendingOperations()
        try await super.tearDown()
    }

    func testMusicTakingFocusHandsTheMiniPlayerBackToMusic() {
        let dock = openedDock()
        AppAudioSession.claimFocus(.listening)
        XCTAssertFalse(dock.hasVideo)
    }

    func testOtherSoundOnlyPausesTheVideo() {
        let dock = openedDock()
        AppAudioSession.claimFocus(.memoryVideo)
        XCTAssertTrue(dock.hasVideo)
        dock.close()
    }

    func testPausedLoadDoesNotClaimFocusWhenTheStreamReturns() async throws {
        let search = SuspendedSearch()
        let dock = ListeningVideoDock(search: search)
        let claims = ClaimLog()
        let token = observeClaims(claims)
        defer {
            dock.close()
            search.failAll()
            NotificationCenter.default.removeObserver(token)
        }
        dock.open(selection("BV1"))
        try await waitUntil { search.isWaiting("BV1") }
        dock.pause()
        search.resume("BV1", url: try silentWAV())
        try await waitUntil { dock.player != nil }
        XCTAssertFalse(dock.isPlaying)
        XCTAssertEqual(dock.player?.timeControlStatus, .paused)
        XCTAssertFalse(claims.owners.contains(.artistVideo))
        XCTAssertTrue(dock.hasVideo)

        dock.play(video("BV2"))
        try await waitUntil { search.isWaiting("BV2") }
        search.resume("BV2", url: try silentWAV())
        try await waitUntil { dock.isPlaying }
        XCTAssertEqual(dock.selection?.video.id, "BV2")
        XCTAssertTrue(claims.owners.contains(.artistVideo))
    }

    func testLosingArtistVideoFocusCancelsAutoplayOfThePendingLoad() async throws {
        let search = SuspendedSearch()
        let dock = ListeningVideoDock(search: search)
        let claims = ClaimLog()
        let token = observeClaims(claims)
        defer {
            dock.close()
            search.failAll()
            NotificationCenter.default.removeObserver(token)
        }
        dock.open(selection("BV1"))
        try await waitUntil { search.isWaiting("BV1") }
        AppAudioSession.claimFocus(.memoryVideo)
        search.resume("BV1", url: try silentWAV())
        try await waitUntil { dock.player != nil }
        XCTAssertTrue(dock.hasVideo)
        XCTAssertFalse(dock.isPlaying)
        XCTAssertEqual(dock.player?.timeControlStatus, .paused)
        XCTAssertFalse(claims.owners.contains(.artistVideo))
    }

    func testManualResumeAfterAPausedLoadClaimsFocus() async throws {
        let search = SuspendedSearch()
        let dock = ListeningVideoDock(search: search)
        let claims = ClaimLog()
        let token = observeClaims(claims)
        defer {
            dock.close()
            search.failAll()
            NotificationCenter.default.removeObserver(token)
        }
        dock.open(selection("BV1"))
        try await waitUntil { search.isWaiting("BV1") }
        dock.pause()
        search.resume("BV1", url: try silentWAV())
        try await waitUntil { dock.player != nil }
        XCTAssertFalse(dock.isPlaying)
        dock.togglePlayback()
        try await waitUntil { dock.isPlaying }
        XCTAssertTrue(claims.owners.contains(.artistVideo))
    }

    func testFailedItemShowsRetryAndTheNextAttemptResolvesTheAddressAgain() async throws {
        let search = SuspendedSearch()
        let dock = ListeningVideoDock(search: search)
        defer {
            dock.close()
            search.failAll()
        }
        dock.open(selection("BV1"))
        try await waitUntil { search.isWaiting("BV1") }
        search.resume("BV1", url: missingMediaURL())
        try await waitUntil { dock.loadFailed }
        XCTAssertNotNil(dock.player)
        XCTAssertTrue(dock.loadFailed)
        XCTAssertFalse(dock.isPlaying)
        XCTAssertEqual(ListeningVideoScreenContent.resolve(loadFailed: true, hasPlayer: true), .failed)
        XCTAssertEqual(ListeningVideoScreenContent.resolve(loadFailed: false, hasPlayer: true), .player)
        XCTAssertEqual(ListeningVideoScreenContent.resolve(loadFailed: false, hasPlayer: false), .loading)

        let callsBeforeRetry = search.callCount
        dock.retry()
        try await waitUntil { search.callCount > callsBeforeRetry && search.isWaiting("BV1") }
        search.resume("BV1", url: try silentWAV())
        try await waitUntil { dock.isPlaying && !dock.loadFailed }
        XCTAssertFalse(dock.loadFailed)
        XCTAssertNotNil(dock.player)
    }

    func testFinishedPreviousItemDoesNotCloseTheVideoThatReplacedIt() async throws {
        let search = SuspendedSearch()
        let dock = ListeningVideoDock(search: search)
        defer {
            dock.close()
            search.failAll()
        }
        dock.open(selection("BV1"))
        try await waitUntil { search.isWaiting("BV1") }
        search.resume("BV1", url: try silentWAV())
        try await waitUntil { dock.player?.currentItem != nil }
        let finished = dock.player?.currentItem
        dock.play(video("BV2"))
        try await waitUntil { search.isWaiting("BV2") }
        search.resume("BV2", url: try silentWAV())
        try await waitUntil { dock.selection?.video.id == "BV2" && dock.isPlaying }
        NotificationCenter.default.post(name: AVPlayerItem.didPlayToEndTimeNotification, object: finished)
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(dock.selection?.video.id, "BV2")
        XCTAssertTrue(dock.hasVideo)
        XCTAssertFalse(dock.loadFailed)
    }

    func testOnlyTheCurrentLoadMayStartOrClosePlayback() {
        XCTAssertTrue(ListeningVideoLoadGate.accepts(generation: 2, current: 2))
        XCTAssertFalse(ListeningVideoLoadGate.accepts(generation: 1, current: 2))
        XCTAssertFalse(ListeningVideoLoadGate.shouldStartPlayback(
            autoplay: false, generation: 2, current: 2, cancelled: false, videoID: "BV1", selectedID: "BV1"
        ))
        XCTAssertFalse(ListeningVideoLoadGate.shouldStartPlayback(
            autoplay: true, generation: 1, current: 2, cancelled: false, videoID: "BV1", selectedID: "BV1"
        ))
        XCTAssertFalse(ListeningVideoLoadGate.shouldStartPlayback(
            autoplay: true, generation: 2, current: 2, cancelled: true, videoID: "BV1", selectedID: "BV1"
        ))
        XCTAssertFalse(ListeningVideoLoadGate.shouldStartPlayback(
            autoplay: true, generation: 2, current: 2, cancelled: false, videoID: "BV1", selectedID: "BV2"
        ))
        XCTAssertTrue(ListeningVideoLoadGate.shouldStartPlayback(
            autoplay: true, generation: 2, current: 2, cancelled: false, videoID: "BV1", selectedID: "BV1"
        ))
    }

    func testQueuedPlayingDoesNotReclaimFocusAfterAnotherSourcePauses() async throws {
        let search = SuspendedSearch()
        let dock = ListeningVideoDock(search: search)
        let claims = ClaimLog()
        let token = observeClaims(claims)
        defer {
            dock.close()
            search.failAll()
            NotificationCenter.default.removeObserver(token)
        }
        dock.open(selection("BV1"))
        try await waitUntil { search.isWaiting("BV1") }
        search.resume("BV1", url: try silentWAV())
        try await waitUntil { dock.isPlaying }
        let epoch = dock.playbackEpochValue
        let generation = dock.loadGeneration
        let player = dock.player
        AppAudioSession.claimFocus(.memoryVideo)
        let afterPause = claims.owners.count
        dock.consumeTimeControlStatus(.playing, player: player, generation: generation, emittedEpoch: epoch)
        XCTAssertFalse(dock.isPlaying)
        XCTAssertNotEqual(dock.playbackEpochValue, epoch)
        XCTAssertEqual(claims.owners.count, afterPause)
        XCTAssertFalse(claims.owners.suffix(from: afterPause).contains(.artistVideo))
        try await waitUntil { player?.timeControlStatus == .paused }
        dock.consumeTimeControlStatus(.playing, player: player, generation: generation, emittedEpoch: dock.playbackEpochValue)
        XCTAssertEqual(player?.timeControlStatus, .paused)
        XCTAssertEqual(claims.owners.count, afterPause)
        XCTAssertFalse(dock.isPlaying)
    }

    func testSystemPlayerResumeClaimsFocusAfterPause() async throws {
        let search = SuspendedSearch()
        let dock = ListeningVideoDock(search: search)
        let claims = ClaimLog()
        let token = observeClaims(claims)
        defer {
            dock.close()
            search.failAll()
            NotificationCenter.default.removeObserver(token)
        }
        dock.open(selection("BV1"))
        try await waitUntil { search.isWaiting("BV1") }
        search.resume("BV1", url: try silentWAV())
        try await waitUntil { dock.isPlaying }
        dock.pause()
        XCTAssertFalse(dock.isPlaying)
        let afterPause = claims.owners.count
        dock.player?.play()
        try await waitUntil { dock.isPlaying && claims.owners.count > afterPause }
        XCTAssertEqual(claims.owners.last, .artistVideo)
        XCTAssertEqual(dock.player?.timeControlStatus, .playing)
    }

    private func selection(_ bvid: String) -> ListeningVideoSelection {
        ListeningVideoSelection(artist: "a", video: video(bvid), related: [])
    }

    private func video(_ bvid: String) -> ArtistVideo {
        ArtistVideo(bvid: bvid, title: bvid, author: "a", playCount: 0, duration: "3:00", coverURL: nil)
    }

    private func observeClaims(_ log: ClaimLog) -> NSObjectProtocol {
        NotificationCenter.default.addObserver(forName: AppAudioSession.focusDidChange, object: nil, queue: nil) { note in
            let owner = note.object as? AppAudioSession.Owner
            MainActor.assumeIsolated {
                if let owner { log.owners.append(owner) }
            }
        }
    }

    private func waitUntil(_ condition: @MainActor () -> Bool) async throws {
        for _ in 0..<250 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTFail("Timed out waiting for video dock")
    }

    private func missingMediaURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("beforeshow-missing-\(UUID().uuidString).mp4")
    }

    private func silentWAV() throws -> URL {
        let sampleRate = 8_000
        let frames = sampleRate * 2
        let dataSize = frames * 2
        var data = Data()
        func append(_ string: String) { data.append(contentsOf: string.utf8) }
        func append32(_ value: UInt32) {
            var little = value.littleEndian
            withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
        }
        func append16(_ value: UInt16) {
            var little = value.littleEndian
            withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
        }
        append("RIFF")
        append32(UInt32(36 + dataSize))
        append("WAVE")
        append("fmt ")
        append32(16)
        append16(1)
        append16(1)
        append32(UInt32(sampleRate))
        append32(UInt32(sampleRate * 2))
        append16(2)
        append16(16)
        append("data")
        append32(UInt32(dataSize))
        data.append(Data(count: dataSize))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("beforeshow-\(UUID().uuidString).wav")
        try data.write(to: url)
        return url
    }
}

@MainActor
private final class ClaimLog {
    var owners: [AppAudioSession.Owner] = []
}

private final class SuspendedSearch: ArtistVideoSearching, @unchecked Sendable {
    private let lock = NSLock()
    private var waiters: [String: CheckedContinuation<ArtistVideoStream, Error>] = [:]
    private var pending: [String: Result<ArtistVideoStream, Error>] = [:]
    private var calls = 0

    func videos(for artist: String) async throws -> [ArtistVideo] { [] }

    func stream(for bvid: String) async throws -> ArtistVideoStream {
        try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            calls += 1
            if let result = pending.removeValue(forKey: bvid) {
                lock.unlock()
                continuation.resume(with: result)
                return
            }
            waiters[bvid] = continuation
            lock.unlock()
        }
    }

    var callCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return calls
    }

    func isWaiting(_ bvid: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return waiters[bvid] != nil
    }

    func resume(_ bvid: String, url: URL) {
        deliver(bvid, .success(ArtistVideoStream(url: url, headers: [:])))
    }

    func failAll() {
        lock.lock()
        let stranded = waiters
        waiters.removeAll()
        lock.unlock()
        stranded.values.forEach { $0.resume(throwing: CancellationError()) }
    }

    private func deliver(_ bvid: String, _ result: Result<ArtistVideoStream, Error>) {
        lock.lock()
        let waiter = waiters.removeValue(forKey: bvid)
        if waiter == nil { pending[bvid] = result }
        lock.unlock()
        waiter?.resume(with: result)
    }
}
