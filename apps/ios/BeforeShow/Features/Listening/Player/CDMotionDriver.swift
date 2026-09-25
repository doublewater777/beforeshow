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
        didSet { if reducedMotion != oldValue { wake() } }
    }
    @ObservationIgnored var onFrame: () -> Void = {}
    @ObservationIgnored private var lastTime: Double = 0
    #if os(iOS)
    @ObservationIgnored private var link: CADisplayLink?
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
        #else
        timer?.invalidate(); timer = nil
        #endif
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

        if hadActiveSprings {
            onFrame()
        }

        let springsResting = lid.target == nil && discX.target == nil && discY.target == nil && lift.target == nil && discScale.target == nil
        if springsResting {
            #if os(iOS)
            link?.isPaused = true
            #else
            stop()
            #endif
        }
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
