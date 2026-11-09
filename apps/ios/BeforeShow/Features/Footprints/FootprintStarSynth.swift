import AVFoundation
import os

/// A small celesta for the night sky: one bell-like voice per finger, ringing while
/// held and fading when let go. It rides the app's ambient session like the other
/// Footprints sounds, so it mixes with music and follows the silent switch.
final class FootprintStarSynth: @unchecked Sendable {
    /// 一种音色：泛音配比加上起音和衰减。每种音阶配一种。
    struct Timbre: Hashable {
        /// Second and third harmonic amounts at full brightness.
        let second: Float
        let third: Float
        /// Fraction of the ring left after one second while held.
        let ringPerSecond: Double
        /// The level a held note settles at; zero lets it die away even under a finger.
        let floor: Float
        let overtonePerSecond: Double
        /// Per-sample approach to the ring level: higher is a harder strike.
        let attack: Float

        /// 钢片琴：现在的声音。
        static let celesta = Timbre(second: 0.35, third: 0.15, ringPerSecond: 0.35, floor: 0.28, overtonePerSecond: 0.05, attack: 0.02)
        /// 八音盒：亮、短，按住也会自己消失。
        static let musicBox = Timbre(second: 0.15, third: 0.45, ringPerSecond: 0.12, floor: 0, overtonePerSecond: 0.2, attack: 0.08)
        /// 柔和的钢琴：泛音少，尾音长。
        static let softPiano = Timbre(second: 0.22, third: 0.04, ringPerSecond: 0.5, floor: 0.22, overtonePerSecond: 0.3, attack: 0.008)
        /// 拨弦：起音硬，很快衰减，像古筝或三味线。
        static let pluck = Timbre(second: 0.55, third: 0.3, ringPerSecond: 0.05, floor: 0, overtonePerSecond: 0.01, attack: 0.2)
        /// 电钢琴：二次泛音重，带一点钟声。
        static let electricPiano = Timbre(second: 0.6, third: 0.08, ringPerSecond: 0.4, floor: 0.25, overtonePerSecond: 0.12, attack: 0.03)
    }

    private struct Voice {
        let id: Int
        /// Phase advance per sample, as a rotation (cos, sin) so no trig runs per sample.
        let stepCos: Float
        let stepSin: Float
        /// How much overtone the bell carries: brighter for artists seen more.
        let brightness: Float
        let second: Float
        let third: Float
        let ringDecay: Float
        let floor: Float
        let overtoneDecay: Float
        let attack: Float
        var cos: Float = 1
        var sin: Float = 0
        var level: Float = 0
        var ring: Float = 1
        /// Overtones die away faster than the fundamental, like a struck bar.
        var overtone: Float = 1
        /// Samples played so far; a quick tap still gets its full strike before letting go.
        var played = 0
        var released = false
    }

    static let shared = FootprintStarSynth()

    private let engine = AVAudioEngine()
    private let voices = OSAllocatedUnfairLock(initialState: [Voice]())
    private let sampleRate: Double
    private var isStarted = false
    private var configObserver: (any NSObjectProtocol)?

    private init() {
        let output = engine.outputNode.outputFormat(forBus: 0).sampleRate
        sampleRate = output > 0 ? output : 48_000
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        // Per-sample release rate, worked out once for this sample rate.
        let rate = sampleRate
        let releaseDecay = Float(pow(0.0006, 1 / rate))
        // However quick the tap, the note strikes for this long before a release takes hold.
        let strike = Int(rate * 0.06)
        let source = AVAudioSourceNode(format: format) { [voices] _, _, frameCount, bufferList in
            let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
            guard let out = buffers.first?.mData?.assumingMemoryBound(to: Float.self) else { return noErr }
            let frames = Int(frameCount)
            for frame in 0..<frames { out[frame] = 0 }
            voices.withLock { voices in
                // Voice by voice with everything in locals: cheap enough for the audio thread.
                for index in voices.indices {
                    var v = voices[index]
                    for frame in 0..<frames {
                        v.played += 1
                        if v.released && v.played > strike {
                            v.level *= releaseDecay
                        } else {
                            v.level += (v.ring - v.level) * v.attack
                            v.ring = max(v.floor, v.ring * v.ringDecay)
                        }
                        v.overtone *= v.overtoneDecay
                        // Rotate the phasor one step.
                        let c = v.cos * v.stepCos - v.sin * v.stepSin
                        let s = v.sin * v.stepCos + v.cos * v.stepSin
                        v.cos = c
                        v.sin = s
                        // Second and third harmonics from the same phasor.
                        let second = 2 * s * c
                        let third = s * (3 - 4 * s * s)
                        out[frame] += (s + v.brightness * v.overtone * (v.second * second + v.third * third)) * v.level
                    }
                    // Keep the phasor on the unit circle against rounding drift.
                    let norm = 1 / (v.cos * v.cos + v.sin * v.sin).squareRoot()
                    v.cos *= norm
                    v.sin *= norm
                    voices[index] = v
                }
                voices.removeAll { $0.released && $0.played > strike && $0.level < 0.0005 }
            }
            for frame in 0..<frames { out[frame] = tanhf(out[frame] * 0.24) }
            return noErr
        }
        engine.attach(source)
        engine.connect(source, to: engine.mainMixerNode, format: format)
        engine.mainMixerNode.outputVolume = 0.7

        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: nil
        ) { [weak self] _ in
            self?.handleConfigurationChange()
        }
    }

    func start() {
        AppAudioSession.workQueue.async { [weak self, engine] in
            guard let self else { return }
            self.isStarted = true
            guard !engine.isRunning else { return }
            try? engine.start()
        }
    }

    func stop() {
        voices.withLock { $0.removeAll() }
        AppAudioSession.workQueue.async { [weak self, engine] in
            guard let self else { return }
            self.isStarted = false
            engine.stop()
        }
    }

    private func handleConfigurationChange() {
        voices.withLock { $0.removeAll() }
        AppAudioSession.workQueue.async { [weak self] in
            guard let self, self.isStarted else { return }
            if !self.engine.isRunning {
                try? self.engine.start()
            }
        }
    }

    /// `gain` scales the voice: accompaniment sits under the melody.
    func press(_ id: Int, note: Int, brightness: Double, timbre: Timbre = .celesta, gain: Float = 1) {
        start()
        let step = 2 * Double.pi * FootprintStarScale.frequency(of: note) / sampleRate
        let perSample = { (fraction: Double) in Float(pow(fraction, 1 / self.sampleRate)) }
        let voice = Voice(
            id: id,
            stepCos: Float(Foundation.cos(step)),
            stepSin: Float(Foundation.sin(step)),
            brightness: Float(brightness),
            second: timbre.second,
            third: timbre.third,
            ringDecay: perSample(timbre.ringPerSecond),
            floor: timbre.floor * gain,
            overtoneDecay: perSample(timbre.overtonePerSecond),
            attack: timbre.attack,
            ring: gain
        )
        voices.withLock { voices in
            for index in voices.indices where voices[index].id == id { voices[index].released = true }
            // A handful of fingers is plenty; drop the oldest ringing voice past that.
            if voices.count >= 10, let oldest = voices.firstIndex(where: \.released) ?? voices.indices.first {
                voices.remove(at: oldest)
            }
            voices.append(voice)
        }
    }

    func release(_ id: Int) {
        voices.withLock { voices in
            for index in voices.indices where voices[index].id == id { voices[index].released = true }
        }
    }
}
