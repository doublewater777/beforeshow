import AVFoundation

/// Feeds video frames using a host clock, without an audio player/session.
final class DynamicCoverFrameReader: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.beforeshow.dynamic-cover-frames")
    private let asset: AVAsset
    private let track: AVAssetTrack
    private let composition: AVVideoComposition
    private let renderer: AVSampleBufferVideoRenderer
    private let timebase: CMTimebase
    private let duration: CMTime
    private var reader: AVAssetReader?
    private var output: AVAssetReaderVideoCompositionOutput?
    private var isPlaying = false
    private var hasFirstFrame = false
    private var stopped = false

    init(asset: AVAsset, track: AVAssetTrack, composition: AVVideoComposition,
         renderer: AVSampleBufferVideoRenderer, timebase: CMTimebase, duration: CMTime) {
        self.asset = asset
        self.track = track
        self.composition = composition
        self.renderer = renderer
        self.timebase = timebase
        self.duration = duration
    }

    func start(isPlaying: Bool) {
        queue.async { [self] in
            self.isPlaying = isPlaying
            restart()
        }
    }

    func setPlaying(_ value: Bool) {
        queue.async { [self] in
            guard !stopped else { return }
            isPlaying = value
            if value && renderer.requiresFlushToResumeDecoding {
                restart()
            } else {
                CMTimebaseSetRate(timebase, rate: value && hasFirstFrame ? 1 : 0)
            }
        }
    }

    func loopIfNeeded() {
        queue.async { [self] in
            guard !stopped, isPlaying,
                  CMTimeCompare(CMTimebaseGetTime(timebase), duration) >= 0 else { return }
            restart()
        }
    }

    func stop() {
        queue.async { [self] in
            stopped = true
            CMTimebaseSetRate(timebase, rate: 0)
            renderer.stopRequestingMediaData()
            reader?.cancelReading()
            reader = nil
            output = nil
            renderer.flush()
        }
    }

    func finishStopping() async {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume() }
        }
    }

    private func restart() {
        guard !stopped else { return }
        CMTimebaseSetRate(timebase, rate: 0)
        renderer.stopRequestingMediaData()
        reader?.cancelReading()
        renderer.flush()
        hasFirstFrame = false
        do {
            let nextReader = try AVAssetReader(asset: asset)
            let output = AVAssetReaderVideoCompositionOutput(
                videoTracks: [track],
                videoSettings: [
                    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                    kCVPixelBufferIOSurfacePropertiesKey as String: [:]
                ]
            )
            output.videoComposition = composition
            output.alwaysCopiesSampleData = false
            guard nextReader.canAdd(output) else { return }
            nextReader.add(output)
            guard nextReader.startReading() else { return }
            reader = nextReader
            self.output = output
            CMTimebaseSetTime(timebase, time: .zero)
            renderer.requestMediaDataWhenReady(on: queue) { [weak self] in
                guard let self, !self.stopped else { return }
                while self.renderer.isReadyForMoreMediaData {
                    guard let sample = self.output?.copyNextSampleBuffer() else {
                        self.renderer.stopRequestingMediaData()
                        return
                    }
                    self.renderer.enqueue(sample)
                    if !self.hasFirstFrame {
                        self.hasFirstFrame = true
                        CMTimebaseSetRate(self.timebase, rate: self.isPlaying ? 1 : 0)
                    }
                }
            }
        } catch {
            reader = nil
        }
    }
}
