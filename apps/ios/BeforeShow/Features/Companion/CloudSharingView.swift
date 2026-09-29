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
            ? BSLocalization.text("再次邀请")
            : BSLocalization.text("邀请朋友")
    }
}

enum CompanionInviteWebLink {
    static let host = "beforeshow.doublewaterapps.com"
    static let path = "/join/"

    private struct Payload: Codable {
        let v: Int
        let u: String
        let n: String
        let t: Int64
        let z: String?
        let s: Int?
        let l: String?
        let o: String?
        let c: String?
    }

    static func make(
        from shareURL: URL,
        show: CompanionShowSnapshot,
        ownerName: String?
    ) -> URL? {
        guard validShareURL(shareURL) else { return nil }
        let location = [show.venueName, show.city]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
        let coverURL: String? = {
            guard let raw = show.coverImageURL?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !raw.isEmpty,
                  let url = URL(string: raw),
                  let scheme = url.scheme?.lowercased(),
                  scheme == "https" || scheme == "http",
                  raw.count <= 1000 else {
                return nil
            }
            return raw
        }()
        let payload = Payload(
            v: 1,
            u: shareURL.absoluteString,
            n: String(show.showName.prefix(200)),
            t: Int64(show.showStartTime.timeIntervalSince1970),
            z: show.timeZoneIdentifier.flatMap { TimeZone(identifier: $0) == nil ? nil : $0 },
            s: show.timeZoneSecondsFromGMT,
            l: (location.isEmpty ? show.showLocation : location).map { String($0.prefix(240)) },
            o: ownerName.map { String($0.trimmingCharacters(in: .whitespacesAndNewlines).prefix(100)) },
            c: coverURL
        )
        guard let data = try? JSONEncoder().encode(payload) else { return nil }
        let token = data
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        components.path = path + token
        return components.url
    }

    static func shareURL(from webURL: URL) -> URL? {
        let isWebLink = webURL.scheme?.lowercased() == "https"
            && webURL.host?.lowercased() == host
        let isAppLink = webURL.scheme?.lowercased() == "beforeshow"
            && webURL.host?.lowercased() == "join"
        guard isWebLink || isAppLink,
              webURL.query == nil,
              webURL.fragment == nil else { return nil }
        let token: String
        if isWebLink {
            guard webURL.path.hasPrefix(path) else { return nil }
            token = String(webURL.path.dropFirst(path.count))
        } else {
            token = String(webURL.path.dropFirst())
        }
        guard !token.isEmpty, token.count < 8_192,
              token.range(of: "^[A-Za-z0-9_-]+$", options: .regularExpression) != nil else {
            return nil
        }
        var padded = token
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        padded += String(repeating: "=", count: (4 - padded.count % 4) % 4)
        guard let data = Data(base64Encoded: padded),
              let payload = try? JSONDecoder().decode(Payload.self, from: data),
              payload.v == 1,
              let shareURL = URL(string: payload.u),
              validShareURL(shareURL)
        else {
            return nil
        }
        return shareURL
    }

    private static func validShareURL(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https", let host = url.host?.lowercased() else {
            return false
        }
        let isValidHost = host == "icloud.com"
            || host.hasSuffix(".icloud.com")
            || host == "icloud.com.cn"
            || host.hasSuffix(".icloud.com.cn")
            || host == "apple.com"
            || host.hasSuffix(".apple.com")
        let hasValidPath = url.path.hasPrefix("/share/") || host.contains("share.")
        return isValidHost && hasValidPath
    }
}

private final class CompanionInviteActivityItemSource: NSObject, UIActivityItemSource {
    private let url: URL
    private let title: String
    private let coverImage: UIImage?

    init(url: URL, title: String, coverImage: UIImage? = nil) {
        self.url = url
        self.title = title
        self.coverImage = coverImage
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

        if let coverImage {
            metadata.imageProvider = NSItemProvider(object: coverImage)
        }

        let appLogo = UIImage(named: "AppLogo")
            ?? UIImage(named: "AppIcon")
            ?? (Bundle.main.infoDictionary?["CFBundleIcons"] as? [String: Any])
                .flatMap { $0["CFBundlePrimaryIcon"] as? [String: Any] }
                .flatMap { $0["CFBundleIconFiles"] as? [String] }
                .flatMap { $0.last }
                .flatMap { UIImage(named: $0) }

        if let appLogo {
            metadata.iconProvider = NSItemProvider(object: appLogo)
        } else if let coverImage {
            metadata.iconProvider = NSItemProvider(object: coverImage)
        }

        return metadata
    }
}

/// Distributes a BeforeShow invitation that carries the stable `CKShare.url`.
/// We intentionally do not present `UICloudSharingController`: that controller also
/// exposes participant removal, stop-sharing and leave-share controls, while the
/// BeforeShow companion product only exposes joining and re-sharing the same invite.
@MainActor
enum SystemCloudSharePresenter {
    @discardableResult
    static func present(
        shareData: Data,
        show: CompanionShowSnapshot,
        containerIdentifier: String,
        coverImage: UIImage? = nil,
        onEvent: @escaping (CloudSharingControllerEvent, CKShare?, Error?) -> Void,
        onDismiss: @escaping () -> Void,
        onPresented: (() -> Void)? = nil
    ) -> Bool {
        guard let share = try? CloudKitCompanionSharingService.unarchiveShare(from: shareData) else {
            CompanionDebugLog.write("CompanionShare: unarchive share failed (bytes=\(shareData.count))")
            return false
        }
        return present(
            share: share,
            show: show,
            container: CKContainer(identifier: containerIdentifier),
            coverImage: coverImage,
            onEvent: onEvent,
            onDismiss: onDismiss,
            onPresented: onPresented
        )
    }

    @discardableResult
    static func present(
        share: CKShare,
        show: CompanionShowSnapshot,
        container _: CKContainer,
        coverImage: UIImage? = nil,
        onEvent _: @escaping (CloudSharingControllerEvent, CKShare?, Error?) -> Void,
        onDismiss: @escaping () -> Void,
        onPresented: (() -> Void)? = nil
    ) -> Bool {
        guard let invitationURL = share.url,
              let presenter = SystemPNGSharePresenter.topViewController() else {
            CompanionDebugLog.write("CompanionShare: missing invitationURL or topViewController")
            return false
        }
        if presenter is UIActivityViewController {
            return false
        }

        let ownerName = CompanionUserProfile.nickname ?? share.currentUserParticipant.flatMap {
            CloudKitCompanionSharingService.displayName(for: $0)
        }
        guard let webURL = CompanionInviteWebLink.make(
            from: invitationURL,
            show: show,
            ownerName: ownerName
        ) else {
            CompanionDebugLog.write("CompanionShare: CompanionInviteWebLink.make failed for url=\(invitationURL)")
            return false
        }
        let title = BSLocalization.format("一起去 %@", show.showName)
        let resolvedCoverImage: UIImage? = coverImage ?? {
            guard let raw = show.coverImageURL, let url = URL(string: raw) else { return nil }
            if url.isFileURL, let data = try? Data(contentsOf: url) {
                return UIImage(data: data)
            }
            return ShowCoverImageCache.shared.memoryImage(for: url)
        }()
        let controller = UIActivityViewController(
            activityItems: [CompanionInviteActivityItemSource(url: webURL, title: title, coverImage: resolvedCoverImage)],
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
