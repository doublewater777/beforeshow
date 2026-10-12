import SwiftUI
import simd

/// What a standing case shows; `nil` content is a blank case waiting for its catalog.
struct ListeningRackCaseContent: Equatable {
    var disc: ListeningDisc?
    var title: String
    var artworkURL: URL?
    var isLive = false
    var isPlaceholder = false
    var marked = false
    var showsDisc = false
}

/// One jewel case drawn as a real box under the shelf's shared camera.
struct ListeningRackCase: View, Animatable {
    var pose: ListeningRackPose
    let content: ListeningRackCaseContent
    let width: CGFloat
    var show: Show?

    nonisolated var animatableData: ListeningRackPose {
        get { pose }
        set { pose = newValue }
    }

    private typealias L = ListeningRackLayout
    private typealias P = ListeningRackProjector

    var body: some View {
        let box = P(width: width).box(pose)
        let size = L.caseSize
        ZStack(alignment: .topLeading) {
            face(box * ListeningRackFace.back, CGSize(width: L.spine, height: size)) {
                ListeningStyle.rackCaseBack
            }
            if let disc = content.disc {
                face(box * ListeningRackFace.disc(peek: pose.peek), CGSize(width: L.discSize, height: L.discSize), culled: false) {
                    ListeningPeekingDisc(disc: disc, size: L.discSize)
                        .id(disc.id)
                }
                .opacity(content.showsDisc ? 1 : 0)
            }
            face(box * ListeningRackFace.left, CGSize(width: size, height: size)) {
                cover
                    .overlay(LinearGradient(colors: [.black.opacity(0.55), .black.opacity(0.05)], startPoint: .leading, endPoint: .trailing))
            }
            face(box * ListeningRackFace.right, CGSize(width: size, height: size)) {
                cover
                    .overlay(Rectangle().fill(LinearGradient(colors: [.black.opacity(0.05), .black.opacity(0.55)], startPoint: .leading, endPoint: .trailing)).opacity(1 - pose.lit))
                    .overlay(alignment: .leading) {
                        LinearGradient(
                            stops: [.init(color: .white.opacity(0.18), location: 0), .init(color: .white.opacity(0.05), location: 0.75), .init(color: .black.opacity(0.28), location: 1)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: 10)
                        .overlay(alignment: .trailing) { Rectangle().fill(.white.opacity(0.1)).frame(width: 1).offset(x: 1) }
                    }
                    .overlay(
                        LinearGradient(
                            stops: [.init(color: .white.opacity(0.2), location: 0), .init(color: .white.opacity(0.05), location: 0.32), .init(color: .clear, location: 0.33)],
                            startPoint: UnitPoint(x: -0.1, y: 0.18),
                            endPoint: UnitPoint(x: 1.1, y: 0.82)
                        )
                    )
                    .overlay(Rectangle().strokeBorder(.white.opacity(0.16), lineWidth: 1))
                    .shadow(color: .black.opacity(0.6 * pose.lit), radius: 20, y: 24)
            }
            face(box, CGSize(width: L.spine, height: size)) {
                ListeningRackSpine(content: content)
            }
        }
        .frame(width: width, height: L.canvasHeight, alignment: .topLeading)
        .opacity(pose.opacity)
        .allowsHitTesting(false)
    }

    /// Re-identified per disc so a case that now holds another album reloads its artwork.
    private var cover: some View {
        coverArt
            .id(content.disc?.id ?? content.artworkURL?.absoluteString ?? content.title)
            .background(ListeningStyle.rackCaseBack)
    }

    @ViewBuilder
    private var coverArt: some View {
        if content.isPlaceholder {
            ListeningStyle.rackPlaceholder
        } else if let disc = content.disc {
            switch disc.origin {
            case .album, .featuredPlaylist:
                ListeningArtwork(url: disc.artworkURL, title: disc.title)
            case let .compilation(_, number):
                ListeningCompilationJacket(identity: .init(disc: disc, show: show), number: number)
            }
        } else {
            ListeningArtwork(url: content.artworkURL, title: content.title)
        }
    }

    private func face<Content: View>(
        _ transform: simd_double4x4,
        _ size: CGSize,
        culled: Bool = true,
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .frame(width: size.width, height: size.height)
            .projectionEffect(P.effect(transform))
            .opacity(!culled || P.faces(transform, size: size) ? 1 : 0)
    }
}

/// Spine label set vertically: CJK stays upright, Latin runs turn on their side.
private struct ListeningRackSpine: View {
    let content: ListeningRackCaseContent
    @State private var tone: UIColor?

    private var toneURL: URL? { content.disc?.artworkURL ?? content.artworkURL }

    private var style: (fill: Color, ink: Color) {
        if content.isPlaceholder { return (ListeningStyle.rackPlaceholder, .clear) }
        if content.isLive { return (ListeningStyle.liveSpine, BSColor.Stage.accent) }
        guard let tone else { return (BSColor.Stage.surfaceRaised, BSColor.Stage.foreground.opacity(0.86)) }
        let spine = ListeningArtworkTone.spine(for: tone)
        return (Color(uiColor: spine.fill), spine.isLight ? BSColor.Stage.background : BSColor.Stage.foreground.opacity(0.92))
    }

    var body: some View {
        let style = style
        Rectangle()
            .fill(style.fill)
            .overlay { ListeningVerticalLabel(text: content.title, maxLength: 104).foregroundStyle(style.ink) }
            .overlay(alignment: .top) { Rectangle().fill(.black.opacity(0.18)).frame(height: 6) }
            .overlay(alignment: .bottom) { Rectangle().fill(.black.opacity(0.18)).frame(height: 6) }
            .overlay(alignment: .leading) { Rectangle().fill(.white.opacity(0.22)).frame(width: 1) }
            .overlay(alignment: .trailing) { Rectangle().fill(.black.opacity(0.35)).frame(width: 1) }
            .overlay(alignment: .topLeading) {
                if content.marked {
                    RoundedRectangle(cornerRadius: 1).fill(BSColor.Stage.accent).frame(width: 6, height: 6).offset(x: 6, y: 10)
                }
            }
            .task(id: toneURL) {
                tone = ListeningArtworkTone.cached(toneURL)
                if tone == nil, let toneURL { tone = await ListeningArtworkTone.tone(for: toneURL) }
            }
    }
}

private struct ListeningVerticalLabel: View {
    let text: String
    let maxLength: CGFloat

    private static let font = UIFont.systemFont(ofSize: 9, weight: .bold)
    private static let tracking: CGFloat = 1

    private enum Run: Hashable {
        case upright(String)
        case sideways(String, length: CGFloat)
    }

    private static func isUpright(_ c: Character) -> Bool {
        c.unicodeScalars.contains { (0x2E80...0x9FFF).contains($0.value) || (0xAC00...0xD7AF).contains($0.value) || (0xF900...0xFAFF).contains($0.value) || (0xFF00...0xFFEF).contains($0.value) }
    }

    private static func length(_ s: String) -> CGFloat {
        ceil((s as NSString).size(withAttributes: [.font: font, .kern: tracking]).width)
    }

    private var runs: [Run] {
        var segments: [(text: String, upright: Bool)] = []
        for c in text {
            let upright = Self.isUpright(c)
            if let last = segments.last, !last.upright, !upright {
                segments[segments.count - 1].text.append(c)
            } else {
                segments.append((String(c), upright))
            }
        }
        let advance = Self.font.pointSize + Self.tracking
        var runs: [Run] = [], used: CGFloat = 0
        for segment in segments {
            if segment.upright {
                guard used + advance <= maxLength else { runs.append(.upright("…")); break }
                runs.append(.upright(segment.text))
                used += advance
                continue
            }
            let latin = segment.text.trimmingCharacters(in: .whitespaces)
            guard !latin.isEmpty else { continue }
            if used + Self.length(latin) <= maxLength {
                runs.append(.sideways(latin, length: Self.length(latin)))
                used += Self.length(latin)
                continue
            }
            var cut = latin
            while !cut.isEmpty, used + Self.length(cut + "…") > maxLength { cut.removeLast() }
            if !cut.isEmpty { runs.append(.sideways(cut + "…", length: Self.length(cut + "…"))) }
            break
        }
        return runs
    }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(runs.enumerated()), id: \.offset) { _, run in
                switch run {
                case let .upright(s):
                    Text(s).frame(height: Self.font.pointSize + Self.tracking)
                case let .sideways(s, length):
                    Text(s)
                        .tracking(Self.tracking)
                        .fixedSize()
                        .rotationEffect(.degrees(90))
                        .frame(width: ListeningRackLayout.spine, height: length)
                }
            }
        }
        .font(Font(Self.font))
        .lineLimit(1)
    }
}

/// The shelf the cases stand on: a floor receding to the camera and a front lip.
struct ListeningRackFloor: View {
    let width: CGFloat

    private typealias P = ListeningRackProjector

    var body: some View {
        let stage = P(width: width).stage
        let floor = stage * P.translate(-700, -168) * P.translate(700, 300) * P.rotateX(90) * P.translate(-700, -300)
        let lip = stage * P.translate(-700, Double(ListeningRackLayout.caseSize), 1)
        ZStack(alignment: .topLeading) {
            LinearGradient(
                stops: [
                    .init(color: ListeningStyle.rackFloorBack, location: 0),
                    .init(color: ListeningStyle.rackFloorMid, location: 0.45),
                    .init(color: ListeningStyle.rackFloorFront, location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .overlay {
                EllipticalGradient(
                    stops: [.init(color: ListeningStyle.rackLight.opacity(0.1), location: 0), .init(color: .clear, location: 0.7)],
                    endRadiusFraction: 0.5
                )
                .frame(width: 1120, height: 360)
                .position(x: 700, y: 300)
            }
            .frame(width: 1400, height: 300)
            .clipped()
            .projectionEffect(P.effect(floor))
            LinearGradient(colors: [ListeningStyle.rackLipTop, ListeningStyle.rackLipBottom], startPoint: .top, endPoint: .bottom)
                .overlay(alignment: .top) { Rectangle().fill(.white.opacity(0.1)).frame(height: 1) }
                .frame(width: 1400, height: 9)
                .projectionEffect(P.effect(lip))
        }
        .frame(width: width, height: ListeningRackLayout.canvasHeight, alignment: .topLeading)
        .allowsHitTesting(false)
    }
}

/// Edge fade shared by the shelf and its loading stand-in.
struct ListeningRackEdgeFade: ViewModifier {
    func body(content: Content) -> some View {
        content.mask {
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black, location: ListeningRackLayout.edgeFade),
                    .init(color: .black, location: 1 - ListeningRackLayout.edgeFade),
                    .init(color: .clear, location: 1)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            .padding(.vertical, -ListeningRackLayout.caseSize)
        }
    }
}

/// Loading stand-in with the shelf's own geometry: blank cases and a blank plate.
struct ListeningRackSkeleton: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dim = false

    private typealias L = ListeningRackLayout

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { proxy in
                ZStack(alignment: .topLeading) {
                    ListeningRackFloor(width: proxy.size.width)
                    ForEach([-3, 3, -2, 2, -1, 1, 0], id: \.self) { d in
                        ListeningRackCase(
                            pose: pose(at: d),
                            content: ListeningRackCaseContent(title: "", isPlaceholder: true),
                            width: proxy.size.width
                        )
                        .opacity(dim ? 0.55 : 1)
                    }
                }
            }
            .frame(height: L.canvasHeight)
            .modifier(ListeningRackEdgeFade())
            Capsule()
                .fill(ListeningStyle.rackPlaceholder)
                .frame(width: 96, height: L.plateHeight)
                .frame(height: BSLayout.minTouchTarget)
                .opacity(dim ? 0.55 : 1)
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: dim)
        .onAppear { dim = true }
        .accessibilityHidden(true)
    }

    private func pose(at d: Int) -> ListeningRackPose {
        var pose = L.pose(at: d, discOut: false)
        pose.lit = d == 0 ? 1 : 0
        return pose
    }
}
