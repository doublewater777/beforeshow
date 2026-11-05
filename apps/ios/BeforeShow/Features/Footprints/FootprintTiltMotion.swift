import CoreMotion
import Observation

/// Device tilt for the pass hologram; runs only while a view holds it on screen.
@MainActor
@Observable
final class FootprintTiltMotion {
    /// Normalised to -1...1 on both axes.
    private(set) var roll: Double = 0
    private(set) var pitch: Double = 0

    @ObservationIgnored private let manager = CMMotionManager()

    func start() {
        guard manager.isDeviceMotionAvailable, !manager.isDeviceMotionActive else { return }
        manager.deviceMotionUpdateInterval = 1 / 30
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let motion else { return }
            MainActor.assumeIsolated {
                self?.roll = max(-1, min(1, motion.attitude.roll / 0.6))
                self?.pitch = max(-1, min(1, (motion.attitude.pitch - 0.7) / 0.5))
            }
        }
    }

    func stop() {
        manager.stopDeviceMotionUpdates()
    }
}
