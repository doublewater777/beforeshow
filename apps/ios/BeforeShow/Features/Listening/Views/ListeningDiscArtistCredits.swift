import MusicKit
import SwiftUI

/// The disc's credited artists, each opening its Apple Music page. Two or three names
/// sit inline when they fit; more collapse into a menu.
struct ListeningDiscArtistCredits: View {
    let links: [ListeningDiscArtistLink]

    @Environment(\.openURL) private var openURL

    var body: some View {
        if links.count == 1, let link = links.first {
            artistButton(link)
        } else if links.count > 1 {
            ViewThatFits(in: .horizontal) {
                if links.count <= 3 {
                    HStack(spacing: BSSpacing.xs) {
                        ForEach(Array(links.enumerated()), id: \.element.id) { index, link in
                            if index > 0 {
                                Text("/")
                                    .foregroundStyle(BSColor.Stage.muted)
                                    .accessibilityHidden(true)
                            }
                            artistButton(link)
                        }
                    }
                    .fixedSize()
                }
                artistMenu
            }
        }
    }

    private var summary: String {
        links.count > 3
            ? ListeningCopy.format("%@ 等 %d 位艺人", links.prefix(2).map(\.name).joined(separator: " / "), links.count)
            : links.map(\.name).joined(separator: " / ")
    }

    private func artistButton(_ link: ListeningDiscArtistLink) -> some View {
        Button(link.name) { open(link) }
            .font(BSFont.body)
            .foregroundStyle(BSColor.Stage.accent)
            .lineLimit(1)
            .buttonStyle(.plain)
            .accessibilityLabel(BSLocalization.format("在 Apple Music 中查看 %@", link.name))
    }

    private var artistMenu: some View {
        Menu {
            ForEach(links) { link in
                Button(link.name) { open(link) }
            }
        } label: {
            HStack(spacing: BSSpacing.xs) {
                Text(summary)
                    .multilineTextAlignment(.center)
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
            }
            .font(BSFont.body)
            .foregroundStyle(BSColor.Stage.accent)
        }
    }

    private func open(_ link: ListeningDiscArtistLink) {
        Task {
            let storefront = await ListeningAppleMusicStorefront.current()
            if let url = link.appleMusicURL(storefront: storefront) {
                openURL(url)
            }
        }
    }
}

/// The listener's Apple Music storefront, falling back to the device region.
@MainActor enum ListeningAppleMusicStorefront {
    private static var resolved: String?

    static func current() async -> String? {
        if let resolved { return resolved }
        // Only the account storefront is remembered; the region fallback is re-read
        // so a later Music authorization still upgrades it.
        if MusicAuthorization.currentStatus == .authorized,
           let code = try? await MusicDataRequest.currentCountryCode {
            resolved = code
            return code
        }
        return Locale.autoupdatingCurrent.region?.identifier
    }
}
