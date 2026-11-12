import AVFoundation
import XCTest
@testable import BeforeShow

@MainActor
final class AppAudioSessionTests: XCTestCase {
    override func setUp() async throws {
        try await super.setUp()
        AppAudioSession.resetForTests()
        await AppAudioSession.waitForPendingOperations()
    }

    override func tearDown() async throws {
        AppAudioSession.resetForTests()
        await AppAudioSession.waitForPendingOperations()
        try await super.tearDown()
    }

    func testListeningLeaseSurvivesAMemoryVideo() async {
        AppAudioSession.lease(.listening)
        await AppAudioSession.waitForPendingOperations()
        XCTAssertEqual(AVAudioSession.sharedInstance().category, .playback)

        AppAudioSession.lease(.memoryVideo)
        AppAudioSession.release(.memoryVideo)
        await AppAudioSession.waitForPendingOperations()

        XCTAssertEqual(AVAudioSession.sharedInstance().category, .playback)
        AppAudioSession.release(.listening)
        await AppAudioSession.waitForPendingOperations()
        XCTAssertEqual(AVAudioSession.sharedInstance().category, .ambient)
    }

    func testPickAuditionPlaysThroughTheSilentSwitch() async {
        AppAudioSession.lease(.pickAudition)
        await AppAudioSession.waitForPendingOperations()
        XCTAssertEqual(AVAudioSession.sharedInstance().category, .playback)
        AppAudioSession.release(.pickAudition)
    }

    func testEachOwnerHoldsItsOwnLease() async {
        AppAudioSession.lease(.listening)
        AppAudioSession.lease(.timetablePreview)
        AppAudioSession.release(.timetablePreview)
        await AppAudioSession.waitForPendingOperations()
        XCTAssertEqual(AVAudioSession.sharedInstance().category, .playback, "releasing one owner must not end another's playback")

        AppAudioSession.release(.listening)
        await AppAudioSession.waitForPendingOperations()
        XCTAssertEqual(AVAudioSession.sharedInstance().category, .ambient)
    }

    func testFoleyNeverCutsOffMusicThatIsPlaying() {
        XCTAssertTrue(FootprintSoundPlayer.plays(category: .ambient, musicIsPlaying: true), "the ambient session mixes")
        XCTAssertFalse(FootprintSoundPlayer.plays(category: .playback, musicIsPlaying: true),
                       "a playback session would interrupt the music and never give it back")
        XCTAssertTrue(FootprintSoundPlayer.plays(category: .playback, musicIsPlaying: false))
    }

    func testClaimingFocusPausesEveryOtherOwnerOnly() {
        var paused: [AppAudioSession.Owner] = []
        let observers = [AppAudioSession.Owner.listening, .timetablePreview, .memoryVideo].map { owner in
            AppAudioSession.observeFocusLoss(of: owner) { paused.append(owner) }
        }
        defer { observers.forEach(NotificationCenter.default.removeObserver) }

        AppAudioSession.claimFocus(.timetablePreview)

        XCTAssertEqual(Set(paused), [.listening, .memoryVideo])
    }
}
