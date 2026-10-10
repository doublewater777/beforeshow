import SwiftUI
import UIKit

/// Reads the viewer's own window scene rather than choosing a global foreground window.
struct TimetableOrientationHost: UIViewRepresentable {
    let controller: TimetableOrientationController
    let isEnabled: Bool

    func makeUIView(context: Context) -> SceneView {
        let view = SceneView()
        view.onSceneAvailable = controller.attach(to:)
        return view
    }

    func updateUIView(_ uiView: SceneView, context: Context) {
        controller.setViewingEnabled(isEnabled)
    }

    final class SceneView: UIView {
        var onSceneAvailable: ((UIWindowScene) -> Void)?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            if let scene = window?.windowScene {
                onSceneAvailable?(scene)
            }
        }
    }
}
