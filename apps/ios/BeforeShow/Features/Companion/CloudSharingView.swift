import CloudKit
import SwiftUI
import UIKit

/// Events retained for compatibility with the companion coordinator callback surface.
/// Invite distribution itself no longer opens CloudKit's participant-management UI.
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

/// Distributes the stable `CKShare.url` through the ordinary system activity sheet.
/// We intentionally do not present `UICloudSharingController`: that controller also
/// exposes participant removal, stop-sharing and leave-share controls, while the
/// BeforeShow companion product only exposes joining and re-sharing the same invite.
@MainActor
enum SystemCloudSharePresenter {
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
        container _: CKContainer,
        onEvent _: @escaping (CloudSharingControllerEvent, CKShare?, Error?) -> Void,
        onDismiss: @escaping () -> Void,
        onPresented: (() -> Void)? = nil
    ) -> Bool {
        guard let invitationURL = share.url,
              let presenter = SystemPNGSharePresenter.topViewController() else {
            return false
        }
        if presenter is UIActivityViewController {
            return false
        }

        let controller = UIActivityViewController(
            activityItems: [invitationURL],
            applicationActivities: nil
        )
        controller.completionWithItemsHandler = { _, _, _, _ in
            Task { @MainActor in
                onDismiss()
            }
        }
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
}
