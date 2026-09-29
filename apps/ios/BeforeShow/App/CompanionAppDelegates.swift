import CloudKit
import Foundation
import SwiftData
import UIKit

final class BeforeShowAppDelegate: NSObject, UIApplicationDelegate {
    static weak var shared: BeforeShowAppDelegate?

    var companionCoordinator: CompanionSharingCoordinator?
    var modelContainer: ModelContainer?

    override init() {
        super.init()
        Self.shared = self
    }

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(
            name: "Default Configuration",
            sessionRole: connectingSceneSession.role
        )
        configuration.delegateClass = BeforeShowSceneDelegate.self
        return configuration
    }

    func application(
        _ application: UIApplication,
        userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata
    ) {
        deliverAcceptedShare(cloudKitShareMetadata)
    }

    func deliverAcceptedShare(
        _ metadata: CKShare.Metadata,
        startsNewPresentation: Bool = true
    ) {
        guard let coordinator = companionCoordinator else {
            // Persist before dependencies are available; a process termination must not
            // discard the invitation callback.
            CompanionSharingCoordinator.persistAcceptedShare(metadata)
            return
        }
        Task { @MainActor in
            coordinator.enqueueAcceptedShare(
                metadata,
                startsNewPresentation: startsNewPresentation
            )
            if let container = modelContainer {
                let context = ModelContext(container)
                await coordinator.flushPendingAcceptedShares(in: context)
            }
        }
    }

    func deliverCompanionInviteURL(_ shareURL: URL) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            let presentationGeneration = companionCoordinator?.beginLoadingInvitation()
            do {
                try await CloudKitCompanionSharingService().ensureAccountAvailable()
                let metadata = try await CloudKitCompanionSharingService.fetchMetadataWithRootRecord(for: shareURL)
                if let presentationGeneration,
                   companionCoordinator?.isInvitePresentationActive(presentationGeneration) != true {
                    return
                }
                deliverAcceptedShare(metadata, startsNewPresentation: false)
            } catch {
                if let presentationGeneration,
                   companionCoordinator?.isInvitePresentationActive(presentationGeneration) != true {
                    return
                }
                CompanionDebugLog.write("deliverCompanionInviteURL failed: \(error)")
                companionCoordinator?.handleIncomingInviteFailure(error)
            }
        }
    }

    func noteDependenciesReady() {
        guard let coordinator = companionCoordinator else { return }
        coordinator.reloadPersistedAcceptedShares()
        Task { @MainActor in
            if let container = modelContainer {
                let context = ModelContext(container)
                await coordinator.flushPendingAcceptedShares(in: context)
            }
        }
    }

    func application(
        _ application: UIApplication,
        performActionFor shortcutItem: UIApplicationShortcutItem,
        completionHandler: @escaping (Bool) -> Void
    ) {
        if shortcutItem.type == "com.doublewaterapps.beforeshow.pro-discount" {
            Task { @MainActor in
                ProOfferDeepLinkRouter.shared.routeToPro(showWinbackOffer: true)
            }
            completionHandler(true)
        } else {
            completionHandler(false)
        }
    }
}

final class BeforeShowSceneDelegate: NSObject, UIWindowSceneDelegate {
    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        if let metadata = connectionOptions.cloudKitShareMetadata {
            deliver(metadata)
        }
        for activity in connectionOptions.userActivities
        where activity.activityType == NSUserActivityTypeBrowsingWeb {
            if let url = activity.webpageURL {
                deliver(url)
            }
        }
        for context in connectionOptions.urlContexts {
            deliver(context.url)
        }
        if let shortcutItem = connectionOptions.shortcutItem,
           shortcutItem.type == "com.doublewaterapps.beforeshow.pro-discount" {
            Task { @MainActor in
                ProOfferDeepLinkRouter.shared.routeToPro(showWinbackOffer: true)
            }
        }
    }

   func windowScene(
       _ windowScene: UIWindowScene,
       userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata
   ) {
       deliver(cloudKitShareMetadata)
   }

    func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
        guard userActivity.activityType == NSUserActivityTypeBrowsingWeb,
              let url = userActivity.webpageURL else {
            return
        }
        deliver(url)
    }

    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        for context in URLContexts {
            deliver(context.url)
        }
    }

    func windowScene(
        _ windowScene: UIWindowScene,
        performActionFor shortcutItem: UIApplicationShortcutItem,
        completionHandler: @escaping (Bool) -> Void
    ) {
        if shortcutItem.type == "com.doublewaterapps.beforeshow.pro-discount" {
            Task { @MainActor in
                ProOfferDeepLinkRouter.shared.routeToPro(showWinbackOffer: true)
            }
            completionHandler(true)
        } else {
            completionHandler(false)
        }
    }
    private func deliver(_ metadata: CKShare.Metadata) {
        guard let appDelegate = (UIApplication.shared.delegate as? BeforeShowAppDelegate) ?? BeforeShowAppDelegate.shared else {
            return
        }
        appDelegate.deliverAcceptedShare(metadata)
    }

    private func deliver(_ webpageURL: URL) {
        guard let shareURL = CompanionInviteWebLink.shareURL(from: webpageURL),
              let appDelegate = (UIApplication.shared.delegate as? BeforeShowAppDelegate) ?? BeforeShowAppDelegate.shared else {
            return
        }
        appDelegate.deliverCompanionInviteURL(shareURL)
    }
}
