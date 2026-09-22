import SwiftUI
import QuartzCore
#if os(iOS)
import UIKit
#endif

/// The displayed value is the state. Grabbing a moving part cancels its target,
/// never reads a SwiftUI animation's (already advanced) model endpoint.
struct CDSpringChannel {
    var value: Double
    var velocity: Double = 0
    var target: Double?
    var tolerance = CDPlayerConfiguration.Motion.normalizedTolerance
    mutating func move(to target: Double) { self.target = target }
    mutating func grab() { target = nil; velocity = 0 }
    mutating func step(_ dt: Double, frequency: Double = CDPlayerConfiguration.Motion.springFrequency, reducedMotion: Bool = false) {
        guard let target else { return }
        if reducedMotion {
            value = target; velocity = 0; self.target = nil
            return
        }
        // Analytic critically damped solution; stable at every refresh rate.
        let displacement = value - target
        let b = velocity + frequency * displacement
        let decay = exp(-frequency * dt)
        value = target + (displacement + b * dt) * decay
        velocity = (velocity - frequency * b * dt) * decay
        if abs(value - target) < tolerance && abs(velocity) < tolerance * frequency {
            value = target; velocity = 0; self.target = nil
        }
    }
}

@MainActor @Observable final class CDMotionDriver: NSObject {
    var lid = CDSpringChannel(value: 0)
    var discX = CDSpringChannel(value: 230, tolerance: CDPlayerConfiguration.Motion.positionTolerance)
    var discY = CDSpringChannel(value: 489, tolerance: CDPlayerConfiguration.Motion.positionTolerance)
    var lift = CDSpringChannel(value: 0)
    var discScale = CDSpringChannel(value: 1)
    var reducedMotion = false {
        didSet {
            guard reducedMotion != oldValue else { return }
            let now = Date()
            discAngle = projectedDiscAngle(at: now, advancing: spinning && !oldValue)
            rotationAnchorAngle = discAngle
            rotationAnchorDate = now
            discSpin = spinning && !reducedMotion ? Self.playbackRevolutionsPerSecond : 0
            wake()
        }
    }
    /// Label rotation in degrees. The visual clock is anchored to playback time,
    /// so hiding the view can pause frame delivery without pausing the disc's timeline.
    var discAngle: Double = 0
    /// Current visual angular velocity in revolutions per second.
    private(set) var discSpin: Double = 0
    /// Transport truth. Frame delivery may pause while this remains true.
    private(set) var spinning = false
    @ObservationIgnored var onFrame: () -> Void = {}
    @ObservationIgnored private var lastTime: Double = 0
    @ObservationIgnored private var rotationAnchorAngle: Double = 0
    @ObservationIgnored private var rotationAnchorDate = Date()

    /// Deliberately slower than a literal 33⅓ rpm deck: calm enough for album art
    /// to remain readable while still making playback state obvious.
    private static let playbackRevolutionsPerSecond = 0.30
    #if os(iOS)
    @ObservationIgnored private var link: CADisplayLink?
    @ObservationIgnored private var usesCruiseFrameRate = false
    #else
    @ObservationIgnored private var timer: Timer?
    #endif

    func wake() {
        #if os(iOS)
        if let link {
            if link.isPaused {
                lastTime = CACurrentMediaTime()
                link.isPaused = false
            }
        } else {
            start()
        }
        #else
        if timer == nil {
            start()
        }
        #endif
    }

    func start() {
        stop()
        lastTime = CACurrentMediaTime()
        #if os(iOS)
        let link = CADisplayLink(target: CDDisplayLinkTarget(owner: self), selector: #selector(CDDisplayLinkTarget.frame(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
        link.add(to: .main, forMode: .common)
        self.link = link
        #else
        let timer = Timer(timeInterval: 1 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.frame() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        #endif
    }
    func pause() {
        #if os(iOS)
        link?.isPaused = true
        #else
        stop()
        #endif
    }
    func stop() {
        #if os(iOS)
        link?.invalidate(); link = nil
        usesCruiseFrameRate = false
        #else
        timer?.invalidate(); timer = nil
        #endif
    }
    func synchronizePlayback(isPlaying: Bool, observedAt: Date = Date()) {
        let now = Date()
        let timestamp = observedAt > now ? now : observedAt
        discAngle = projectedDiscAngle(at: timestamp)
        rotationAnchorAngle = discAngle
        rotationAnchorDate = timestamp
        spinning = isPlaying
        discSpin = isPlaying && !reducedMotion ? Self.playbackRevolutionsPerSecond : 0
        wake()
    }

    /// Predict the angle from the playback clock rather than from delivered frames.
    /// This is intentionally internal so deterministic motion tests can cover a
    /// period where CADisplayLink is paused but audio continues.
    func projectedDiscAngle(at date: Date) -> Double {
        projectedDiscAngle(at: date, advancing: spinning && !reducedMotion)
    }

    private func projectedDiscAngle(at date: Date, advancing: Bool) -> Double {
        guard advancing else { return rotationAnchorAngle }
        let elapsed = max(0, date.timeIntervalSince(rotationAnchorDate))
        let angle = rotationAnchorAngle + elapsed * Self.playbackRevolutionsPerSecond * 360
        let normalized = angle.truncatingRemainder(dividingBy: 360)
        return normalized >= 0 ? normalized : normalized + 360
    }

    func resetDiscRotation() {
        discAngle = 0
        discSpin = 0
        spinning = false
        rotationAnchorAngle = 0
        rotationAnchorDate = Date()
    }
    fileprivate func frame() {
        let now = CACurrentMediaTime()
        let dt = min(now - lastTime, 1 / 15)
        lastTime = now
        let hadActiveSprings = lid.target != nil || discX.target != nil || discY.target != nil || lift.target != nil || discScale.target != nil
        lid.step(dt, reducedMotion: reducedMotion)
        discX.step(dt, reducedMotion: reducedMotion)
        discY.step(dt, reducedMotion: reducedMotion)
        lift.step(dt, reducedMotion: reducedMotion)
        discScale.step(dt, reducedMotion: reducedMotion)
        // Rotation follows an independent playback clock. CADisplayLink can be
        // suspended while the view is hidden; the next delivered frame catches up
        // immediately instead of resuming from the stale visual angle.
        discSpin = spinning && !reducedMotion ? Self.playbackRevolutionsPerSecond : 0
        if discSpin != 0 {
            discAngle = projectedDiscAngle(at: Date())
        }
        if hadActiveSprings {
            onFrame()
        }

        let springsResting = lid.target == nil && discX.target == nil && discY.target == nil && lift.target == nil && discScale.target == nil
        updateFrameRate(springsResting: springsResting)
        let visibleRotationResting = (reducedMotion || !spinning) && discSpin == 0
        if springsResting && visibleRotationResting {
            #if os(iOS)
            link?.isPaused = true
            #else
            stop()
            #endif
        }
    }

    private func updateFrameRate(springsResting: Bool) {
        #if os(iOS)
        let shouldUseCruiseFrameRate = springsResting && !reducedMotion && discSpin != 0
        guard shouldUseCruiseFrameRate != usesCruiseFrameRate else { return }
        usesCruiseFrameRate = shouldUseCruiseFrameRate
        link?.preferredFrameRateRange = shouldUseCruiseFrameRate
            ? CAFrameRateRange(minimum: 30, maximum: 30, preferred: 30)
            : CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
        #endif
    }
}

#if os(iOS)
@MainActor private final class CDDisplayLinkTarget: NSObject {
    weak var owner: CDMotionDriver?
    init(owner: CDMotionDriver) { self.owner = owner }
    @objc func frame(_ link: CADisplayLink) {
        guard let owner else { link.invalidate(); return }
        owner.frame()
    }
}
#endif
