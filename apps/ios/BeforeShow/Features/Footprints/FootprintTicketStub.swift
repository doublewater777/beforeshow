import SwiftUI

/// An admit-one ticket for the night. Tear along the perforation and the torn
/// half becomes the share image; tap the stub to put it back.
struct FootprintTicketStub: View {
    let show: Show
    let ordinal: Int
    let lights: [Color]
    var reunionLine: String?

    @State private var torn = false
    @State private var shareImage: Image?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.displayScale) private var displayScale

    private static let height: CGFloat = 118
    private static let stubWidth: CGFloat = 86
    private static let paper = Color(red: 0.937, green: 0.906, blue: 0.839)
    private static let ink = Color(red: 0.106, green: 0.102, blue: 0.09)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .leading) {
                stub
                    .clipShape(torn ? AnyShape(FootprintTornEdge()) : AnyShape(UnevenRoundedRectangle(topLeadingRadius: 10, bottomLeadingRadius: 10)))
                    .rotationEffect(.degrees(torn ? -4 : 0), anchor: .leading)
                    .onTapGesture { if torn { withAnimation(.spring(response: 0.45, dampingFraction: 0.7)) { torn = false } } }
                Button(action: tear) {
                    FootprintTicketFace(show: show, ordinal: ordinal, lights: lights)
                }
                .buttonStyle(.plain)
                .frame(height: Self.height)
                .padding(.leading, Self.stubWidth)
                .offset(x: torn ? 80 : 0, y: torn ? -60 : 0)
                .rotationEffect(.degrees(torn ? 9 : 0))
                .opacity(torn ? 0 : 1)
                .allowsHitTesting(!torn)
                .accessibilityLabel(BSLocalization.text("沿虚线撕下票根"))
                perforationNotches
            }
            .frame(height: Self.height)
            .shadow(color: .black.opacity(0.45), radius: 12, y: 8)
            HStack {
                Text(torn ? BSLocalization.text("票根已撕下，分享图已生成") : (reunionLine ?? BSLocalization.text("点票根撕下")))
                    .font(.system(size: 12))
                    .foregroundStyle(torn ? lights[1] : BSColor.Stage.muted)
                    .contentTransition(.opacity)
                Spacer(minLength: 8)
                if torn, let shareImage {
                    ShareLink(item: shareImage, preview: SharePreview(show.name, image: shareImage)) {
                        Text(BSLocalization.text("分享票根"))
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(BSColor.Stage.foreground)
                            .padding(.horizontal, 14)
                            .frame(height: 32)
                            .background(Color.white.opacity(0.08), in: Capsule())
                    }
                    .transition(.opacity)
                }
            }
            .frame(height: 32)
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: torn) { _, isTorn in isTorn }
    }

    private var stub: some View {
        VStack(alignment: .leading) {
            Text(BSLocalization.text("STUB"))
                .font(.system(size: 9, weight: .medium).width(.condensed))
                .tracking(2)
                .foregroundStyle(Self.ink.opacity(0.5))
            Spacer(minLength: 0)
            Text(String(format: "%03d", ordinal))
                .font(.system(size: 30, weight: .medium).width(.condensed))
                .foregroundStyle(Self.ink)
            Spacer(minLength: 0)
            Text(Self.shortDate(show))
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(Self.ink.opacity(0.6))
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 10)
        .frame(width: Self.stubWidth, height: Self.height, alignment: .leading)
        .background(Self.paper)
        .accessibilityHidden(true)
    }

    /// Punched half-circles where the perforation meets the edges.
    private var perforationNotches: some View {
        VStack {
            Circle().fill(BSColor.Stage.background).frame(width: 18, height: 18).offset(y: -9)
            Spacer()
            Circle().fill(BSColor.Stage.background).frame(width: 18, height: 18).offset(y: 9)
        }
        .frame(height: Self.height)
        .offset(x: Self.stubWidth - 9)
        .opacity(torn ? 0 : 1)
        .allowsHitTesting(false)
    }

    private func tear() {
        guard !torn else { return }
        let renderer = ImageRenderer(content: FootprintTicketFace(show: show, ordinal: ordinal, lights: lights, isExport: true))
        renderer.scale = displayScale
        if let uiImage = renderer.uiImage { shareImage = Image(uiImage: uiImage) }
        FootprintSoundPlayer.shared.play(.tear)
        withAnimation(reduceMotion ? .easeOut(duration: 0.25) : .timingCurve(0.5, 0, 0.3, 1, duration: 0.9)) { torn = true }
    }

    private static func shortDate(_ show: Show) -> String {
        let parts = show.timingCalendar().dateComponents([.year, .month, .day], from: show.effectiveDate)
        return String(format: "%02d.%02d.%02d", (parts.year ?? 0) % 100, parts.month ?? 0, parts.day ?? 0)
    }
}

/// The tear-off half: what gets shared.
struct FootprintTicketFace: View {
    let show: Show
    let ordinal: Int
    let lights: [Color]
    var isExport = false

    private static let paper = Color(red: 0.937, green: 0.906, blue: 0.839)
    private static let ink = Color(red: 0.106, green: 0.102, blue: 0.09)

    var body: some View {
        HStack(spacing: 0) {
            LinearGradient(colors: lights, startPoint: .top, endPoint: .bottom).frame(width: 10)
            VStack(alignment: .leading) {
                HStack {
                    Text(BSLocalization.text("ADMIT ONE"))
                    Spacer()
                    Text(isExport ? String(format: "№ %03d", ordinal) : BSLocalization.text("BEFORESHOW"))
                }
                .font(.system(size: 9, weight: .medium).width(.condensed))
                .tracking(2.5)
                .foregroundStyle(Self.ink.opacity(0.5))
                Spacer(minLength: 0)
                Text(show.name)
                    .font(.system(size: 17, weight: .heavy, design: .serif))
                    .foregroundStyle(Self.ink)
                    .lineLimit(1)
                Spacer(minLength: 0)
                HStack(alignment: .bottom) {
                    Text([footprintFullDateText(show.effectiveDate, calendar: show.timingCalendar()), FootprintTextNormalizer.nonEmptyTrimmed(show.city)].compactMap { $0 }.joined(separator: " · "))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Self.ink.opacity(0.75))
                    Spacer()
                    FootprintTicketBarcode().frame(width: 54, height: 18)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
        .frame(width: isExport ? 300 : nil, height: 118)
        .background(Self.paper)
        .clipShape(UnevenRoundedRectangle(bottomTrailingRadius: 10, topTrailingRadius: 10))
        .overlay(alignment: .leading) {
            if !isExport {
                // The perforation.
                Path { path in
                    path.move(to: CGPoint(x: 1, y: 0))
                    path.addLine(to: CGPoint(x: 1, y: 118))
                }
                .stroke(Self.ink.opacity(0.35), style: StrokeStyle(lineWidth: 2, dash: [4, 4]))
                .frame(width: 2)
            }
        }
    }
}

private struct FootprintTicketBarcode: View {
    var body: some View {
        Canvas { canvas, size in
            let pattern: [CGFloat] = [1, 2, 2, 1, 1, 3, 1, 1, 2, 1, 3, 2, 1, 1, 2, 2, 1, 3, 1, 2]
            var x: CGFloat = 0
            for (index, width) in pattern.enumerated() where x < size.width {
                if index % 2 == 0 {
                    canvas.fill(Path(CGRect(x: x, y: 0, width: width, height: size.height)), with: .color(Color(red: 0.106, green: 0.102, blue: 0.09)))
                }
                x += width + 1
            }
        }
        .accessibilityHidden(true)
    }
}

/// The stub's ragged edge once the ticket has been torn away.
private struct FootprintTornEdge: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - 3, y: rect.minY))
        let teeth = 14
        for tooth in 0...teeth {
            let y = rect.minY + rect.height * CGFloat(tooth) / CGFloat(teeth)
            path.addLine(to: CGPoint(x: tooth % 2 == 0 ? rect.maxX : rect.maxX - 5, y: y))
        }
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
