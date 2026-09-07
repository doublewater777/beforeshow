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

                // CD label title
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
}

/// Missing covers get a deterministic typographic sleeve, never pretend artwork.
struct ListeningArtwork: View {
    let url: URL?
    var title = "BeforeShow"
    private var tone: Color {
        let palette = [BSColor.Stage.glowBlue, BSColor.Stage.prepare, BSColor.Stage.accent, BSColor.Stage.success]
        return palette[title.utf8.reduce(0) { ($0 + Int($1)) % palette.count }]
    }
    var body: some View {
        GeometryReader { proxy in
            AsyncImage(url: url) { image in image.resizable().scaledToFill() } placeholder: {
                ZStack(alignment: .bottomLeading) {
                    LinearGradient(colors: [tone.opacity(0.75), BSColor.Stage.surface], startPoint: .topLeading, endPoint: .bottomTrailing)
                    ZStack {
                        ForEach(0..<8) { index in
                            Circle().stroke(tone.opacity(0.35), lineWidth: 1)
                                .padding(CGFloat(index) * proxy.size.width * 0.035)
                        }
                    }.frame(width: proxy.size.width * 1.15, height: proxy.size.width * 1.15)
                        .offset(x: proxy.size.width * 0.23, y: -proxy.size.height * 0.22)
                    VStack(alignment: .leading, spacing: BSSpacing.sm) {
                        Text("BEFORESHOW").font(.system(size: max(7, proxy.size.width * 0.045), weight: .medium, design: .monospaced)).tracking(2)
                        Spacer()
                        Text(title).font(.system(size: max(14, proxy.size.width * 0.13), weight: .semibold)).lineLimit(3)
                        Rectangle().fill(BSColor.Stage.accent).frame(width: proxy.size.width * 0.18, height: 2)
                    }.padding(proxy.size.width * 0.1)
                        .foregroundStyle(BSColor.Stage.heroIvory)
                }
            }.frame(width: proxy.size.width, height: proxy.size.height).clipped()
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
            Color.clear.preference(key: ListeningFramesKey.self, value: [name: proxy.frame(in: .named("listeningRoom"))])
        })
    }
}

extension ListeningRoomCoordinator {
    func perform(_ control: CDControl) {
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
    var body: some View {
        AsyncImage(url: url) { image in image.resizable().scaledToFill() } placeholder: {
            ZStack {
                BSColor.Stage.surfaceRaised
                Text(String(name.prefix(1))).font(.largeTitle).foregroundStyle(BSColor.Stage.muted)
            }
        }.clipped().accessibilityHidden(true)
    }
}
