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

    func makeUIViewController(context: Context) -> ContainerViewController {
        let controller = ContainerViewController(rootView: content)
        controller.view.insetsLayoutMarginsFromSafeArea = false
        return controller
    }

    func updateUIViewController(_ controller: ContainerViewController, context: Context) {
        controller.hostingController.rootView = content
        let shouldSpin = isRotating && scenePhase != .background
        let isLayerActive = shouldSpin && isRootTabActive
        context.coordinator.update(
            controller: controller,
            identity: identity,
            isRotating: shouldSpin,
            isLayerActive: isLayerActive,
            revolutionsPerMinute: revolutionsPerMinute
        )
    }

    static func dismantleUIViewController(_ controller: ContainerViewController, coordinator: Coordinator) {
        coordinator.reset(controller: controller)
    }

    @MainActor
    final class ContainerViewController: UIViewController {
        let hostingController: UIHostingController<Content>

        init(rootView: Content) {
            self.hostingController = UIHostingController(rootView: rootView)
            super.init(nibName: nil, bundle: nil)
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = .clear
            view.insetsLayoutMarginsFromSafeArea = false

            hostingController.view.backgroundColor = .clear
            hostingController.view.layer.allowsEdgeAntialiasing = true
            hostingController.view.layer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            hostingController.view.insetsLayoutMarginsFromSafeArea = false
            if #available(iOS 16.4, *) {
                hostingController.safeAreaRegions = []
            }
            hostingController.view.autoresizingMask = []

            addChild(hostingController)
            view.addSubview(hostingController.view)
            hostingController.didMove(toParent: self)
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            let size = view.bounds.size
            guard size.width > 0, size.height > 0 else { return }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            hostingController.view.bounds = CGRect(origin: .zero, size: size)
            hostingController.view.center = CGPoint(x: view.bounds.midX, y: view.bounds.midY)
            CATransaction.commit()
        }
    }

    @MainActor final class Coordinator {
        private let animationKey = "listening.disc.continuousRotation"
        private var identity: String?
        private var revolutionsPerMinute: Double?
        private var isLayerActive = false

        func update(
            controller: ContainerViewController,
            identity: String,
            isRotating: Bool,
            isLayerActive: Bool,
            revolutionsPerMinute: Double
        ) {
            let layer = controller.hostingController.view.layer
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
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                layer.removeAnimation(forKey: animationKey)
                layer.speed = 1
                layer.timeOffset = 0
                layer.beginTime = 0
                layer.transform = CATransform3DMakeRotation(currentAngle, 0, 0, 1)
                CATransaction.commit()
                self.isLayerActive = false
                return
            }

            if !self.isLayerActive || layer.animation(forKey: animationKey) == nil || identityChanged {
                installRotation(on: layer, rpm: rpm, startAngle: currentAngle)
            }
            self.isLayerActive = true
        }

        func reset(controller: ContainerViewController) {
            let layer = controller.hostingController.view.layer
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer.speed = 1
            layer.timeOffset = 0
            layer.beginTime = 0
            layer.removeAnimation(forKey: animationKey)
            layer.transform = CATransform3DIdentity
            CATransaction.commit()
            isLayerActive = false
        }

        private func installRotation(on layer: CALayer, rpm: Double, startAngle: Double) {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer.removeAnimation(forKey: animationKey)
            layer.speed = 1
            layer.timeOffset = 0
            layer.beginTime = 0
            layer.transform = CATransform3DIdentity
            CATransaction.commit()

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
