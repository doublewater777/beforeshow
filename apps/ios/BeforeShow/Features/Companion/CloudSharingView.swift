import CloudKit
import LinkPresentation
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
    static func actionTitle(hasExistingShare: Bool) -> String {
        hasExistingShare
            ? BSLocalization.text("再次分享邀请")
            : BSLocalization.text("分享邀请")
    }
}

enum CompanionInviteWebLink {
    static let host = "beforeshow.doublewaterapps.com"
    static let path = "/join/"

    static func make(from shareURL: URL) -> URL? {
        guard shareURL.scheme?.lowercased() == "https" else { return nil }
        let token = Data(shareURL.absoluteString.utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        components.path = path
        components.fragment = "share=\(token)"
        return components.url
    }

    static func shareURL(from webURL: URL) -> URL? {
        guard webURL.scheme?.lowercased() == "https",
              webURL.host?.lowercased() == host,
              webURL.path == path || webURL.path == "/join",
              let fragment = URLComponents(url: webURL, resolvingAgainstBaseURL: false)?.fragment,
              fragment.hasPrefix("share=")
        else {
            return nil
        }

        var token = String(fragment.dropFirst("share=".count))
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let padding = (4 - token.count % 4) % 4
        token += String(repeating: "=", count: padding)
        guard let data = Data(base64Encoded: token),
              let value = String(data: data, encoding: .utf8),
              let shareURL = URL(string: value),
              shareURL.scheme?.lowercased() == "https"
        else {
            return nil
        }
        return shareURL
    }
}

private final class CompanionInviteActivityItemSource: NSObject, UIActivityItemSource {
    private let url: URL
    private let title: String

    init(url: URL, title: String) {
        self.url = url
        self.title = title
    }

    func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any {
        url
    }

    func activityViewController(
        _ activityViewController: UIActivityViewController,
        itemForActivityType activityType: UIActivity.ActivityType?
    ) -> Any? {
        url
    }

    func activityViewControllerLinkMetadata(
        _ activityViewController: UIActivityViewController
    ) -> LPLinkMetadata? {
        let metadata = LPLinkMetadata()
        metadata.title = title
        metadata.originalURL = url
        metadata.url = url
        return metadata
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

        guard let webURL = CompanionInviteWebLink.make(from: invitationURL) else {
            return false
        }
        let title = (share[CKShare.SystemFieldKey.title] as? String)
            ?? BSLocalization.text("同行邀请")
        let controller = UIActivityViewController(
            activityItems: [CompanionInviteActivityItemSource(url: webURL, title: title)],
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
