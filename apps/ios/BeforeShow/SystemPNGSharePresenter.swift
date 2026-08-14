import UIKit

@MainActor
enum SystemPNGSharePresenter {
    static func present(url: URL) -> Bool {
        present(items: [url]) { _, _, _, _ in
            try? FileManager.default.removeItem(at: url)
        }
    }

    static func present(items: [Any]) -> Bool {
        present(items: items, completion: nil)
    }

    private static func present(
        items: [Any],
        completion: UIActivityViewController.CompletionWithItemsHandler?
    ) -> Bool {
        guard let presenter = topViewController() else { return false }
        let controller = UIActivityViewController(
            activityItems: items,
            applicationActivities: nil
        )
        controller.completionWithItemsHandler = completion
        if let popover = controller.popoverPresentationController {
            popover.sourceView = presenter.view
            popover.sourceRect = CGRect(
                x: presenter.view.bounds.midX,
                y: presenter.view.bounds.maxY,
                width: 1,
                height: 1
            )
        }
        presenter.present(controller, animated: true)
        return true
    }

    static func topViewController() -> UIViewController? {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }),
              let root = scene.windows.first(where: \.isKeyWindow)?.rootViewController else {
            return nil
        }
        return topViewController(from: root)
    }

    private static func topViewController(from controller: UIViewController) -> UIViewController {
        if let presented = controller.presentedViewController {
            return topViewController(from: presented)
        }
        if let navigation = controller as? UINavigationController,
           let visible = navigation.visibleViewController {
            return topViewController(from: visible)
        }
        if let tabs = controller as? UITabBarController,
           let selected = tabs.selectedViewController {
            return topViewController(from: selected)
        }
        return controller
    }
}
