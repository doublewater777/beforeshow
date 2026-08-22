import CloudKit
import SwiftUI
import UIKit

/// Events from system `UICloudSharingController` that the coordinator must reconcile.
enum CloudSharingControllerEvent: Equatable {
    case didSave
    case didStopSharing
    case failedToSave
}

enum CompanionInviteGate {
    /// Discovery / refresh errors must not block a brand-new invite, except missing iCloud.
    static func blocksNewInvite(_ error: CompanionSharingError?) -> Bool {
        error == .iCloudAccountUnavailable
    }
}

enum CompanionInvitePreparingPresentation {
    static var overlayTitle: String {
        BSLocalization.text("正在打开系统分享")
    }

    static func primaryActionTitle(isPreparing: Bool, isRetry: Bool) -> String {
        if isPreparing {
            return BSLocalization.text("正在准备邀请")
        }
        return isRetry
            ? BSLocalization.text("重新邀请")
            : BSLocalization.text("分享邀请")
    }
}

/// Presents `UICloudSharingController` from the top UIKit controller.
/// Embedding it as a SwiftUI `fullScreenCover` root dismisses the share sheet as soon
/// as the system presents its own activity UI.
@MainActor
enum SystemCloudSharePresenter {
    private static var activeSession: Session?

    @discardableResult
    static func present(
        shareData: Data,
        containerIdentifier: String,
        onEvent: @escaping (CloudSharingControllerEvent, CKShare?, Error?) -> Void,
        onDismiss: @escaping () -> Void,
        onPresented: (() -> Void)? = nil
    ) -> Bool {
        guard let share = try? CloudKitCompanionSharingService.unarchiveShare(from: shareData) else {
            return false
        }
        return present(
            share: share,
            container: CKContainer(identifier: containerIdentifier),
            onEvent: onEvent,
            onDismiss: onDismiss,
            onPresented: onPresented
        )
    }

    @discardableResult
    static func present(
        share: CKShare,
        container: CKContainer,
        onEvent: @escaping (CloudSharingControllerEvent, CKShare?, Error?) -> Void,
        onDismiss: @escaping () -> Void,
        onPresented: (() -> Void)? = nil
    ) -> Bool {
        guard let presenter = SystemPNGSharePresenter.topViewController() else {
            return false
        }
        if presenter is UICloudSharingController {
            return false
        }

        let session = Session(onEvent: onEvent, onDismiss: onDismiss)
        activeSession = session

        let controller = UICloudSharingController(share: share, container: container)
        controller.delegate = session
        controller.availablePermissions = [.allowReadWrite, .allowPrivate]
        controller.presentationController?.delegate = session
        if let popover = controller.popoverPresentationController {
            popover.sourceView = presenter.view
            popover.sourceRect = CGRect(
                x: presenter.view.bounds.midX,
                y: presenter.view.bounds.maxY - 20,
                width: 1,
                height: 1
            )
        }
        presenter.present(controller, animated: true, completion: onPresented)
        return true
    }

    private final class Session: NSObject, UICloudSharingControllerDelegate, UIAdaptivePresentationControllerDelegate {
        var onEvent: (CloudSharingControllerEvent, CKShare?, Error?) -> Void
        var onDismiss: () -> Void
        private(set) var isFinished = false

        init(
            onEvent: @escaping (CloudSharingControllerEvent, CKShare?, Error?) -> Void,
            onDismiss: @escaping () -> Void
        ) {
            self.onEvent = onEvent
            self.onDismiss = onDismiss
        }

        func cloudSharingControllerDidSaveShare(_ csc: UICloudSharingController) {
            onEvent(.didSave, csc.share, nil)
        }

        func cloudSharingControllerDidStopSharing(_ csc: UICloudSharingController) {
            onEvent(.didStopSharing, csc.share, nil)
            finish()
        }

        func cloudSharingController(
            _ csc: UICloudSharingController,
            failedToSaveShareWithError error: Error
        ) {
            onEvent(.failedToSave, csc.share, error)
        }

        func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
            finish()
        }

        func itemThumbnailData(for csc: UICloudSharingController) -> Data? { nil }

        func itemTitle(for csc: UICloudSharingController) -> String? {
            csc.share?[CKShare.SystemFieldKey.title] as? String
        }

        private func finish() {
            guard !isFinished else { return }
            isFinished = true
            let dismiss = onDismiss
            onEvent = { _, _, _ in }
            onDismiss = {}
            SystemCloudSharePresenter.activeSession = nil
            dismiss()
        }
    }
}
