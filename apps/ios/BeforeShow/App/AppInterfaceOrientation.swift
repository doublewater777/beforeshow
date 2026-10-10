import UIKit

@MainActor
enum AppInterfaceOrientation {
    static var supported: UIInterfaceOrientationMask = .portrait
}

extension BeforeShowAppDelegate {
    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        AppInterfaceOrientation.supported
    }
}
