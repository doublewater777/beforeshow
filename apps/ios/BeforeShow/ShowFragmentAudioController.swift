import AVFoundation
import Foundation

/// 现场碎片的语音录制控制器。
///
/// 封装 `AVAudioRecorder` 与 `AVAudioSession` 的生命周期：
/// - 录音结束后释放音频会话，避免 `.playAndRecord` 常驻导致试听声音从听筒播出；
/// - 重新录制或放弃时会删除上一段未保存的临时音频文件，避免磁盘泄漏；
/// - 通过 `AVAudioRecorderDelegate` 处理电话中断等异常停止，防止 UI 卡在"录音中"。
@MainActor
final class FragmentAudioRecorder: NSObject, ObservableObject, AVAudioRecorderDelegate {
    @Published private(set) var isRecording = false
    @Published private(set) var currentURL: URL?
    @Published private(set) var currentRelativePath: String?
    @Published private(set) var duration: TimeInterval?

    private var recorder: AVAudioRecorder?
    private let storage: ShowFragmentAudioStorage
    private let fileManager: FileManager

    init(
        storage: ShowFragmentAudioStorage = .applicationSupport(),
        fileManager: FileManager = .default
    ) {
        self.storage = storage
        self.fileManager = fileManager
        super.init()
    }

    /// 暴露底层 recorder，供实时波形组件读取电平。
    var avAudioRecorder: AVAudioRecorder? { recorder }

    func start() throws {
        // 重新录制前丢弃上一段未保存的录音文件，避免磁盘泄漏。
        if currentURL != nil {
            discard()
        }

        let relativePath = "FragmentAudio/\(UUID().uuidString).m4a"
        let url = storage.rootDirectory.appendingPathComponent(relativePath, isDirectory: false)
        try fileManager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default)
        try session.setActive(true)

        let recorder = try AVAudioRecorder(
            url: url,
            settings: [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 44_100,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue
            ]
        )
        recorder.delegate = self
        recorder.isMeteringEnabled = true
        recorder.record()

        self.recorder = recorder
        currentURL = url
        currentRelativePath = relativePath
        duration = nil
        isRecording = true
    }

    /// 停止录音并释放音频会话。返回已录制音频的快照供保存使用。
    @discardableResult
    func stop() -> (url: URL, relativePath: String, duration: TimeInterval)? {
        guard let recorder else { return nil }
        let stoppedDuration = recorder.currentTime
        recorder.stop()
        self.recorder = nil
        isRecording = false
        duration = stoppedDuration

        try? AVAudioSession.sharedInstance().setActive(
            false, options: .notifyOthersOnDeactivation
        )

        guard let url = currentURL, let relativePath = currentRelativePath else {
            return nil
        }
        return (url, relativePath, stoppedDuration)
    }

    /// 删除当前未保存的录音文件并清理状态。用于放弃录音或重新录制的场景。
    func discard() {
        if let url = currentURL {
            try? fileManager.removeItem(at: url)
        }
        clearState()
    }

    /// 保存成功后调用：放弃对当前文件的所有权但**不删除**文件（文件已由碎片引用）。
    func detach() {
        clearState()
    }

    private func clearState() {
        currentURL = nil
        currentRelativePath = nil
        duration = nil

        if recorder != nil {
            recorder?.stop()
            recorder = nil
            isRecording = false
            try? AVAudioSession.sharedInstance().setActive(
                false, options: .notifyOthersOnDeactivation
            )
        }
    }

    // MARK: - AVAudioRecorderDelegate

    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        Task { @MainActor in self.handleRecorderStopped() }
    }

    nonisolated func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        Task { @MainActor in self.handleRecorderStopped() }
    }

    @MainActor
    private func handleRecorderStopped() {
        guard recorder != nil else { return }
        _ = stop()
    }
}

/// 现场碎片语音试听控制器。
///
/// 通过 `AVAudioPlayerDelegate` 监听播放完成，替代原先基于 `Task.sleep` 的计时器，
/// 避免暂停/播放反复操作后累积多个无法取消的计时任务。
@MainActor
final class FragmentAudioPlayerController: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published private(set) var isPlaying = false
    private var player: AVAudioPlayer?

    func toggle(url: URL?) {
        guard let url else { return }

        if isPlaying {
            player?.pause()
            isPlaying = false
            return
        }

        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.delegate = self
            player.prepareToPlay()
            player.play()
            self.player = player
            isPlaying = true
        } catch {
            isPlaying = false
        }
    }

    // MARK: - AVAudioPlayerDelegate

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.handlePlaybackFinished() }
    }

    @MainActor
    private func handlePlaybackFinished() {
        player = nil
        isPlaying = false
    }
}
