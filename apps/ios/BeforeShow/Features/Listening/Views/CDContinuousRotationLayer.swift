import SwiftUI
import UIKit
import QuartzCore

@MainActor
final class CDContinuousRotationStore {
    static let shared = CDContinuousRotationStore()

    struct State {
        var baseAngle: Double = 0
        var referenceTime: CFTimeInterval?
        var revolutionsPerMinute: Double = BSListeningTokens.discRotationRPM
        var isRotating: Bool = false
    }

    private var states: [String: State] = [:]

    func currentAngle(for identity: String, at time: CFTimeInterval = CACurrentMediaTime()) -> Double {
        guard let state = states[identity] else { return 0 }
        guard state.isRotating, let ref = state.referenceTime else {
            return state.baseAngle
        }
        let elapsed = max(0, time - ref)
        let delta = elapsed * (2 * .pi * (state.revolutionsPerMinute / 60.0))
        return (state.baseAngle + delta).truncatingRemainder(dividingBy: 2 * .pi)
    }

    @discardableResult
    func update(
        identity: String,
        isRotating: Bool,
        revolutionsPerMinute: Double,
        at time: CFTimeInterval = CACurrentMediaTime()
    ) -> Double {
        let rpm = max(revolutionsPerMinute, 0.01)
        var state = states[identity] ?? State(revolutionsPerMinute: rpm)
        let current = currentAngle(for: identity, at: time)

        if isRotating {
            if !state.isRotating || state.referenceTime == nil {
                state.baseAngle = current
                state.referenceTime = time
            }
            state.revolutionsPerMinute = rpm
            state.isRotating = true
        } else {
            state.baseAngle = current
            state.referenceTime = nil
            state.revolutionsPerMinute = rpm
            state.isRotating = false
        }
        states[identity] = state
        return current
    }

    func reset(identity: String) {
        states.removeValue(forKey: identity)
    }

    #if DEBUG
    func resetAll() {
        states.removeAll()
    }
    #endif
}

/// The disc motor is rendered by Core Animation rather than the mechanism's
/// display link. This keeps continuous playback rotation on the compositor
/// while the app is foreground-inactive under Notification Center or Control Center.
struct CDContinuousRotationLayer<Content: View>: UIViewControllerRepresentable {
    let identity: String
    let isRotating: Bool
    let revolutionsPerMinute: Double
    let content: Content

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.isRootTabActive) private var isRootTabActive

    init(
        identity: String,
        isRotating: Bool,
        revolutionsPerMinute: Double,
        @ViewBuilder content: () -> Content
    ) {
        self.identity = identity
        self.isRotating = isRotating
        self.revolutionsPerMinute = revolutionsPerMinute
        self.content = content()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIViewController(context: Context) -> UIHostingController<Content> {
        let controller = UIHostingController(rootView: content)
        controller.view.backgroundColor = .clear
        controller.view.layer.allowsEdgeAntialiasing = true
        controller.view.insetsLayoutMarginsFromSafeArea = false
        if #available(iOS 16.4, *) {
            controller.safeAreaRegions = []
        }
        return controller
    }

    func updateUIViewController(_ controller: UIHostingController<Content>, context: Context) {
        controller.rootView = content
        let shouldSpin = isRotating && scenePhase != .background
        let isLayerActive = shouldSpin && isRootTabActive
        context.coordinator.update(
            layer: controller.view.layer,
            identity: identity,
            isRotating: shouldSpin,
            isLayerActive: isLayerActive,
            revolutionsPerMinute: revolutionsPerMinute
        )
    }

    static func dismantleUIViewController(_ controller: UIHostingController<Content>, coordinator: Coordinator) {
        coordinator.reset(layer: controller.view.layer)
    }

    @MainActor final class Coordinator {
        private let animationKey = "listening.disc.continuousRotation"
        private var identity: String?
        private var revolutionsPerMinute: Double?
        private var isLayerActive = false

        func update(
            layer: CALayer,
            identity: String,
            isRotating: Bool,
            isLayerActive: Bool,
            revolutionsPerMinute: Double
        ) {
            let rpm = max(revolutionsPerMinute, 0.01)
            let identityChanged = self.identity != identity
            if identityChanged || self.revolutionsPerMinute != rpm {
                self.identity = identity
                self.revolutionsPerMinute = rpm
            }

            let now = CACurrentMediaTime()
            let currentAngle = CDContinuousRotationStore.shared.update(
                identity: identity,
                isRotating: isRotating,
                revolutionsPerMinute: rpm,
                at: now
            )

            if !isLayerActive {
                layer.removeAnimation(forKey: animationKey)
                layer.speed = 1
                layer.timeOffset = 0
                layer.beginTime = 0
                layer.transform = CATransform3DMakeRotation(currentAngle, 0, 0, 1)
                self.isLayerActive = false
                return
            }

            if !self.isLayerActive || layer.animation(forKey: animationKey) == nil || identityChanged {
                installRotation(on: layer, rpm: rpm, startAngle: currentAngle)
            }
            self.isLayerActive = true
        }

        func reset(layer: CALayer) {
            layer.speed = 1
            layer.timeOffset = 0
            layer.beginTime = 0
            layer.removeAnimation(forKey: animationKey)
            isLayerActive = false
        }

        private func installRotation(on layer: CALayer, rpm: Double, startAngle: Double) {
            layer.removeAnimation(forKey: animationKey)
            layer.speed = 1
            layer.timeOffset = 0
            layer.beginTime = 0
            layer.transform = CATransform3DIdentity

            let animation = CABasicAnimation(keyPath: "transform.rotation.z")
            animation.fromValue = startAngle
            animation.toValue = startAngle + (Double.pi * 2)
            animation.duration = 60.0 / rpm
            animation.repeatCount = .infinity
            animation.timingFunction = CAMediaTimingFunction(name: .linear)
            animation.isRemovedOnCompletion = false
            layer.add(animation, forKey: animationKey)
        }
    }
}
