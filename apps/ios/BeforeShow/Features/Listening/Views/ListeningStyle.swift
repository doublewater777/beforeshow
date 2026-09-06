import SwiftUI

/// Physical material colors are feature-scoped; page chrome uses BS tokens.
enum ListeningStyle {
    static let lcdInk = Color(red: 0.19, green: 0.23, blue: 0.15)
    static let lcdTop = Color(red: 0.54, green: 0.60, blue: 0.46)
    static let lcdBottom = Color(red: 0.71, green: 0.75, blue: 0.59)
    static let woodEdge = Color(red: 0.47, green: 0.33, blue: 0.23)
    static let woodFace = Color(red: 0.32, green: 0.22, blue: 0.16)
    static let woodShadow = Color(red: 0.13, green: 0.09, blue: 0.07)
    static let sleeveSize: CGFloat = 124
    static let shelfHeight: CGFloat = 190
    static let shelfDiscSize: CGFloat = 110
    static let maximumStageScale: CGFloat = 0.72
    static let nowPlayingHeight: CGFloat = 72
}

struct ListeningDiscArtwork: View {
    var disc: ListeningDisc?
    var image = "listen_04_disc"
    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size.width
            ZStack {
                Image(image).resizable()
                Text(disc?.title ?? "CD")
                    .font(.system(size: size * 0.037, weight: .semibold, design: .monospaced))
                    .foregroundStyle(ListeningStyle.lcdInk)
                    .lineLimit(2).multilineTextAlignment(.center)
                    .frame(width: size * 0.65).offset(y: -size * 0.25)
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
