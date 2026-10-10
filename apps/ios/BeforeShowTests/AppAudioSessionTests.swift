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

    func testListeningLeaseSurvivesTemporarySoundSession() async {
        AppAudioSession.configureMusicPlayback()
        await AppAudioSession.waitForPendingOperations()
        XCTAssertEqual(AVAudioSession.sharedInstance().category, .playback)

        AppAudioSession.configureSoundPlayback()
        AppAudioSession.configureAmbient()
        await AppAudioSession.waitForPendingOperations()

        XCTAssertEqual(AVAudioSession.sharedInstance().category, .playback)
        AppAudioSession.releaseMusicPlayback()
        await AppAudioSession.waitForPendingOperations()
        XCTAssertEqual(AVAudioSession.sharedInstance().category, .ambient)
    }

    func testSoundSessionRestoresAmbientWhenListeningIsIdle() async {
        AppAudioSession.configureSoundPlayback()
        await AppAudioSession.waitForPendingOperations()
        XCTAssertEqual(AVAudioSession.sharedInstance().category, .playback)
        AppAudioSession.configureAmbient()
        await AppAudioSession.waitForPendingOperations()
        XCTAssertEqual(AVAudioSession.sharedInstance().category, .ambient)
    }
}
