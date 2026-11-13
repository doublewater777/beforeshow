import SwiftUI

enum BSStageLighting: Equatable {
    /// The light rig runs its programme in the poster's colours. Energy 0 is the still preset
    /// while the room fills, 1 the full show.
    case show(energy: Double)
    /// The poster's colours wash the stage; nothing moves and no rig hangs.
    case wash
    /// After the show: house lights up, no beams.
    case house
    /// Postponed: the stage is dark but for one ghost light.
    case ghost
    /// Cancelled: nothing lit.
    case dark

    var isShow: Bool {
        if case .show = self { true } else { false }
    }

    /// Lit in the poster's colours.
    var isColored: Bool { isShow || self == .wash }
}

/// A stage seen from the floor: truss and lamps, the poster as the LED wall, the crowd along the lip.
/// The same stage carries a show from before doors to house lights; only the lighting changes.
struct BSStageScene<Wall: View, Lip: View>: View {

    let colors: [Color]
    let lighting: BSStageLighting
    let powered: Bool
    var height: CGFloat = 380
    @ViewBuilder let wall: Wall
    /// Something standing on the stage lip, in front of the crowd.
    @ViewBuilder let lip: Lip

    private static var floor: Color { Color(red: 0.024, green: 0.02, blue: 0.02) }
    private static var houseColor: Color { Color(red: 1.0, green: 0.93, blue: 0.8) }
    private static var ghostColor: Color { Color(red: 1.0, green: 0.78, blue: 0.5) }

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack {
                Self.floor
                RadialGradient(colors: [ambient.color.opacity(ambient.opacity), .clear], center: .init(x: 0.5, y: lighting == .house ? 0.4 : 0.72), startRadius: 0, endRadius: width * 0.8)
                if lighting.isColored {
                    // The LED wall lights the haze behind and around it.
                    RadialGradient(colors: [colors[0].opacity(0.22), colors[1].opacity(0.08), .clear], center: .init(x: 0.5, y: 0.46), startRadius: 20, endRadius: width * 0.55)
                        .opacity(powered ? 1 : 0)
                        .allowsHitTesting(false)
                }
                if case .show(let energy) = lighting {
                    // Back truss: beams come from behind the screen so the poster stays whole.
                    BSStageRig(colors: colors, energy: energy, height: height)
                        .opacity(powered ? 1 : 0)
                }
                if lighting == .ghost {
                    ghostLight(width: width)
                }
                wall.position(x: width / 2, y: height - 204)
                if lighting != .wash {
                    truss(width: width)
                }
                // Light spilling onto the floor in front of the crowd.
                Ellipse()
                    .fill(RadialGradient(colors: [ambient.color.opacity(ambient.opacity * 1.2), .clear], center: .center, startRadius: 0, endRadius: width * 0.5))
                    .frame(width: width * 1.1, height: 90)
                    .position(x: width / 2, y: height - 66)
                    .allowsHitTesting(false)
                BSStageCrowd()
                    .fill(Self.floor)
                    .overlay {
                        // Light catching the tops of heads and hands.
                        BSStageCrowd()
                            .stroke(ambient.color.opacity(powered ? rimOpacity : 0), lineWidth: 1)
                            .blur(radius: 0.6)
                    }
                    .frame(height: 78)
                    .position(x: width / 2, y: height - 39)
                    .allowsHitTesting(false)
                lip.position(x: width / 2, y: height - 70)
            }
        }
        .frame(height: height)
        .clipped()
        // The stage dissolves into the page instead of ending on a hard edge.
        .mask {
            LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.86), .init(color: .clear, location: 1)], startPoint: .top, endPoint: .bottom)
        }
    }

    private var ambient: (color: Color, opacity: Double) {
        switch lighting {
        case .show, .wash: (colors[0], 0.18)
        case .house: (Self.houseColor, 0.12)
        case .ghost: (Self.ghostColor, 0.05)
        case .dark: (.clear, 0)
        }
    }

    private var rimOpacity: Double {
        switch lighting {
        case .show, .wash: 0.3
        case .house: 0.22
        case .ghost: 0.12
        case .dark: 0
        }
    }

    /// One bare bulb on a stand, left on an empty stage until it opens again.
    private func ghostLight(width: CGFloat) -> some View {
        let x = width * 0.83
        let bulbY = height - 128
        return ZStack {
            RadialGradient(colors: [Self.ghostColor.opacity(0.32), Self.ghostColor.opacity(0.06), .clear], center: .center, startRadius: 2, endRadius: 90)
                .frame(width: 180, height: 180)
                .position(x: x, y: bulbY)
            Rectangle()
                .fill(Color(white: 0.16))
                .frame(width: 2, height: 58)
                .position(x: x, y: bulbY + 32)
            Circle()
                .fill(Color(red: 1, green: 0.92, blue: 0.78))
                .frame(width: 7, height: 7)
                .shadow(color: Self.ghostColor, radius: 6)
                .position(x: x, y: bulbY)
        }
        .opacity(powered ? 1 : 0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func truss(width: CGFloat) -> some View {
        ZStack(alignment: .top) {
            Canvas { canvas, size in
                canvas.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(white: 0.12)))
                var x: CGFloat = -size.height
                while x < size.width {
                    var strut = Path()
                    strut.move(to: CGPoint(x: x, y: size.height))
                    strut.addLine(to: CGPoint(x: x + size.height, y: 0))
                    canvas.stroke(strut, with: .color(Color(white: 0.24)), lineWidth: 1.2)
                    x += 9
                }
            }
            .frame(height: 12)
            // Moving-head bodies hung where the rig's beams start.
            ForEach(0..<BSStageRig.fixtureCount, id: \.self) { index in
                RoundedRectangle(cornerRadius: 3)
                    .fill(LinearGradient(colors: [Color(white: 0.16), Color(white: 0.07)], startPoint: .top, endPoint: .bottom))
                    .frame(width: 14, height: 11)
                    .position(x: width * BSStageRig.fixtureX(index), y: 15)
            }
        }
        .frame(width: width)
        .position(x: width / 2, y: 18)
        .accessibilityHidden(true)
    }
}

extension BSStageScene where Lip == EmptyView {
    init(colors: [Color], lighting: BSStageLighting, powered: Bool, height: CGFloat = 380, @ViewBuilder wall: () -> Wall) {
        self.init(colors: colors, lighting: lighting, powered: powered, height: height, wall: wall, lip: { EmptyView() })
    }
}

/// The date line above a show's name: "2026.10.03 SAT", "— 10.04 SUN" for a show over several days.
enum BSStageDateLine {
    static func text(
        start: Date,
        calendar: Calendar,
        end: Date?,
        endCalendar: Calendar,
        showsYear: Bool = true,
        startTime: Date? = nil
    ) -> String {
        var text = format(start, calendar: calendar, pattern: showsYear ? "yyyy.MM.dd EEE" : "MM.dd EEE")
        if let startTime {
            text += " " + format(startTime, calendar: calendar, pattern: "HH:mm")
        }
        if let end, end > start, !calendar.isDate(end, inSameDayAs: start) {
            text += " — " + format(end, calendar: endCalendar, pattern: "MM.dd EEE")
        }
        return text
    }

    private static func format(_ date: Date, calendar: Calendar, pattern: String) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = pattern
        return formatter.string(from: date).uppercased()
    }
}

/// Heads and raised hands along the front of the stage.
private struct BSStageCrowd: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        var hands: [CGPoint] = []
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.5))
        let heads = 14
        let step = rect.width / CGFloat(heads)
        func y(_ fraction: CGFloat) -> CGFloat { rect.minY + rect.height * fraction }
        for index in 0..<heads {
            let x = rect.minX + CGFloat(index) * step
            let lift: CGFloat = index % 3 == 0 ? 0.3 : index % 2 == 0 ? 0.45 : 0.38
            // One continuous outline: shoulder, head, (arm up and back down), shoulder.
            path.addQuadCurve(to: CGPoint(x: x + step * 0.5, y: y(lift)), control: CGPoint(x: x + step * 0.12, y: y(lift - 0.05)))
            if index % 4 == 1 {
                let wrist = CGPoint(x: x + step * 0.62, y: y(0.1))
                path.addLine(to: CGPoint(x: x + step * 0.56, y: y(lift)))
                path.addLine(to: CGPoint(x: wrist.x - 1.5, y: wrist.y))
                path.addLine(to: CGPoint(x: wrist.x + 1.5, y: wrist.y))
                path.addLine(to: CGPoint(x: x + step * 0.66, y: y(lift + 0.02)))
                hands.append(wrist)
            }
            path.addQuadCurve(to: CGPoint(x: x + step, y: y(0.52)), control: CGPoint(x: x + step * 0.88, y: y(lift - 0.05)))
        }
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        for wrist in hands {
            path.addEllipse(in: CGRect(x: wrist.x - 3.5, y: wrist.y - 7, width: 7, height: 9))
        }
        return path
    }
}

/// The bill as chips; artists seen before carry "第 N 次" and sort first so the limit never hides them.
struct BSStageLineupChips: View {
    struct Entry {
        let name: String
        /// How many times this night makes, counting it.
        let nth: Int
    }

    let entries: [Entry]
    let accent: Color
    let onOpen: (String) -> Void

    @State private var isExpanded = false

    private static let limit = 10

    var body: some View {
        let sorted = entries.enumerated()
            .sorted { ($0.element.nth > 1 ? 0 : 1, $0.offset) < ($1.element.nth > 1 ? 0 : 1, $1.offset) }
            .map(\.element)
        if !sorted.isEmpty {
            BSFlowLayout(spacing: 6) {
                ForEach(sorted.prefix(isExpanded ? sorted.count : Self.limit), id: \.name) { entry in
                    Button { onOpen(entry.name) } label: { chip(entry) }
                        .buttonStyle(.plain)
                }
                if sorted.count > Self.limit {
                    Button {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { isExpanded.toggle() }
                    } label: {
                        HStack(spacing: 2) {
                            Text(isExpanded ? BSLocalization.text("收起") : BSLocalization.format("全部 %lld 位", sorted.count))
                            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                .font(.system(size: 9, weight: .bold))
                        }
                        .font(.system(size: 12))
                        .foregroundStyle(BSColor.Stage.muted)
                        .padding(.horizontal, 10)
                        .frame(height: 28)
                        .overlay(Capsule().stroke(Color.white.opacity(0.12)))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func chip(_ entry: Entry) -> some View {
        let isReunion = entry.nth > 1
        return HStack(spacing: 5) {
            Text(entry.name).lineLimit(1)
            if isReunion {
                Text(BSLocalization.format("第 %lld 次", entry.nth))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(accent)
            }
        }
        .font(.system(size: 12))
        .foregroundStyle(isReunion ? BSColor.Stage.heroIvory : BSColor.Stage.foreground.opacity(0.75))
        .padding(.horizontal, 10)
        .frame(height: 28)
        .background(isReunion ? accent.opacity(0.1) : Color.white.opacity(0.06), in: Capsule())
        .overlay { if isReunion { Capsule().stroke(accent.opacity(0.35)) } }
    }
}

/// Wraps chips onto as many lines as they need.
struct BSFlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0, height: rows.last.map { $0.y + $0.height } ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: bounds.minY + row.y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
        }
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> [(indices: [Int], y: CGFloat, width: CGFloat, height: CGFloat)] {
        var rows: [(indices: [Int], y: CGFloat, width: CGFloat, height: CGFloat)] = []
        var current: [Int] = [], x: CGFloat = 0, y: CGFloat = 0, height: CGFloat = 0
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                rows.append((current, y, x - spacing, height))
                y += height + spacing
                current = []; x = 0; height = 0
            }
            current.append(index)
            x += size.width + spacing
            height = max(height, size.height)
        }
        if !current.isEmpty { rows.append((current, y, x - spacing, height)) }
        return rows
    }
}
