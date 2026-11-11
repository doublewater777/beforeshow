import SwiftUI
import simd

/// Picks how 帮我挑一张 lays out the albums, each style shown with the user's own covers.
struct ListeningPickStyleSheet: View {
    let discs: [ListeningDisc]
    let show: Show
    let currentID: String?
    let current: ListeningPickStyle
    /// Free trial opens left for the Pro styles; nil for Pro.
    let trialLeft: Int?
    /// A Pro style can't be chosen: the trial is used up and this open didn't count towards it.
    let isLocked: Bool
    let onChoose: (ListeningPickStyle) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var isShowingPaywall = false

    private var position: Double { Double(discs.firstIndex { $0.id == currentID } ?? 0) }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 240), spacing: BSSpacing.md)], spacing: BSSpacing.xl) {
                    ForEach(ListeningPickStyle.available()) { style in
                        option(style)
                    }
                }
                .padding(BSSpacing.roomy)
            }
            .background(BSColor.Stage.background.ignoresSafeArea())
            .navigationTitle(ListeningCopy.text("样式"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                BSChromeToolbarCloseButton(accessibilityLabel: BSLocalization.text("关闭")) { dismiss() }
            }
        }
        .tint(BSColor.Stage.foreground)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $isShowingPaywall) { ProPaywallView() }
    }

    private func option(_ style: ListeningPickStyle) -> some View {
        let locked = style.isPro && isLocked
        let isCurrent = style == current
        return Button {
            if locked {
                isShowingPaywall = true
            } else {
                onChoose(style)
                dismiss()
            }
        } label: {
            VStack(alignment: .leading, spacing: BSSpacing.sm) {
                preview(style)
                    .aspectRatio(0.68, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(isCurrent ? BSColor.Stage.foreground : .white.opacity(0.12), lineWidth: isCurrent ? 2 : 0.5)
                    }
                    .overlay(alignment: .topTrailing) {
                        if locked {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 12, weight: .bold))
                                .frame(width: 28, height: 28)
                                .background(Circle().fill(.black.opacity(0.45)))
                                .padding(BSSpacing.sm)
                        }
                    }
                HStack(spacing: BSSpacing.xs) {
                    Text(style.title).font(.system(size: 15, weight: .bold, design: .rounded))
                    if isCurrent {
                        Image(systemName: "checkmark").font(.system(size: 12, weight: .bold))
                    }
                }
                Text(badge(locked: locked))
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(BSColor.Stage.foreground.opacity(0.6))
                    .opacity(style.isPro ? 1 : 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func badge(locked: Bool) -> String {
        guard let trialLeft, !locked else { return "PRO" }
        return ListeningCopy.format("免费试用，剩 %lld 次", trialLeft)
    }

    @ViewBuilder
    private func preview(_ style: ListeningPickStyle) -> some View {
        if style == .feed {
            feedPreview
        } else {
            ZStack {
                ListeningPickShelfBackdrop()
                if style == .shelf3D, #available(iOS 18.0, *) {
                    ShelfStill3D(discs: discs, position: position)
                } else {
                    StylePreviewStage(style: style, discs: discs, show: show, position: position)
                }
            }
            .allowsHitTesting(false)
        }
    }

    /// One album filling the screen, the way 一屏一张 opens.
    private var feedPreview: some View {
        GeometryReader { proxy in
            let disc = discs.first { $0.id == currentID } ?? discs.first
            let cover = proxy.size.width * 0.72
            ZStack(alignment: .bottomLeading) {
                BSColor.Stage.background
                if let disc {
                    ListeningArtwork(url: disc.artworkURL, title: disc.title)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .blur(radius: 24)
                        .opacity(0.6)
                    LinearGradient(colors: [.clear, BSColor.Stage.background.opacity(0.85)], startPoint: .center, endPoint: .bottom)
                    ListeningArtwork(url: disc.artworkURL, title: disc.title)
                        .frame(width: cover, height: cover)
                        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                        .shadow(color: .black.opacity(0.5), radius: 12, y: 8)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .padding(.top, proxy.size.height * 0.2)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(disc.displayArtistName(for: show))
                            .font(ListeningOverviewStyle.caps(8)).tracking(1.2).textCase(.uppercase)
                            .foregroundStyle(BSColor.Stage.accent)
                        Text(disc.title).font(ListeningOverviewStyle.serif(17)).lineLimit(2)
                    }
                    .padding(BSSpacing.md)
                    .padding(.bottom, proxy.size.height * 0.06)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        }
        .allowsHitTesting(false)
    }
}

/// A shelf style playing its opening once, so each preview shows how it moves.
private struct StylePreviewStage: View {
    let style: ListeningPickStyle
    let discs: [ListeningDisc]
    let show: Show
    let position: Double

    @State private var start: Date?
    @State private var isDone = false
    private var duration: Double { ListeningPickShelfStage.openingDuration(for: style) }

    var body: some View {
        TimelineView(.animation(paused: isDone)) { context in
            ListeningPickShelfStage(
                style: style, discs: discs, show: show, position: position,
                entrance: start.map { min(1, context.date.timeIntervalSince($0) / duration) } ?? 0
            )
        }
        .onAppear { start = .now }
        .task(id: start) {
            guard start != nil else { return }
            try? await Task.sleep(for: .seconds(duration + 0.1))
            isDone = true
        }
    }
}

/// The 3D shelf at rest, drawn flat through the same camera. A live RealityKit preview would share the frame rate with
/// the 3D shelf under the sheet, and both slow to a crawl.
@available(iOS 18.0, *)
private struct ShelfStill3D: View {
    let discs: [ListeningDisc]
    let position: Double

    private static let side: CGFloat = 100
    private static let plastic = Color(red: 0.84, green: 0.82, blue: 0.9)

    private struct Face: Identifiable {
        let id: String
        /// Top-left, top-right, bottom-right, bottom-left on screen.
        let corners: [CGPoint]
        /// The printed front; nil for a plastic edge.
        let disc: ListeningDisc?
        let brightness: Double
        let opacity: Double
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                ForEach(faces(in: proxy.size)) { face in
                    content(of: face)
                        .frame(width: Self.side, height: Self.side)
                        .projectionEffect(Self.mapping(to: face.corners))
                        .opacity(face.opacity)
                }
            }
        }
        .clipped()
    }

    @ViewBuilder
    private func content(of face: Face) -> some View {
        if let disc = face.disc {
            HStack(spacing: 0) {
                Rectangle()
                    .fill(ListeningArtworkTone.cached(disc.artworkURL).map { Color(uiColor: ListeningArtworkTone.spine(for: $0).fill) } ?? Color(white: 0.12))
                    .frame(width: Self.side * 0.11)
                ListeningArtwork(url: disc.artworkURL, title: disc.title)
                    .frame(width: Self.side * 0.82, height: Self.side * 0.92)
                    .clipped()
            }
            .frame(width: Self.side, height: Self.side)
            .background(Self.plastic)
        } else {
            Self.plastic.brightness(face.brightness)
        }
    }

    /// Each case's front, right edge and top, far ones first, placed like `ShelfScene3D` at rest.
    private func faces(in size: CGSize) -> [Face] {
        guard !discs.isEmpty, size.width > 0 else { return [] }
        let base = min(max(Int(position.rounded()), 0), discs.count - 1)
        let offset = ShelfScene3D.cameraOffset(for: size)
        let eye = ShelfScene3D.aim + offset
        let forward = simd_normalize(-offset)
        let w = ShelfScene3D.caseWidth / 2, h = ShelfScene3D.caseHeight / 2, t = ShelfScene3D.thickness / 2
        let cases = (max(0, base - 8)...min(discs.count - 1, base + 18)).map { index -> (Int, SIMD3<Float>, simd_quatf) in
            let d = Float(index - base)
            if d == 0 {
                return (index, ShelfScene3D.pullOut, simd_quatf(angle: ShelfScene3D.pullTurn, axis: [0, 1, 0]))
            }
            return (index, [0, 0, -d * ShelfScene3D.spacing + (d < 0 ? ShelfScene3D.frontGap : 0)], simd_quatf(angle: 0, axis: [0, 1, 0]))
        }
        var faces: [Face] = []
        for (index, centre, turn) in cases.sorted(by: { simd_dot($0.1 - eye, forward) > simd_dot($1.1 - eye, forward) }) {
            let d = Double(index - base)
            let opacity = min(1, max(0, (20 - d) / 8)) * min(1, max(0, (d + 9) / 4))
            let id = discs[index].id
            let sides: [(String, [SIMD3<Float>], ListeningDisc?, Double)] = [
                ("top", [[-w, h, -t], [w, h, -t], [w, h, t], [-w, h, t]], nil, 0.08),
                ("side", [[w, h, t], [w, h, -t], [w, -h, -t], [w, -h, t]], nil, -0.12),
                ("front", [[-w, h, t], [w, h, t], [w, -h, t], [-w, -h, t]], discs[index], 0),
            ]
            for (name, points, disc, brightness) in sides {
                var corners: [CGPoint] = []
                for point in points {
                    corners.append(ShelfScene3D.project(centre + turn.act(point), in: size))
                }
                faces.append(Face(id: id + name, corners: corners, disc: disc, brightness: brightness, opacity: opacity))
            }
        }
        return faces
    }

    /// Maps the face's square onto its four corners on screen.
    private static func mapping(to q: [CGPoint]) -> ProjectionTransform {
        let sx = q[0].x - q[1].x + q[2].x - q[3].x, sy = q[0].y - q[1].y + q[2].y - q[3].y
        let dx1 = q[1].x - q[2].x, dx2 = q[3].x - q[2].x, dy1 = q[1].y - q[2].y, dy2 = q[3].y - q[2].y
        let den = dx1 * dy2 - dx2 * dy1
        let g = den == 0 ? 0 : (sx * dy2 - dx2 * sy) / den
        let h = den == 0 ? 0 : (dx1 * sy - sx * dy1) / den
        var square = ProjectionTransform()
        square.m11 = q[1].x - q[0].x + g * q[1].x
        square.m12 = q[1].y - q[0].y + g * q[1].y
        square.m13 = g
        square.m21 = q[3].x - q[0].x + h * q[3].x
        square.m22 = q[3].y - q[0].y + h * q[3].y
        square.m23 = h
        square.m31 = q[0].x
        square.m32 = q[0].y
        square.m33 = 1
        return ProjectionTransform(CGAffineTransform(scaleX: 1 / side, y: 1 / side)).concatenating(square)
    }
}
