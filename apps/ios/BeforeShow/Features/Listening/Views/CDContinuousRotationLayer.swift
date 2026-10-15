import SwiftUI
import UIKit
import QuartzCore

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
        return controller
    }

    func updateUIViewController(_ controller: UIHostingController<Content>, context: Context) {
        controller.rootView = content
        context.coordinator.update(
            layer: controller.view.layer,
            identity: identity,
            isRotating: isRotating && isRootTabActive && scenePhase != .background,
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
        private var isRotating = false

        func update(
            layer: CALayer,
            identity: String,
            isRotating: Bool,
            revolutionsPerMinute: Double
        ) {
            let rpm = max(revolutionsPerMinute, 0.01)
            if self.identity != identity || self.revolutionsPerMinute != rpm {
                reset(layer: layer)
                self.identity = identity
                self.revolutionsPerMinute = rpm
            }

            guard isRotating != self.isRotating else { return }
            if isRotating {
                if layer.animation(forKey: animationKey) == nil {
                    installRotation(on: layer, rpm: rpm)
                } else {
                    resume(layer: layer)
                }
            } else {
                pause(layer: layer)
            }
            self.isRotating = isRotating
        }

        func reset(layer: CALayer) {
            layer.speed = 1
            layer.timeOffset = 0
            layer.beginTime = 0
            layer.removeAnimation(forKey: animationKey)
            isRotating = false
        }

        private func installRotation(on layer: CALayer, rpm: Double) {
            let animation = CABasicAnimation(keyPath: "transform.rotation.z")
            animation.fromValue = 0.0
            animation.toValue = Double.pi * 2
            animation.duration = 60 / rpm
            animation.repeatCount = .infinity
            animation.timingFunction = CAMediaTimingFunction(name: .linear)
            animation.isRemovedOnCompletion = false
            layer.add(animation, forKey: animationKey)
        }

        private func pause(layer: CALayer) {
            guard layer.animation(forKey: animationKey) != nil, layer.speed != 0 else { return }
            let pausedTime = layer.convertTime(CACurrentMediaTime(), from: nil)
            layer.speed = 0
            layer.timeOffset = pausedTime
        }

        private func resume(layer: CALayer) {
            guard layer.speed == 0 else { return }
            let pausedTime = layer.timeOffset
            layer.speed = 1
            layer.timeOffset = 0
            layer.beginTime = 0
            let timeSincePause = layer.convertTime(CACurrentMediaTime(), from: nil) - pausedTime
            layer.beginTime = timeSincePause
        }
    }
}
