import AVFoundation
import os

/// A small celesta for the night sky: one bell-like voice per finger, ringing while
/// held and fading when let go. It rides the app's ambient session like the other
/// Footprints sounds, so it mixes with music and follows the silent switch.
final class FootprintStarSynth: @unchecked Sendable {
    private struct Voice {
        let id: Int
        /// Phase advance per sample, as a rotation (cos, sin) so no trig runs per sample.
        let stepCos: Float
        let stepSin: Float
        /// How much overtone the bell carries: brighter for artists seen more.
        let brightness: Float
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

    private init() {
        let output = engine.outputNode.outputFormat(forBus: 0).sampleRate
        sampleRate = output > 0 ? output : 48_000
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        // Per-sample envelope rates, worked out once for this sample rate.
        let rate = sampleRate
        let perSecond = { (fraction: Double) in Float(pow(fraction, 1 / rate)) }
        let ringDecay = perSecond(0.35)
        let overtoneDecay = perSecond(0.05)
        let releaseDecay = perSecond(0.0006)
        let attack: Float = 0.02
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
                            v.level += (v.ring - v.level) * attack
                            v.ring = max(0.28, v.ring * ringDecay)
                        }
                        v.overtone *= overtoneDecay
                        // Rotate the phasor one step.
                        let c = v.cos * v.stepCos - v.sin * v.stepSin
                        let s = v.sin * v.stepCos + v.cos * v.stepSin
                        v.cos = c
                        v.sin = s
                        // Second and third harmonics from the same phasor.
                        let second = 2 * s * c
                        let third = s * (3 - 4 * s * s)
                        out[frame] += (s + v.brightness * v.overtone * (0.35 * second + 0.15 * third)) * v.level
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
    }

    func start() {
        AppAudioSession.workQueue.async { [engine] in
            guard !engine.isRunning else { return }
            try? engine.start()
        }
    }

    func stop() {
        voices.withLock { $0.removeAll() }
        AppAudioSession.workQueue.async { [engine] in engine.stop() }
    }

    func press(_ id: Int, note: Int, brightness: Double) {
        let step = 2 * Double.pi * FootprintStarScale.frequency(of: note) / sampleRate
        let voice = Voice(id: id, stepCos: Float(Foundation.cos(step)), stepSin: Float(Foundation.sin(step)), brightness: Float(brightness))
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
