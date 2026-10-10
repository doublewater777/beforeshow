import UIKit

/// The timetable viewer temporarily allows rotation; every other surface stays portrait.
@MainActor
final class TimetableOrientationController {
    private weak var scene: UIWindowScene?
    private var isViewingEnabled = false

    func attach(to scene: UIWindowScene) {
        self.scene = scene
        updateSupportedOrientations()
    }

    func setViewingEnabled(_ enabled: Bool) {
        guard isViewingEnabled != enabled else { return }
        isViewingEnabled = enabled
        updateSupportedOrientations()
        if !enabled {
            scene?.requestGeometryUpdate(.iOS(interfaceOrientations: .portrait))
        }
    }

    func toggleOrientation() {
        guard isViewingEnabled, let scene else { return }
        let orientations: UIInterfaceOrientationMask = scene.effectiveGeometry.interfaceOrientation.isLandscape
            ? .portrait : .landscape
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: orientations))
    }

    private func updateSupportedOrientations() {
        AppInterfaceOrientation.supported = isViewingEnabled ? .allButUpsideDown : .portrait
        var controller = scene?.keyWindow?.rootViewController
        while let current = controller {
            current.setNeedsUpdateOfSupportedInterfaceOrientations()
            controller = current.presentedViewController
        }
    }
}
