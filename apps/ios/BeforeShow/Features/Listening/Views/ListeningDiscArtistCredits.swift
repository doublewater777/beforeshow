import MusicKit
import SwiftUI

/// The disc's credited artists. Connected lineup artists open their in-app page; others open Apple Music.
/// Two or three names sit inline when they fit; more collapse into a menu.
struct ListeningDiscArtistCredits: View {
    let links: [ListeningDiscArtistLink]
    let room: ListeningRoomCoordinator

    @Environment(\.openURL) private var openURL
    @State private var profile: ArtistReference?

    var body: some View {
        credits
            .navigationDestination(item: $profile) { reference in
                ArtistProfileView(reference: reference, show: room.show, room: room)
            }
    }

    @ViewBuilder
    private var credits: some View {
        if links.count == 1, let link = links.first {
            artistButton(link)
        } else if links.count > 1 {
            ViewThatFits(in: .horizontal) {
                if links.count <= 3 {
                    HStack(spacing: BSSpacing.xs) {
                        ForEach(Array(links.enumerated()), id: \.element.id) { index, link in
                            if index > 0 {
                                Text(verbatim: "·")
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
            ? ListeningCopy.format("%@ 等 %d 位艺人", links[0].name, links.count)
            : links.map(\.name).joined(separator: " · ")
    }

    private func artistButton(_ link: ListeningDiscArtistLink) -> some View {
        Button { open(link) } label: {
            Text(link.name).font(ListeningOverviewStyle.caps(14)).tracking(2).textCase(.uppercase)
        }
            .foregroundStyle(BSColor.Stage.accent)
            .lineLimit(1)
            .buttonStyle(.plain)
    }

    private var artistMenu: some View {
        Menu {
            ForEach(links) { link in
                Button(link.name) { open(link) }
            }
        } label: {
            HStack(spacing: BSSpacing.xs) {
                Text(summary)
                    .font(ListeningOverviewStyle.caps(14)).tracking(2).textCase(.uppercase)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(BSColor.Stage.accent)
        }
    }

    private func open(_ link: ListeningDiscArtistLink) {
        if let artist = ListeningDiscArtistLinks.lineupArtist(for: link, in: room.browseArtists) {
            profile = ArtistReference(browseArtist: artist, show: room.show)
            return
        }
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
