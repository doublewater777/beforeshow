import SwiftUI

/// Refined disc cover presentation with physical micro-groove foil vinyl and sleeve depth.
struct ListeningDiscCover: View {
    let disc: ListeningDisc
    var show: Show?
    var body: some View {
        Group {
            switch disc.origin {
            case .album, .featuredPlaylist:
                ListeningArtwork(url: disc.artworkURL, title: disc.title)
            case .compilation:
                ListeningPlaylistArtwork(identity: .init(disc: disc, show: show))
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .background(BSColor.Stage.surfaceRaised)
        .clipShape(RoundedRectangle(cornerRadius: BSRadius.sm, style: .continuous))
        .overlay {
            // Cardboard spine subtle fold catch light
            LinearGradient(
                colors: [Color.white.opacity(0.25), Color.black.opacity(0.3), Color.clear],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .clipShape(RoundedRectangle(cornerRadius: BSRadius.sm, style: .continuous))
        }
        .overlay(
            RoundedRectangle(cornerRadius: BSRadius.sm, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: BSListeningTokens.hairline)
        )
        .compositingGroup()
        .shadow(color: Color.black.opacity(0.35), radius: 4, y: 2)
        .accessibilityHidden(true)
    }
}

/// A show playlist's cover: a color field with the show's artwork washed through it and
/// the playlist name set large, like an editorial Apple Music playlist. One cover for the
/// entry tile and the playlist page.
struct ListeningPlaylistArtwork: View {
    let identity: ListeningSleeveIdentity

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: .bottomLeading) {
                identity.color
                LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .topLeading, endPoint: .bottomTrailing)
                ListeningArtwork(url: identity.artworkURL, title: identity.title)
                    .frame(width: width, height: proxy.size.height)
                    .blendMode(.softLight)
                    .opacity(0.55)
                LinearGradient(colors: [.clear, .black.opacity(0.35)], startPoint: .center, endPoint: .bottom)
                Text(identity.title)
                    .font(.system(size: width * 0.15, weight: .heavy))
                    .tracking(-0.5)
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.6)
                    .padding(width * 0.08)
            }
            .clipped()
        }
    }
}
