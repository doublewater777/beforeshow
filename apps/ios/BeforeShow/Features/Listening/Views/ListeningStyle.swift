import SwiftUI

/// Physical material colors are feature-scoped; page chrome uses BS tokens.
enum ListeningStyle {
    static let lcdInk = Color(red: 0.19, green: 0.23, blue: 0.15)
    static let lcdTop = Color(red: 0.54, green: 0.60, blue: 0.46)
    static let lcdBottom = Color(red: 0.71, green: 0.75, blue: 0.59)
    static let woodEdge = Color(red: 0.42, green: 0.28, blue: 0.18)
    static let woodFace = Color(red: 0.28, green: 0.18, blue: 0.12)
    static let woodShadow = Color(red: 0.09, green: 0.06, blue: 0.04)
    static let sleeveSize: CGFloat = 78
    static let shelfHeight: CGFloat = 186
    static let shelfDiscSize: CGFloat = 74
    static let maximumStageScale: CGFloat = 0.94
    static let nowPlayingHeight: CGFloat = 56
    static let nowPlayingArtworkSize: CGFloat = 52
    static let sleeveWidth: CGFloat = 104
    static let sleeveHeight: CGFloat = 112
    static let compartmentWidth: CGFloat = 120
    static let dividerWidth: CGFloat = 4
    static let shelfFrame: CGFloat = 6
    static let shelfLip: CGFloat = 18
    static let woodHighlight = Color(red: 0.58, green: 0.40, blue: 0.26)
    static let woodBack = Color(red: 0.08, green: 0.05, blue: 0.035)
    static let caseHighlight = Color.white.opacity(0.32)
    static let caseShadow = Color.black.opacity(0.55)
}

struct ListeningDiscArtwork: View {
    var disc: ListeningDisc?
    var image = "listen_04_disc"
    @State private var artwork: UIImage?

    /// Compilation discs have no single cover; tile the first four track
    /// covers into one label image. Cached by track-artwork fingerprint.
    private static var mosaicCache: [String: UIImage] = [:]

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size.width
            ZStack {
                // Base CD texture asset
                Image(image)
                    .resizable()

                // Radial metallic holographic sheen / rainbow diffraction
                AngularGradient(
                    gradient: Gradient(colors: [
                        Color.clear,
                        Color.cyan.opacity(0.18),
                        Color.pink.opacity(0.16),
                        Color.yellow.opacity(0.15),
                        Color.clear,
                        Color.purple.opacity(0.18),
                        Color.cyan.opacity(0.16),
                        Color.clear
                    ]),
                    center: .center,
                    angle: .degrees(45)
                )
                .clipShape(Circle())
                .blendMode(.screen)

                // Album artwork printed on the label area, between hub and rim.
                if let artwork {
                    ZStack {
                        Image(uiImage: artwork)
                            .resizable()
                            .scaledToFill()
                        // Clear center mimics the unprinted hub ring of a real CD.
                        RadialGradient(
                            colors: [BSColor.Stage.surfaceRaised, BSColor.Stage.surfaceRaised.opacity(0.0)],
                            center: .center,
                            startRadius: 0,
                            endRadius: size * 0.10
                        )
                        Circle().stroke(Color.white.opacity(0.25), lineWidth: 1)
                            .frame(width: size * 0.19, height: size * 0.19)
                    }
                    .frame(width: size * 0.94, height: size * 0.94)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color.white.opacity(0.20), lineWidth: 1))
                }

                // High-contrast specular wedge highlights
                AngularGradient(
                    gradient: Gradient(stops: [
                        .init(color: .clear, location: 0.0),
                        .init(color: Color.white.opacity(0.35), location: 0.12),
                        .init(color: .clear, location: 0.25),
                        .init(color: .clear, location: 0.50),
                        .init(color: Color.white.opacity(0.30), location: 0.62),
                        .init(color: .clear, location: 0.75),
                        .init(color: .clear, location: 1.0)
                    ]),
                    center: .center,
                    angle: .degrees(30)
                )
                .clipShape(Circle())
                .blendMode(.screen)

                // Concentric data-track rings
                Circle()
                    .strokeBorder(Color.white.opacity(0.10), lineWidth: size * 0.18)
                    .padding(size * 0.15)

                // Spindle hub ring
                Circle()
                    .stroke(Color.white.opacity(0.25), lineWidth: 1.2)
                    .frame(width: size * 0.26, height: size * 0.26)

                // CD label title, only when no artwork covers the label
                if artwork == nil {
                    Text(disc?.title ?? "CD")
                        .font(.system(size: max(8, size * 0.045), weight: .semibold, design: .monospaced))
                        .foregroundStyle(ListeningStyle.lcdInk.opacity(0.9))
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .frame(width: size * 0.62)
                        .offset(y: -size * 0.24)
                }
            }
        }
        .task(id: disc?.artworkURL) {
            artwork = nil
            if let url = disc?.artworkURL {
                artwork = ShowCoverImageCache.shared.memoryImage(for: url)
                if artwork == nil {
                    artwork = await ShowCoverImageCache.shared.image(from: url)
                }
            } else if let disc, !disc.tracks.isEmpty {
                artwork = await Self.mosaic(for: disc)
            }
        }
    }

    private static func mosaic(for disc: ListeningDisc) async -> UIImage? {
        let urls = disc.tracks.compactMap(\.artworkURL).prefix(4)
        guard !urls.isEmpty else { return nil }
        let key = urls.map(\.absoluteString).joined(separator: "|")
        if let cached = mosaicCache[key] { return cached }
        var images: [UIImage] = []
        for url in urls {
            var image = ShowCoverImageCache.shared.memoryImage(for: url)
            if image == nil {
                image = await ShowCoverImageCache.shared.image(from: url)
            }
            if let image { images.append(image) }
        }
        guard !images.isEmpty else { return nil }
        let grid: Int = images.count > 1 ? 2 : 1
        let tile: CGFloat = 300
        let canvas = tile * CGFloat(grid)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let mosaic = UIGraphicsImageRenderer(size: CGSize(width: canvas, height: canvas), format: format).image { context in
            UIColor.black.setFill()
            context.fill(CGRect(x: 0, y: 0, width: canvas, height: canvas))
            for (index, image) in images.prefix(grid * grid).enumerated() {
                let origin = CGPoint(x: CGFloat(index % grid) * tile, y: CGFloat(index / grid) * tile)
                let side = min(image.size.width, image.size.height)
                let crop = CGRect(
                    x: (image.size.width - side) / 2 * image.scale,
                    y: (image.size.height - side) / 2 * image.scale,
                    width: side * image.scale,
                    height: side * image.scale
                )
                guard let cg = image.cgImage?.cropping(to: crop) else { continue }
                UIImage(cgImage: cg).draw(in: CGRect(origin: origin, size: CGSize(width: tile, height: tile)))
            }
        }
        mosaicCache[key] = mosaic
        return mosaic
    }
}

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
        GeometryReader { proxy in
            let size = proxy.size.width
            Group {
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    placeholder(size: size)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        }
        .task(id: url) {
            guard let url else { image = nil; return }
            if image == nil {
                image = ShowCoverImageCache.shared.memoryImage(for: url)
            }
            if image == nil {
                image = await ShowCoverImageCache.shared.image(from: url)
            }
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

struct ListeningFramesKey: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

extension View {
    func listeningFrame(_ name: String) -> some View {
        background(GeometryReader { proxy in
            Color.clear.preference(key: ListeningFramesKey.self, value: [name: proxy.frame(in: .named("listeningContent"))])
        })
    }
}

extension ListeningRoomCoordinator {
    func perform(_ control: CDControl) {
        CDSoundPlayer.shared.play("button")
        switch control {
        case .previous: skip(-1)
        case .next: skip(1)
        case .playPause: playPause()
        case .stop: stop()
        case .open: mechanism.setLid(open: (mechanism.motion.lid.target ?? mechanism.motion.lid.value) < 0.5)
        }
    }
}

struct ListeningArtistArtwork: View {
    let url: URL?
    let name: String
    @State private var image: UIImage?

    init(url: URL?, name: String) {
        self.url = url
        self.name = name
        _image = State(initialValue: url.flatMap { ShowCoverImageCache.shared.memoryImage(for: $0) })
    }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                GeometryReader { proxy in
                    ZStack {
                        BSColor.Stage.surfaceRaised
                        Text(String(name.prefix(1)))
                            .font(.system(size: proxy.size.width * 0.5, weight: .semibold))
                            .foregroundStyle(BSColor.Stage.muted)
                    }
                    .frame(width: proxy.size.width, height: proxy.size.height)
                }
            }
        }
        .clipped()
        .accessibilityHidden(true)
        .task(id: url) {
            guard let url else { image = nil; return }
            if image == nil {
                image = ShowCoverImageCache.shared.memoryImage(for: url)
            }
            if image == nil {
                image = await ShowCoverImageCache.shared.image(from: url)
            }
        }
    }
}
