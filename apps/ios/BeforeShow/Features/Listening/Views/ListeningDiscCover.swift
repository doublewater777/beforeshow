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
            case let .compilation(_, number):
                ListeningCompilationJacket(identity: .init(disc: disc, show: show), number: number)
            }
        }
        .aspectRatio(1, contentMode: .fit)
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
        .shadow(color: Color.black.opacity(0.45), radius: 5, y: 3)
        .accessibilityHidden(true)
    }
}

private struct ListeningCompilationJacket: View {
    let identity: ListeningSleeveIdentity
    let number: Int

    var body: some View {
        GeometryReader { proxy in
            let inset = proxy.size.width * BSListeningTokens.sleeveInsetFraction
            ZStack(alignment: .bottomLeading) {
                identity.color
                ListeningSleeveImage(url: identity.artworkURL)
                    .padding(inset)
                VStack(alignment: .leading, spacing: BSSpacing.xs) {
                    Text(String(format: "%02d", number))
                        .font(.system(size: proxy.size.width * BSListeningTokens.sleeveNumberFraction,
                                      weight: .bold, design: .rounded))
                        .padding(BSSpacing.xs)
                        .background(BSListeningTokens.paper)
                    Spacer(minLength: 0)
                    Text(identity.title)
                        .font(.system(size: proxy.size.width * BSListeningTokens.sleeveTitleFraction,
                                      weight: .semibold))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(inset)
                        .background(BSListeningTokens.paper.opacity(BSListeningTokens.paperOpacity))
                }
                .foregroundStyle(BSListeningTokens.ink)
                .padding(inset)
            }
            .clipped()
        }
    }
}

struct ListeningSleeveImage: View {
    let url: URL?
    @State private var image: UIImage?

    init(url: URL?) {
        self.url = url
        _image = State(initialValue: url.flatMap { ShowCoverImageCache.shared.memoryImage(for: $0) })
    }

    var body: some View {
        GeometryReader { proxy in
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
                    .frame(width: proxy.size.width, height: proxy.size.height).clipped()
            }
        }
        .task(id: url) {
            guard let url else { image = nil; return }
            if image == nil {
                image = ShowCoverImageCache.shared.memoryImage(for: url)
            }
            if image == nil {
                let loaded = await ShowCoverImageCache.shared.image(from: url)
                guard !Task.isCancelled else { return }
                image = loaded
            }
        }
    }
}

