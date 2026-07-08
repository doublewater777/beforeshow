import AVFoundation
import XCTest
@testable import BeforeShow

@MainActor
final class ShowFragmentAudioControllerTests: XCTestCase {
    private func makeStorage() -> ShowFragmentAudioStorage {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("BSFragmentAudioController-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return ShowFragmentAudioStorage(rootDirectory: url)
    }

    // 修复 #1：discard() 删除未保存的录音文件并清空状态。
    func testDiscardRemovesPendingAudioFile() throws {
        let storage = makeStorage()
        let recorder = FragmentAudioRecorder(storage: storage)
        try recorder.start()

        let url = try XCTUnwrap(recorder.currentURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))

        recorder.discard()

        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        XCTAssertNil(recorder.currentURL)
        XCTAssertFalse(recorder.isRecording)
    }

    // 修复 #1：重新录制时，上一段未保存的录音文件被丢弃，不残留。
    func testStartingAgainDiscardsPreviousTake() throws {
        let storage = makeStorage()
        let recorder = FragmentAudioRecorder(storage: storage)
        try recorder.start()
        let firstURL = try XCTUnwrap(recorder.currentURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: firstURL.path))

        try recorder.start()

        XCTAssertFalse(FileManager.default.fileExists(atPath: firstURL.path))
        XCTAssertNotNil(recorder.currentURL)
        XCTAssertNotEqual(recorder.currentURL, firstURL)
    }

    // 修复 #2：stop() 后停止录音、释放底层 recorder，但保留文件供保存使用。
    func testStopReleasesRecordingStateButKeepsFile() throws {
        let storage = makeStorage()
        let recorder = FragmentAudioRecorder(storage: storage)
        try recorder.start()
        XCTAssertTrue(recorder.isRecording)

        let snapshot = try XCTUnwrap(recorder.stop())

        XCTAssertFalse(recorder.isRecording)
        XCTAssertNil(recorder.avAudioRecorder)
        XCTAssertTrue(FileManager.default.fileExists(atPath: snapshot.url.path))
        XCTAssertEqual(snapshot.url, recorder.currentURL)
    }

    // 保存路径：detach() 转移文件所有权但不删除（文件已由碎片引用）。
    func testDetachKeepsFileForArchivedFragment() throws {
        let storage = makeStorage()
        let recorder = FragmentAudioRecorder(storage: storage)
        try recorder.start()
        let url = try XCTUnwrap(recorder.currentURL)

        recorder.detach()

        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        XCTAssertNil(recorder.currentURL)
        XCTAssertFalse(recorder.isRecording)
    }

    // 修复 #4：录音被中断时 delegate 回调复位状态，UI 不会卡在"录音中"。
    func testRecorderInterruptionResetsState() async throws {
        let storage = makeStorage()
        let recorder = FragmentAudioRecorder(storage: storage)
        try recorder.start()
        XCTAssertTrue(recorder.isRecording)
        let avRecorder = try XCTUnwrap(recorder.avAudioRecorder)

        recorder.audioRecorderDidFinishRecording(avRecorder, successfully: false)

        // delegate 在 Task @MainActor 中异步停止，等待主线程排空。
        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertFalse(recorder.isRecording)
    }

    // 修复 #3：播放完成后通过 delegate 复位 isPlaying，不再依赖 Task.sleep 计时器。
    func testPlayerResetsIsPlayingAfterFinish() async throws {
        let url = try makeSineWaveAudioFile()
        let player = FragmentAudioPlayerController()
        player.toggle(url: url)
        XCTAssertTrue(player.isPlaying)

        for _ in 0..<50 {
            if !player.isPlaying { break }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        XCTAssertFalse(player.isPlaying)
    }

    // MARK: - Helpers

    private func makeSineWaveAudioFile() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("BSFragmentAudioController-\(UUID().uuidString).caf")
        let sampleRate: Double = 8_000
        let frameCount = AVAudioFrameCount(sampleRate * 0.2)
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        buffer.frameLength = frameCount

        let channel = buffer.floatChannelData![0]
        for frame in 0..<Int(frameCount) {
            let phase = Double(frame) / sampleRate * 440 * 2 * Double.pi
            channel[frame] = Float(sin(phase) * (Double(frame % 97) / 96.0))
        }

        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buffer)
        return url
    }
}
