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
    mutating func move(to target: Double) { self.target = target }
    mutating func grab() { target = nil; velocity = 0 }
    mutating func step(_ dt: Double, frequency: Double = 15) {
        guard let target else { return }
        // Analytic critically damped solution; stable at every refresh rate.
        let displacement = value - target
        let b = velocity + frequency * displacement
        let decay = exp(-frequency * dt)
        value = target + (displacement + b * dt) * decay
        velocity = (velocity - frequency * b * dt) * decay
        if abs(value - target) < 0.0001 && abs(velocity) < 0.001 {
            value = target; velocity = 0; self.target = nil
        }
    }
}

@MainActor @Observable final class CDMotionDriver: NSObject {
    var lid = CDSpringChannel(value: 0)
    var discX = CDSpringChannel(value: 230)
    var discY = CDSpringChannel(value: 489)
    var lift = CDSpringChannel(value: 0)
    var discScale = CDSpringChannel(value: 1)
    var reducedMotion = false
    @ObservationIgnored private var lastTime: Double = 0
    #if os(iOS)
    @ObservationIgnored private var link: CADisplayLink?
    #else
    @ObservationIgnored private var timer: Timer?
    #endif
    func start() {
        stop()
        lastTime = CACurrentMediaTime()
        #if os(iOS)
        let link = CADisplayLink(target: CDDisplayLinkTarget(owner: self), selector: #selector(CDDisplayLinkTarget.frame(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        link.add(to: .main, forMode: .common)
        self.link = link
        #else
        let timer = Timer(timeInterval: 1 / 120, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.frame() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
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
        let frequency = reducedMotion ? 30.0 : 15.0
        lid.step(dt, frequency: frequency)
        discX.step(dt, frequency: frequency)
        discY.step(dt, frequency: frequency)
        lift.step(dt, frequency: frequency)
        discScale.step(dt, frequency: frequency)
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
