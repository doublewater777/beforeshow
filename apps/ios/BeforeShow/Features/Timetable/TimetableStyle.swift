import SwiftUI

/// Visual tokens for the timetable feature. Gold means "mine" (interested),
/// red means "now"; everything else stays neutral.
enum TimetableStyle {
    static let background = BSColor.Stage.background
    static let lane = Color(red: 0.055, green: 0.055, blue: 0.067)
    static let card = Color(red: 0.086, green: 0.086, blue: 0.102)
    static let cardMine = Color(red: 0.122, green: 0.106, blue: 0.075)
    static let foreground = BSColor.Stage.foreground
    static let muted = Color(red: 0.604, green: 0.604, blue: 0.635)
    static let dim = Color(red: 0.369, green: 0.369, blue: 0.400)
    static let mine = BSColor.Stage.accent
    static let now = BSColor.Stage.live
    static let nowSoft = Color(red: 1.0, green: 0.604, blue: 0.631)
    static let night = Color(red: 0.686, green: 0.765, blue: 0.933)
    static let attention = BSColor.Accent.warm

    static func mono(_ size: CGFloat, weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    static let pressSpring = Animation.spring(response: 0.45, dampingFraction: 0.78)
}

/// Capsule day switcher with a sliding indicator.
struct TimetableDaySwitcher: View {
    struct Item: Identifiable, Equatable {
        let id: UUID
        let label: String
        let date: String
        var isToday = false
    }

    let items: [Item]
    @Binding var selection: UUID
    @Namespace private var indicator

    /// Two days keep the one-line pills; three or more stack the date under the
    /// day so they fit the nav bar; five or more scroll, centred on the selection.
    var body: some View {
        if items.count <= 2 {
            track(compact: false)
        } else if items.count <= 4 {
            track(compact: true)
        } else {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    track(compact: true)
                }
                .frame(width: 230)
                .mask(LinearGradient(stops: [
                    .init(color: .clear, location: 0), .init(color: .black, location: 0.08),
                    .init(color: .black, location: 0.92), .init(color: .clear, location: 1)
                ], startPoint: .leading, endPoint: .trailing))
                .onAppear { proxy.scrollTo(selection, anchor: .center) }
                .onChange(of: selection) { _, id in
                    withAnimation(TimetableStyle.pressSpring) { proxy.scrollTo(id, anchor: .center) }
                }
            }
        }
    }

    private func track(compact: Bool) -> some View {
        HStack(spacing: 0) {
            ForEach(items) { item in
                let isOn = item.id == selection
                Button {
                    withAnimation(TimetableStyle.pressSpring) { selection = item.id }
                } label: {
                    Group {
                        if compact {
                            VStack(spacing: 1) {
                                Text(item.label).font(.system(size: 13, weight: .bold))
                                HStack(spacing: 3) {
                                    Text(item.date).font(TimetableStyle.mono(10.5))
                                    if item.isToday { todayDot }
                                }
                                .opacity(0.85)
                            }
                            .frame(minWidth: 54)
                            .frame(height: 40)
                        } else {
                            HStack(spacing: 5) {
                                Text(item.label).font(.system(size: 14, weight: .bold))
                                Text(item.date).font(TimetableStyle.mono(13))
                                if item.isToday { todayDot }
                            }
                            .padding(.horizontal, 14)
                            .frame(height: 38)
                        }
                    }
                    .lineLimit(1)
                    .fixedSize()
                    .foregroundStyle(isOn ? TimetableStyle.background : TimetableStyle.muted)
                    .background {
                        if isOn {
                            Capsule()
                                .fill(TimetableStyle.foreground)
                                .matchedGeometryEffect(id: "day", in: indicator)
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .id(item.id)
            }
        }
        .padding(3)
        .background(Capsule().fill(Color.white.opacity(0.05)))
        .overlay(Capsule().stroke(Color.white.opacity(0.05), lineWidth: 1))
    }

    private var todayDot: some View {
        Circle()
            .fill(TimetableStyle.now)
            .frame(width: 5, height: 5)
            .shadow(color: TimetableStyle.now.opacity(0.9), radius: 3)
    }
}

/// Stages are told apart by colour and marker shape together: the same stage
/// keeps the same light everywhere (home live mode, timetable).
enum TimetableStageLight {
    static let colors: [Color] = [
        Color(red: 0.949, green: 0.627, blue: 0.745),
        Color(red: 0.682, green: 0.612, blue: 1.0),
        Color(red: 0.498, green: 0.827, blue: 0.769),
        Color(red: 0.910, green: 0.780, blue: 0.557)
    ]

    static func color(_ index: Int) -> Color { colors[abs(index) % colors.count] }

    static func marker(_ index: Int) -> AnyShape {
        switch abs(index) % 4 {
        case 0: AnyShape(Circle())
        case 1: AnyShape(Rectangle().rotation(.degrees(45)).scale(0.8))
        case 2: AnyShape(StageTriangle())
        default: AnyShape(RoundedRectangle(cornerRadius: 1.5))
        }
    }

    private struct StageTriangle: Shape {
        func path(in rect: CGRect) -> Path {
            Path { p in
                p.move(to: CGPoint(x: rect.midX, y: rect.minY))
                p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
                p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
                p.closeSubpath()
            }
        }
    }
}

/// Three-bar level meter used as the "live" indicator.
struct TimetableEqualizer: View {
    var color: Color = TimetableStyle.now

    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .bottom, spacing: 1.5) {
                ForEach(0..<3, id: \.self) { index in
                    let phase = (sin(t * 2 * .pi + Double(index) * 2.1) + 1) / 2
                    RoundedRectangle(cornerRadius: 1)
                        .fill(color)
                        .frame(width: 2, height: 3 + 7 * phase)
                }
            }
            .frame(height: 10, alignment: .bottom)
        }
    }
}

struct TimetablePressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// Lock line shown under import actions; recognition never leaves the device.
struct TimetableOnDeviceNote: View {
    var body: some View {
        Label(BSLocalization.text("仅在本机识别"), systemImage: "lock")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(TimetableStyle.dim)
            .labelStyle(.titleAndIcon)
    }
}

/// Artist avatar for timetable surfaces: the matched photo, or the artist's
/// first character so unmatched performers stay recognisable at a glance.
struct TimetableArtistAvatar: View {
    let name: String
    let url: URL?
    let size: CGFloat

    var body: some View {
        if url != nil {
            ArtistAvatarThumb(url: url, size: size)
        } else {
            Circle()
                .fill(Color.white.opacity(0.1))
                .overlay(Circle().stroke(Color.white.opacity(0.08), lineWidth: 1))
                .overlay(
                    Text(String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(1)).uppercased())
                        .font(.system(size: size * 0.45, weight: .semibold))
                        .foregroundStyle(TimetableStyle.foreground.opacity(0.75))
                )
                .frame(width: size, height: size)
        }
    }
}
