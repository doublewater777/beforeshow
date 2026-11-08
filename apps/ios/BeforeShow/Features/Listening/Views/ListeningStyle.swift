import SwiftUI

/// Physical material colors are feature-scoped; page chrome uses BS tokens.
enum ListeningStyle {
    static let lcdInk = Color(red: 0.19, green: 0.23, blue: 0.15)
    static let lcdTop = Color(red: 0.54, green: 0.60, blue: 0.46)
    static let lcdBottom = Color(red: 0.71, green: 0.75, blue: 0.59)
    static let sleeveSize: CGFloat = 78
    static let rackFloorFront = Color(red: 0.17, green: 0.13, blue: 0.125)
    static let rackFloorBack = Color(red: 0.07, green: 0.06, blue: 0.063)
    static let rackFloorMid = Color(red: 0.09, green: 0.067, blue: 0.07)
    static let rackCaseBack = Color(red: 0.05, green: 0.043, blue: 0.04)
    static let rackPlaceholder = BSColor.Stage.surfaceRaised
    static let rackLipTop = Color(red: 0.23, green: 0.19, blue: 0.17)
    static let rackLipBottom = Color(red: 0.13, green: 0.106, blue: 0.098)
    static let rackLight = Color(red: 1, green: 0.925, blue: 0.84)
    static let liveSpine = Color(red: 0.08, green: 0.067, blue: 0.05)
    static let plateTop = Color(red: 0.18, green: 0.15, blue: 0.137)
    static let plateBottom = Color(red: 0.106, green: 0.086, blue: 0.082)
    static let plateInk = Color(red: 0.937, green: 0.89, blue: 0.8)
}

/// The clear clamping ring and centre hole of a CD, kept small so the disc reads first.
struct ListeningDiscHub: View {
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.white.opacity(0.16))
                .overlay(Circle().stroke(Color.white.opacity(0.32), lineWidth: 0.75))
                .frame(width: size * 0.1, height: size * 0.1)
            Circle()
                .fill(Color(white: 0.62))
                .overlay(Circle().stroke(Color.black.opacity(0.18), lineWidth: 0.5))
                .frame(width: size * 0.03, height: size * 0.03)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

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
