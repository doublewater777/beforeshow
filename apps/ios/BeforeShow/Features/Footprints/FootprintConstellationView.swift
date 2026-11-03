import SwiftUI

/// Artists as a night sky: brighter stars were seen more often, lines are shared bills.
struct FootprintConstellationView: View {
    let archive: FootprintArchiveSnapshot

    @State private var selectedName: String?
    @State private var linesDrawn = false
    @State private var detailTarget: FootprintDetailDestination?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let sky = FootprintConstellationBuilder.make(shows: archive.shows)
        let selected = sky.stars.first { $0.name == selectedName } ?? sky.stars.max { $0.count < $1.count }
        VStack(spacing: 0) {
            GeometryReader { proxy in
                let size = proxy.size
                ZStack {
                    FootprintStarDust(count: sky.dustCount, isTwinkling: !reduceMotion)
                    if let selected { spotlight(on: point(selected.position, in: size)) }
                    lines(sky, selected: selected, size: size)
                    groupLabels(sky, size: size)
                    let neighbours = Self.neighbours(of: selected?.name, in: sky)
                    ForEach(sky.stars) { star in
                        starButton(
                            star,
                            isSelected: star.name == selected?.name,
                            showsName: star.count > 1 || neighbours.contains(star.name)
                        )
                        .position(point(star.position, in: size))
                    }
                }
            }
            .frame(maxHeight: .infinity)
            if let selected {
                card(for: selected)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                    .id(selected.name)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .background {
            LinearGradient(colors: [FootprintRoomPalette.skyTop, FootprintRoomPalette.skyBottom], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 0) {
                    FootprintNavigationTitle(title: BSLocalization.text("你的星空"))
                    Text(BSLocalization.format("%lld 位艺人", archive.artists.count))
                        .font(.system(size: 11))
                        .foregroundStyle(BSColor.Stage.muted)
                }
            }
        }
        .navigationDestination(item: $detailTarget) { FootprintDetailView(show: $0.show, archive: archive) }
        .sensoryFeedback(.selection, trigger: selectedName)
        .onAppear {
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 1.6).delay(0.3)) { linesDrawn = true }
        }
    }

    private func point(_ unit: CGPoint, in size: CGSize) -> CGPoint {
        CGPoint(x: unit.x * size.width, y: 24 + unit.y * (size.height - 48))
    }

    private func lines(_ sky: FootprintConstellation, selected: FootprintConstellation.Star?, size: CGSize) -> some View {
        let byName = Dictionary(uniqueKeysWithValues: sky.stars.map { ($0.name, $0) })
        return ForEach(Array(sky.edges.enumerated()), id: \.offset) { _, edge in
            if let a = byName[edge.from], let b = byName[edge.to] {
                let hot = edge.from == selected?.name || edge.to == selected?.name
                Path { path in
                    path.move(to: point(a.position, in: size))
                    path.addLine(to: point(b.position, in: size))
                }
                .trim(from: 0, to: linesDrawn ? 1 : 0)
                .stroke(hot ? BSColor.Stage.accent.opacity(0.85) : FootprintRoomPalette.starlight.opacity(0.32), lineWidth: hot ? 1.4 : 0.8)
                .animation(.easeOut(duration: 0.3), value: hot)
            }
        }
        .allowsHitTesting(false)
    }

    private func groupLabels(_ sky: FootprintConstellation, size: CGSize) -> some View {
        ForEach(sky.groups, id: \.brightest) { group in
            Text(BSLocalization.format("%@座", group.brightest))
                .font(.system(size: 13, design: .serif).italic())
                .foregroundStyle(FootprintRoomPalette.starlight.opacity(0.45))
                .position(point(group.labelAnchor, in: size).applying(.init(translationX: 0, y: 40)))
                .allowsHitTesting(false)
        }
    }

    private func spotlight(on target: CGPoint) -> some View {
        Path { path in
            path.move(to: CGPoint(x: target.x - 8, y: 0))
            path.addLine(to: CGPoint(x: target.x + 8, y: 0))
            path.addLine(to: CGPoint(x: target.x + 70, y: target.y))
            path.addLine(to: CGPoint(x: target.x - 70, y: target.y))
            path.closeSubpath()
        }
        .fill(LinearGradient(colors: [FootprintRoomPalette.spotlight.opacity(0), FootprintRoomPalette.spotlight.opacity(0.13)], startPoint: .top, endPoint: .bottom))
        .animation(reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.85), value: target)
        .allowsHitTesting(false)
    }

    /// Single-show stars stay unnamed unless they share a line with the selected star.
    private static func neighbours(of name: String?, in sky: FootprintConstellation) -> Set<String> {
        guard let name else { return [] }
        return Set(sky.edges.flatMap { edge -> [String] in
            edge.from == name ? [edge.to] : edge.to == name ? [edge.from] : []
        })
    }

    private func starButton(_ star: FootprintConstellation.Star, isSelected: Bool, showsName: Bool) -> some View {
        let core: CGFloat = star.count >= 3 ? 8 : star.count == 2 ? 6 : 3.5
        let halo: CGFloat = star.count >= 3 ? 34 : star.count == 2 ? 22 : 12
        // Names hug the inside of the sky near its edges instead of running off screen.
        let labelAlignment: Alignment = star.position.x > 0.75 ? .bottomTrailing : star.position.x < 0.25 ? .bottomLeading : .bottom
        return Button {
            selectedName = star.name
            FootprintSoundPlayer.shared.play(.chime(forShowCount: star.count))
        } label: {
            ZStack {
                FootprintBreathingHalo(
                    diameter: halo,
                    color: isSelected ? FootprintRoomPalette.spotlight : FootprintRoomPalette.starlight,
                    strength: star.count == 1 ? 0.35 : 0.55,
                    isBreathing: !reduceMotion
                )
                if star.count >= 3 {
                    Rectangle().fill(LinearGradient(colors: [.clear, .white, .clear], startPoint: .top, endPoint: .bottom)).frame(width: 1.5, height: 30)
                    Rectangle().fill(LinearGradient(colors: [.clear, .white, .clear], startPoint: .leading, endPoint: .trailing)).frame(width: 30, height: 1.5)
                }
                Circle()
                    .fill(isSelected ? FootprintRoomPalette.spotlight : .white)
                    .frame(width: core, height: core)
                    .shadow(color: .white, radius: 3)
            }
            .frame(width: 44, height: 44)
            .overlay(alignment: labelAlignment) {
                if showsName || isSelected {
                    Text(star.name)
                        .font(.system(size: star.count >= 2 ? 12 : 10, weight: star.count >= 3 ? .semibold : .regular))
                        .foregroundStyle(isSelected ? BSColor.Stage.accent : FootprintRoomPalette.starlight.opacity(star.count >= 2 ? 0.85 : 0.5))
                        .fixedSize()
                        .offset(y: 14)
                        .transition(.opacity)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(BSLocalization.format("%@，看过 %lld 场", star.name, star.count))
    }

    private func card(for star: FootprintConstellation.Star) -> some View {
        let shows = FootprintArchiveRankingBuilder.chronological(archive.shows.filter { $0.artistNames.contains(star.name) })
        let partners = Self.billPartners(of: star.name, in: shows)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(star.name)
                    .font(.system(size: 22, weight: .heavy, design: .serif))
                    .foregroundStyle(BSColor.Stage.heroIvory)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(BSLocalization.format("看过 %lld 场", star.count))
                    .font(.system(size: 13))
                    .foregroundStyle(BSColor.Stage.accent)
            }
            ForEach(shows.suffix(3)) { show in
                Button { detailTarget = FootprintDetailDestination(show: show) } label: {
                    HStack(spacing: 12) {
                        Text(footprintFullDateText(show.effectiveDate, calendar: show.timingCalendar()))
                            .font(.system(size: 13).monospacedDigit())
                            .foregroundStyle(FootprintRoomPalette.starlight.opacity(0.55))
                        Text([FootprintTextNormalizer.nonEmptyTrimmed(show.venueName), show.name].compactMap { $0 }.joined(separator: " · "))
                            .font(.system(size: 13))
                            .foregroundStyle(FootprintRoomPalette.starlight.opacity(0.9))
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(BSColor.Stage.dim)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Divider().overlay(Color.white.opacity(0.08))
            Text(partners.isEmpty
                 ? BSLocalization.text("孤星：每次都是专场")
                 : BSLocalization.format("同台过 %lld 位：%@", partners.count, partners.prefix(6).joined(separator: "、")))
                .font(.system(size: 12))
                .foregroundStyle(FootprintRoomPalette.starlight.opacity(0.6))
                .lineLimit(2)
        }
        .padding(18)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .background(FootprintRoomPalette.skyBottom.opacity(0.9), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(FootprintRoomPalette.starlight.opacity(0.12)))
        .environment(\.colorScheme, .dark)
    }

    static func billPartners(of name: String, in shows: [Show]) -> [String] {
        var seen = Set([name])
        return shows.flatMap(\.artistNames).filter { seen.insert($0).inserted }
    }
}

private struct FootprintBreathingHalo: View {
    let diameter: CGFloat
    let color: Color
    let strength: Double
    let isBreathing: Bool
    @State private var expanded = false

    var body: some View {
        Circle()
            .fill(RadialGradient(colors: [color.opacity(strength), .clear], center: .center, startRadius: 0, endRadius: diameter / 2))
            .frame(width: diameter, height: diameter)
            .scaleEffect(expanded ? 1.18 : 1)
            .onAppear {
                guard isBreathing else { return }
                withAnimation(.easeInOut(duration: 3.2).repeatForever(autoreverses: true)) { expanded = true }
            }
    }
}

/// One faint point for every artist seen once and never on a shared bill.
private struct FootprintStarDust: View {
    let count: Int
    let isTwinkling: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 10, paused: !isTwinkling)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            Canvas { canvas, size in
                var seed: UInt64 = 7
                func next() -> Double {
                    seed = seed &* 6364136223846793005 &+ 1442695040888963407
                    return Double(seed >> 33) / Double(UInt32.max >> 1)
                }
                for _ in 0..<count {
                    let x = next() * size.width, y = next() * size.height
                    let r = next() < 0.85 ? 0.5 : 0.8
                    let phase = next() * 6.28
                    let alpha = isTwinkling ? 0.35 + 0.45 * (0.5 + 0.5 * sin(t * 1.6 + phase)) : 0.6
                    canvas.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
                                with: .color(FootprintRoomPalette.starlight.opacity(alpha)))
                }
            }
        }
        .accessibilityHidden(true)
    }
}
