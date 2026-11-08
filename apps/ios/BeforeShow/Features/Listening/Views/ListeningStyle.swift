import SwiftUI

/// Hinge strip and a single plastic glare over a cover, read as a jewel case.
/// Missing covers get a deterministic typographic sleeve, never pretend artwork.
struct ListeningArtwork: View {
    let url: URL?
    var title = "BeforeShow"
    @State private var image: UIImage?

    init(url: URL?, title: String = "BeforeShow") {
        self.url = url
        self.title = title
        _image = State(initialValue: url.flatMap { ShowCoverImageCache.shared.memoryImage(for: $0) })
    }

    private var tone: Color {
        let palette = [BSColor.Stage.glowBlue, BSColor.Stage.prepare, BSColor.Stage.accent, BSColor.Stage.success]
        return palette[title.utf8.reduce(0) { ($0 + Int($1)) % palette.count }]
    }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                GeometryReader { proxy in
                    placeholder(size: proxy.size.width)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                }
            }
        }
        .clipped()
        .task(id: url) {
            guard let url else { image = nil; return }
            // A new URL replaces the old picture only once its own image is ready.
            if let cached = ShowCoverImageCache.shared.memoryImage(for: url) {
                image = cached
                return
            }
            let loaded = await ShowCoverImageCache.shared.image(from: url)
            if !Task.isCancelled { image = loaded }
        }
    }

    @ViewBuilder
    private func placeholder(size: CGFloat) -> some View {
        ZStack {
            LinearGradient(colors: [tone.opacity(0.65), BSColor.Stage.surface], startPoint: .topLeading, endPoint: .bottomTrailing)
            // Concentric acoustic soundwaves / vinyl grooves
            ZStack {
                ForEach(0..<6) { index in
                    Circle().stroke(tone.opacity(0.18 + Double(index) * 0.04), lineWidth: 1)
                        .padding(CGFloat(index) * size * 0.06 + 8)
                }
            }
            Circle()
                .stroke(BSColor.Stage.accent.opacity(0.4), lineWidth: 1.5)
                .frame(width: size * 0.32, height: size * 0.32)
            Circle()
                .fill(BSColor.Stage.surfaceRaised.opacity(0.85))
                .frame(width: size * 0.22, height: size * 0.22)
        }
    }
}

struct ListeningArtistArtwork: View {
    let url: URL?
    let name: String
    var size: CGFloat? = nil
    @State private var image: UIImage?

    init(url: URL?, name: String, size: CGFloat? = nil) {
        self.url = url
        self.name = name
        self.size = size
        _image = State(initialValue: url.flatMap { ShowCoverImageCache.shared.memoryImage(for: $0) })
    }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                ZStack {
                    BSColor.Stage.surfaceRaised
                    Text(String(name.prefix(1)))
                        .font(.system(size: (size ?? BSListeningTokens.avatar) * 0.48, weight: .semibold))
                        .foregroundStyle(BSColor.Stage.muted)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .clipped()
        .accessibilityHidden(true)
        .task(id: url) {
            guard let url else { image = nil; return }
            // A new URL replaces the old picture only once its own image is ready.
            if let cached = ShowCoverImageCache.shared.memoryImage(for: url) {
                image = cached
                return
            }
            let loaded = await ShowCoverImageCache.shared.image(from: url)
            if !Task.isCancelled { image = loaded }
        }
    }
}
