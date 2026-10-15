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
