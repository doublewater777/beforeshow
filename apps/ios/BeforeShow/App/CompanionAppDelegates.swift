import CloudKit
import Foundation
import SwiftData
import UIKit

final class BeforeShowAppDelegate: NSObject, UIApplicationDelegate {
    var companionCoordinator: CompanionSharingCoordinator?
    var modelContainer: ModelContainer?

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

    func deliverAcceptedShare(_ metadata: CKShare.Metadata) {
        guard let coordinator = companionCoordinator else {
            // Persist before dependencies are available; a process termination must not
            // discard the invitation callback.
            CompanionSharingCoordinator.persistAcceptedShare(metadata)
            return
        }
        Task { @MainActor in
            coordinator.enqueueAcceptedShare(metadata)
            if let container = modelContainer {
                let context = ModelContext(container)
                await coordinator.flushPendingAcceptedShares(in: context)
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
        guard let appDelegate = UIApplication.shared.delegate as? BeforeShowAppDelegate else {
            return
        }
        appDelegate.deliverAcceptedShare(metadata)
    }
}
