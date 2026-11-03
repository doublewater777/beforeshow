import SwiftUI

/// Venues as neon signs on a brick wall: brightness is how often, flicker is how long ago.
struct FootprintNeonVenuesView: View {
    let archive: FootprintArchiveSnapshot

    @State private var selectedID: String?
    @State private var relit: [String: Date] = [:]
    @State private var powerOn = 0
    @State private var detailTarget: FootprintDetailDestination?

    private static let fonts: [Font] = [
        .system(size: 66, weight: .black, design: .rounded),
        .system(size: 40, weight: .heavy, design: .rounded),
        .system(size: 36, weight: .semibold, design: .serif).italic(),
        .system(size: 50, weight: .light, design: .default).italic(),
        .system(size: 34, weight: .bold, design: .monospaced),
        .system(size: 38, weight: .heavy).width(.condensed)
    ]

    var body: some View {
        let signs = FootprintStagePolicy.neonSigns(venues: archive.venueArchiveItems)
        let dark = archive.venueArchiveItems.filter { !$0.isRevisited }
        let selected = signs.first { $0.id == selectedID } ?? signs.first
        ScrollView {
            VStack(spacing: 34) {
                ForEach(Array(signs.enumerated()), id: \.element.id) { index, sign in
                    signButton(sign, font: Self.fonts[index % Self.fonts.count])
                }
                if !dark.isEmpty { darkRow(dark) }
            }
            .padding(.top, 44)
            .padding(.horizontal, 16)
            .bsAdaptiveContentWidth()
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .safeAreaInset(edge: .bottom) {
            if let selected { card(for: selected).padding(.horizontal, 16).padding(.bottom, 8) }
        }
        .background { FootprintBrickWall().ignoresSafeArea() }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .principal) { FootprintNavigationTitle(title: BSLocalization.text("常回去的地方")) } }
        .navigationDestination(item: $detailTarget) { FootprintDetailView(show: $0.show, archive: archive) }
        .sensoryFeedback(.impact(flexibility: .rigid, intensity: 0.7), trigger: powerOn)
    }

    private func signButton(_ sign: FootprintNeonSign, font: Font) -> some View {
        let text = Self.signText(for: sign.venue.name, cities: sign.venue.cities)
        let isSelected = sign.id == (selectedID ?? sign.id)
        return Button {
            selectedID = sign.id
            relit[sign.id] = Date()
            powerOn += 1
            FootprintSoundPlayer.shared.play(.neon)
        } label: {
            VStack(spacing: 6) {
                FootprintNeonText(text: text.title, font: font, glow: sign.glow, steadiness: sign.steadiness, relitAt: relit[sign.id])
                    .lineLimit(1)
                    .minimumScaleFactor(0.4)
                if let subtitle = text.subtitle {
                    FootprintNeonText(text: subtitle, font: .system(size: 15, weight: .medium).width(.expanded), glow: max(.faint, sign.glow == .full ? .warm : .faint), steadiness: sign.steadiness, relitAt: relit[sign.id])
                        .tracking(6)
                }
                Text(BSLocalization.format("%lld 次", sign.venue.count))
                    .font(.system(size: 11))
                    .foregroundStyle(FootprintRoomPalette.neonCore.opacity(isSelected ? 0.7 : 0.45))
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(BSLocalization.format("%@，去过 %lld 次", sign.venue.name, sign.venue.count))
    }

    private func darkRow(_ venues: [FootprintVenueArchiveItem]) -> some View {
        HStack(spacing: 22) {
            ForEach(venues.prefix(3)) { venue in
                Text(Self.signText(for: venue.name, cities: venue.cities).title)
                    .font(.system(size: 20, weight: .heavy, design: .rounded))
                    .foregroundStyle(FootprintRoomPalette.deadTube)
                    .lineLimit(1)
            }
            if venues.count > 3 {
                Text(BSLocalization.format("还有 %lld 块暗着", venues.count - 3))
                    .font(.system(size: 12))
                    .foregroundStyle(FootprintRoomPalette.neonCore.opacity(0.4))
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func card(for sign: FootprintNeonSign) -> some View {
        let shows = FootprintArchiveRankingBuilder.chronological(archive.shows(for: sign.venue.showIDs))
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(sign.venue.name)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(BSColor.Stage.foreground)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(BSLocalization.format("%lld 次", sign.venue.count))
                    .font(.system(size: 13))
                    .foregroundStyle(FootprintRoomPalette.neonInner)
            }
            if let last = shows.last {
                Text(lastVisitLine(last, sign: sign))
                    .font(.system(size: 13))
                    .foregroundStyle(FootprintRoomPalette.neonCore.opacity(0.72))
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(shows) { show in
                        Button { detailTarget = FootprintDetailDestination(show: show) } label: {
                            Text(footprintFullDateText(show.effectiveDate, calendar: show.timingCalendar()))
                                .font(.system(size: 11).monospacedDigit())
                                .foregroundStyle(FootprintRoomPalette.neonCore.opacity(0.78))
                                .padding(.horizontal, 10)
                                .frame(height: 28)
                                .background(Color.white.opacity(0.06), in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(show.name)
                    }
                }
            }
        }
        .padding(16)
        .background(.ultraThinMaterial.opacity(0.9), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .background(FootprintRoomPalette.brick.opacity(0.92), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(FootprintRoomPalette.neonInner.opacity(0.16)))
        .environment(\.colorScheme, .dark)
    }

    private func lastVisitLine(_ show: Show, sign: FootprintNeonSign) -> String {
        let parts = show.timingCalendar().dateComponents([.year, .month], from: show.effectiveDate)
        let base = BSLocalization.format("上一次是 %lld 年 %lld 月的%@", parts.year ?? 0, parts.month ?? 0, show.name)
        guard sign.steadiness == .failing else { return base }
        return base + BSLocalization.format("，已经 %lld 年多没回去了", sign.daysSinceLast / 365)
    }

    /// The words a sign maker would bend: the city prefix and "Livehouse" move to a sub-line.
    static func signText(for name: String, cities: [String] = []) -> (title: String, subtitle: String?) {
        // "杭州奥体中心" bends as "奥体中心": a sign already hangs in its own city.
        let unprefixed = cities.reduce(name) { text, city in
            let stripped = text.replacingOccurrences(of: city, with: "")
            return stripped.trimmingCharacters(in: .whitespaces).count > 1 ? stripped : text
        }
        let tokens = unprefixed.split(whereSeparator: \.isWhitespace).map(String.init)
        let isLivehouse: (String) -> Bool = { $0.caseInsensitiveCompare("livehouse") == .orderedSame }
        let kept = tokens.filter { !cities.contains($0) && !isLivehouse($0) }
        guard !kept.isEmpty else { return (name, nil) }
        return (kept.joined(separator: " "), tokens.contains(where: isLivehouse) ? "LIVEHOUSE" : nil)
    }
}

/// Text bent from glass tube: layered glow, and a flicker that tells how long since the last visit.
struct FootprintNeonText: View {
    let text: String
    let font: Font
    let glow: FootprintNeonSign.Glow
    let steadiness: FootprintNeonSign.Steadiness
    var relitAt: Date?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 20, paused: reduceMotion)) { context in
            Text(text)
                .font(font)
                .foregroundStyle(FootprintRoomPalette.neonCore)
                .shadow(color: FootprintRoomPalette.neonCore, radius: 1.5)
                .shadow(color: FootprintRoomPalette.neonInner.opacity(glow >= .warm ? 1 : 0.6), radius: 5)
                .shadow(color: FootprintRoomPalette.neonOuter.opacity(glow == .full ? 0.9 : glow == .warm ? 0.55 : 0.3), radius: 14)
                .shadow(color: FootprintRoomPalette.neonOuter.opacity(glow == .full ? 0.5 : 0.2), radius: 30)
                .opacity(reduceMotion ? 1 : brightness(at: context.date))
        }
    }

    private func brightness(at date: Date) -> Double {
        if let relitAt {
            let since = date.timeIntervalSince(relitAt)
            if since < 1.4 { return Self.powerOn(since) }
            return 1
        }
        let t = date.timeIntervalSinceReferenceDate
        switch steadiness {
        case .steady:
            return 1
        case .flickering:
            let phase = t.truncatingRemainder(dividingBy: 5) / 5
            if (0.89..<0.9).contains(phase) { return 0.35 }
            if (0.93..<0.94).contains(phase) { return 0.5 }
            return 1
        case .failing:
            let phase = t.truncatingRemainder(dividingBy: 2.6) / 2.6
            switch phase {
            case 0.10..<0.12, 0.42..<0.45, 0.71..<0.74: return 0.2
            default: return 0.72
            }
        }
    }

    /// Two stutters, then the tube catches.
    private static func powerOn(_ since: TimeInterval) -> Double {
        let p = since / 1.4
        switch p {
        case ..<0.1: return 0.1
        case 0.14..<0.26: return 0.15
        case 0.30..<0.38: return 0.3
        default: return 1
        }
    }
}

/// Dark brick behind the signs, with warm light spilling from them.
private struct FootprintBrickWall: View {
    var body: some View {
        Canvas { canvas, size in
            canvas.fill(Path(CGRect(origin: .zero, size: size)), with: .color(FootprintRoomPalette.brick))
            let rowHeight: CGFloat = 24, brickWidth: CGFloat = 52
            var row = 0
            var y: CGFloat = 0
            while y < size.height {
                canvas.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 2)), with: .color(.black.opacity(0.42)))
                var x: CGFloat = row % 2 == 0 ? 0 : -brickWidth / 2
                while x < size.width {
                    canvas.fill(Path(CGRect(x: x, y: y, width: 2, height: rowHeight)), with: .color(.black.opacity(0.3)))
                    x += brickWidth
                }
                y += rowHeight
                row += 1
            }
        }
        .overlay {
            RadialGradient(colors: [FootprintRoomPalette.neonOuter.opacity(0.16), .clear], center: .init(x: 0.5, y: 0.25), startRadius: 0, endRadius: 320)
        }
        .overlay {
            RadialGradient(colors: [.clear, .black.opacity(0.75)], center: .center, startRadius: 160, endRadius: 560)
        }
        .accessibilityHidden(true)
    }
}
