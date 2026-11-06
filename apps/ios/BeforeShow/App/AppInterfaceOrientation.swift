import UIKit

@MainActor
enum AppInterfaceOrientation {
    static var supported: UIInterfaceOrientationMask = .portrait

    /// The app is portrait-only; a full-screen viewer may let the phone turn sideways while it is up.
    static func allowLandscape(_ allowed: Bool) {
        supported = allowed ? .allButUpsideDown : .portrait
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        var controller = scene?.keyWindow?.rootViewController
        while let current = controller {
            current.setNeedsUpdateOfSupportedInterfaceOrientations()
            controller = current.presentedViewController
        }
        if !allowed {
            scene?.requestGeometryUpdate(.iOS(interfaceOrientations: .portrait))
        }
    }
}

extension BeforeShowAppDelegate {
    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        AppInterfaceOrientation.supported
    }
}
