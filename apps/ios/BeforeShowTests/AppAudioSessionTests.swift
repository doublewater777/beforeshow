import AVFoundation
import XCTest
@testable import BeforeShow

@MainActor
final class AppAudioSessionTests: XCTestCase {
    override func setUp() {
        super.setUp()
        AppAudioSession.resetForTests()
    }

    override func tearDown() {
        AppAudioSession.resetForTests()
        super.tearDown()
    }

    func testListeningLeaseSurvivesTemporarySoundSession() {
        AppAudioSession.configureMusicPlayback()
        XCTAssertEqual(AVAudioSession.sharedInstance().category, .playback)

        AppAudioSession.configureSoundPlayback()
        AppAudioSession.configureAmbient()

        XCTAssertEqual(AVAudioSession.sharedInstance().category, .playback)
        AppAudioSession.releaseMusicPlayback()
        XCTAssertEqual(AVAudioSession.sharedInstance().category, .ambient)
    }

    func testSoundSessionRestoresAmbientWhenListeningIsIdle() {
        AppAudioSession.configureSoundPlayback()
        XCTAssertEqual(AVAudioSession.sharedInstance().category, .playback)
        AppAudioSession.configureAmbient()
        XCTAssertEqual(AVAudioSession.sharedInstance().category, .ambient)
    }
}
