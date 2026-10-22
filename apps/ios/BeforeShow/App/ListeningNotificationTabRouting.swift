import SwiftUI

struct ListeningNotificationTabRouting: ViewModifier {
    @Binding var selectedTab: BeforeShowTab
    private let router = NotificationDeepLinkRouter.shared

    func body(content: Content) -> some View {
        content.task(id: router.featureRootDeepLink) {
            guard let link = router.featureRootDeepLink, link.destination == .listen,
                  await BSNotificationNavigationGate.waitUntilAvailable(),
                  router.featureRootDeepLink == link else { return }
            selectedTab = .listen
        }
    }
}
