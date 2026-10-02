import AVFoundation
import SwiftUI
import UIKit

/// Dynamic covers are decoration and never own audio playback.
@MainActor
enum DynamicCoverPlaybackPolicy {
    static func includes(mediaType: AVMediaType) -> Bool {
        mediaType == .video
    }
}

/// A video-frame surface that cannot activate or interrupt an audio session.
struct DynamicCoverPlaybackView: View {
    let url: URL
    let isPlaying: Bool

    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        DynamicCoverPlayerSurface(
            url: url,
            isPlaying: isPlaying && scenePhase == .active
        )
    }
}

private struct DynamicCoverPlayerSurface: UIViewRepresentable {
    let url: URL
    let isPlaying: Bool

    func makeUIView(context: Context) -> DynamicCoverPlayerView {
        DynamicCoverPlayerView()
    }

    func updateUIView(_ view: DynamicCoverPlayerView, context: Context) {
        view.configure(url: url, isPlaying: isPlaying)
    }

    static func dismantleUIView(_ view: DynamicCoverPlayerView, coordinator: ()) {
        view.stop()
    }
}

@MainActor
final class DynamicCoverPlayerView: UIView {
    private var displayLayer: AVSampleBufferDisplayLayer { layer as! AVSampleBufferDisplayLayer }
    private var frameReader: DynamicCoverFrameReader?
    private var displayLink: CADisplayLink?
    private var loadTask: Task<Void, Never>?
    private var loadedURL: URL?
    private var isPlayingRequested = false

    override class var layerClass: AnyClass { AVSampleBufferDisplayLayer.self }

    override init(frame: CGRect) {
        super.init(frame: frame)
        displayLayer.videoGravity = .resizeAspectFill
        displayLayer.preventsDisplaySleepDuringVideoPlayback = false
        backgroundColor = .black
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(url: URL, isPlaying: Bool) {
        if loadedURL != url {
            let previousReader = frameReader
            stop()
            loadedURL = url
            isPlayingRequested = isPlaying
            loadTask = Task { @MainActor [weak self] in
                do {
                    await previousReader?.finishStopping()
                    try Task.checkCancellation()
                    let asset = AVURLAsset(url: url)
                    let tracks = try await asset.loadTracks(withMediaType: .video)
                    guard let track = tracks.first(where: {
                        DynamicCoverPlaybackPolicy.includes(mediaType: $0.mediaType)
                    }) else { return }
                    let duration = try await asset.load(.duration)
                    let composition = try await AVVideoComposition.videoComposition(withPropertiesOf: asset)
                    try Task.checkCancellation()
                    guard let self, self.loadedURL == url,
                          duration.isNumeric, duration.seconds > 0 else { return }
                    var timebase: CMTimebase?
                    guard CMTimebaseCreateWithSourceClock(
                        allocator: kCFAllocatorDefault,
                        sourceClock: CMClockGetHostTimeClock(),
                        timebaseOut: &timebase
                    ) == noErr, let timebase else { return }
                    self.displayLayer.controlTimebase = timebase
                    let reader = DynamicCoverFrameReader(
                        asset: asset,
                        track: track,
                        composition: composition,
                        renderer: self.displayLayer.sampleBufferRenderer,
                        timebase: timebase,
                        duration: duration
                    )
                    self.frameReader = reader
                    reader.start(isPlaying: self.isPlayingRequested)
                    let link = CADisplayLink(target: self, selector: #selector(self.checkLoop))
                    link.preferredFrameRateRange = CAFrameRateRange(minimum: 15, maximum: 15, preferred: 15)
                    link.isPaused = !self.isPlayingRequested
                    link.add(to: .main, forMode: .common)
                    self.displayLink = link
                } catch {
                    // The static cover remains available if a video cannot load.
                }
            }
            return
        }

        guard isPlayingRequested != isPlaying else { return }
        isPlayingRequested = isPlaying
        frameReader?.setPlaying(isPlaying)
        displayLink?.isPaused = !isPlaying
    }

    func stop() {
        isPlayingRequested = false
        loadTask?.cancel()
        loadTask = nil
        displayLink?.invalidate()
        displayLink = nil
        frameReader?.stop()
        frameReader = nil
        loadedURL = nil
    }

    @objc private func checkLoop() {
        frameReader?.loopIfNeeded()
    }
}
