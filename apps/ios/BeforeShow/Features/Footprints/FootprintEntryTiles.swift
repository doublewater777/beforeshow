import SwiftUI

/// One door per Footprints room; each tile is a live miniature of the room behind it.
struct FootprintEntryTiles: View {
    let archive: FootprintArchiveSnapshot
    let covers: [UUID: FootprintCover]
    let allShows: [Show]

    private enum Door: Hashable { case years, artists, venues, cities, pass, candle }

    var body: some View {
        let anniversary = FootprintAnniversaryFinder.featured(in: FootprintAnniversaryFinder.upcoming(in: archive.shows))
        let doors: [Door] = [.years, .artists, .venues, .cities, .pass] + (anniversary == nil ? [] : [.candle])
        VStack(spacing: 12) {
            ForEach(Array(stride(from: 0, to: doors.count, by: 2)), id: \.self) { start in
                HStack(spacing: 12) {
                    ForEach(doors[start..<min(start + 2, doors.count)], id: \.self) { door in
                        link(door, anniversary: anniversary)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func link(_ door: Door, anniversary: FootprintAnniversary?) -> some View {
        switch door {
        case .years:
            NavigationLink { FootprintVinylYearsView(archive: archive, covers: covers) } label: { yearsTile }
                .buttonStyle(FootprintPressStyle())
        case .artists:
            NavigationLink { FootprintConstellationView(archive: archive) } label: { artistsTile }
                .buttonStyle(FootprintPressStyle())
        case .venues:
            NavigationLink { FootprintNeonVenuesView(archive: archive) } label: { venuesTile }
                .buttonStyle(FootprintPressStyle())
        case .cities:
            NavigationLink { FootprintTourShirtView(archive: archive, covers: covers, allShows: allShows) } label: { citiesTile }
                .buttonStyle(FootprintPressStyle())
        case .pass:
            NavigationLink { FootprintBackstagePassView(archive: archive, covers: covers) } label: { passTile }
                .buttonStyle(FootprintPressStyle())
        case .candle:
            if let anniversary {
                NavigationLink {
                    FootprintCandleView(archive: archive, covers: covers, anniversary: anniversary)
                } label: { candleTile(anniversary) }
                    .buttonStyle(FootprintPressStyle())
            }
        }
    }

    // MARK: Tiles

    private var yearsTile: some View {
        let peak = archive.years.max { $0.shows.count == $1.shows.count ? $0.year > $1.year : $0.shows.count < $1.shows.count }
        let subtitle = archive.years.count > 1 && peak != nil
            ? BSLocalization.format("%lld 张唱片 · %@ 最满", archive.years.count, String(peak!.year))
            : BSLocalization.format("%lld 张唱片", archive.years.count)
        return tile(title: BSLocalization.text("这些年"), subtitle: subtitle, background: AnyShapeStyle(Color(white: 0.09))) {
            FootprintMiniRecord(show: archive.shows.first, cover: archive.shows.first.flatMap { covers[$0.id] })
        }
    }

    private var artistsTile: some View {
        let subtitle = archive.artists.first.map {
            BSLocalization.format("%lld 颗星 · 最亮%@", archive.artists.count, $0.name)
        } ?? BSLocalization.format("%lld 颗星", archive.artists.count)
        let sky = LinearGradient(colors: [FootprintRoomPalette.skyTop, FootprintRoomPalette.skyBottom], startPoint: .top, endPoint: .bottom)
        return tile(title: BSLocalization.text("艺人"), subtitle: subtitle, background: AnyShapeStyle(sky)) {
            FootprintMiniSky(constellation: FootprintConstellationBuilder.make(shows: archive.shows))
        }
    }

    private var venuesTile: some View {
        let signs = FootprintStagePolicy.neonSigns(venues: archive.venueArchiveItems)
        let featured = signs.first
        let subtitle: String = {
            if let failing = signs.first(where: { $0.steadiness == .failing }) {
                return BSLocalization.format("%lld 块招牌 · %@ 在闪", archive.venues.count, failing.venue.name)
            }
            return BSLocalization.format("%lld 块招牌", archive.venues.count)
        }()
        return tile(title: BSLocalization.text("场馆"), subtitle: subtitle, background: AnyShapeStyle(FootprintRoomPalette.brick)) {
            FootprintNeonText(
                text: featured.map { FootprintNeonVenuesView.signText(for: $0.venue.name, cities: $0.venue.cities).title } ?? "LIVE",
                font: .system(size: 30, weight: .heavy, design: .rounded),
                glow: featured?.glow ?? .faint,
                steadiness: featured?.steadiness ?? .steady
            )
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .padding(.horizontal, 12)
        }
    }

    private var citiesTile: some View {
        let stops = FootprintStagePolicy.tourStops(cities: archive.cityArchiveItems, archive: archive, allShows: allShows)
        let next = stops.first(where: \.isNext)
        let subtitle = next.map {
            BSLocalization.format("%lld 站 · 下一站%@", archive.cities.count, $0.city)
        } ?? BSLocalization.format("%lld 站", archive.cities.count)
        return tile(title: BSLocalization.text("城市"), subtitle: subtitle, background: AnyShapeStyle(FootprintRoomPalette.cotton)) {
            VStack(spacing: 2) {
                Text(BSLocalization.format("THE %lld SHOWS", archive.shows.count))
                    .font(.system(size: 21, weight: .black).width(.compressed))
                Text(BSLocalization.text("TOUR"))
                    .font(.system(size: 11, weight: .black).width(.compressed))
                    .tracking(6)
            }
            .foregroundStyle(FootprintRoomPalette.printInk)
        }
    }

    private var passTile: some View {
        let pins = FootprintMilestoneBuilder.make(shows: archive.shows)
        let earned = pins.filter { !$0.isLocked }.count
        let subtitle: String = {
            if case let .locked(target, remaining)? = pins.last?.kind {
                return BSLocalization.format("%lld 枚徽章 · 第 %lld 场还差 %lld", earned, target, remaining)
            }
            return BSLocalization.format("%lld 枚徽章", earned)
        }()
        return tile(title: BSLocalization.text("现场护照"), subtitle: subtitle, background: AnyShapeStyle(Color(white: 0.07))) {
            FootprintMiniPass()
        }
    }

    private func candleTile(_ anniversary: FootprintAnniversary) -> some View {
        let show = archive.shows(for: [anniversary.showID]).first
        let subtitle = BSLocalization.format(
            "%@ · %@ %lld 周年",
            String(format: "%02d.%02d", anniversary.month, anniversary.day),
            show?.name ?? "",
            anniversary.years
        )
        return tile(title: BSLocalization.text("那年今日"), subtitle: subtitle, background: AnyShapeStyle(FootprintRoomPalette.candleRoom)) {
            FootprintCandleFigure(isLit: true, scale: 0.32)
        }
    }

    private func tile<Art: View>(
        title: String,
        subtitle: String,
        background: AnyShapeStyle,
        @ViewBuilder art: () -> Art
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            art()
                .frame(maxWidth: .infinity)
                .frame(height: 96)
            Spacer(minLength: 0)
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(BSColor.Stage.foreground)
            Text(subtitle)
                .font(.system(size: 11))
                .foregroundStyle(BSColor.Stage.muted)
                .lineLimit(1)
                .padding(.top, 2)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 150)
        .background(background, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.white.opacity(0.07)))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Miniatures

private struct FootprintMiniRecord: View {
    let show: Show?
    let cover: FootprintCover?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var spinning = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            FootprintRecordDisc(diameter: 88, labelDiameter: 30) {
                if let show { FootprintResolvedCoverImage(show: show, cover: cover) }
            }
            .rotationEffect(.degrees(spinning ? 360 : 0))
            .animation(reduceMotion ? nil : .linear(duration: 4).repeatForever(autoreverses: false), value: spinning)
            Capsule()
                .fill(FootprintRoomPalette.brass)
                .frame(width: 3, height: 62)
                .rotationEffect(.degrees(20), anchor: .top)
                .offset(x: 10, y: -4)
        }
        .onAppear { spinning = true }
    }
}

private struct FootprintMiniSky: View {
    let constellation: FootprintConstellation

    var body: some View {
        let shown = Array(constellation.stars.prefix(8))
        let names = Set(shown.map(\.name))
        Canvas { canvas, size in
            // Background dust stands for everyone not drawn as a named star.
            var seed: UInt64 = 11
            for _ in 0..<min(constellation.dustCount + 12, 40) {
                seed = seed &* 6364136223846793005 &+ 1442695040888963407
                let x = Double(seed >> 40) / Double(1 << 24) * size.width
                seed = seed &* 6364136223846793005 &+ 1442695040888963407
                let y = Double(seed >> 40) / Double(1 << 24) * size.height
                canvas.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 1.2, height: 1.2)), with: .color(FootprintRoomPalette.starlight.opacity(0.5)))
            }
            let place: (CGPoint) -> CGPoint = { CGPoint(x: $0.x * size.width, y: $0.y * size.height) }
            let byName = Dictionary(uniqueKeysWithValues: shown.map { ($0.name, $0) })
            for edge in constellation.edges where names.contains(edge.from) && names.contains(edge.to) {
                guard let a = byName[edge.from], let b = byName[edge.to] else { continue }
                var line = Path()
                line.move(to: place(a.position))
                line.addLine(to: place(b.position))
                canvas.stroke(line, with: .color(FootprintRoomPalette.starlight.opacity(0.4)), lineWidth: 0.8)
            }
            for star in shown {
                let r: CGFloat = star.count >= 3 ? 3.2 : star.count == 2 ? 2.2 : 1.4
                let p = place(star.position)
                canvas.fill(Path(ellipseIn: CGRect(x: p.x - r * 3, y: p.y - r * 3, width: r * 6, height: r * 6)), with: .color(FootprintRoomPalette.starlight.opacity(0.12)))
                canvas.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)), with: .color(.white))
            }
        }
        .accessibilityHidden(true)
    }
}

private struct FootprintMiniPass: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(LinearGradient(colors: [Color(white: 0.13), Color(white: 0.06)], startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(width: 66, height: 86)
            .overlay {
                VStack(spacing: 2) {
                    Text(BSLocalization.text("AAA"))
                        .font(.system(size: 22, weight: .black).width(.compressed))
                        .foregroundStyle(BSColor.Stage.heroWarmGold)
                    Text(BSLocalization.text("ALL ACCESS"))
                        .font(.system(size: 7, weight: .medium).width(.condensed))
                        .tracking(2)
                        .foregroundStyle(BSColor.Stage.muted)
                }
            }
            .overlay(FootprintHologramSheen(phase: 0.5).clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous)))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.white.opacity(0.1)))
            .rotationEffect(.degrees(-4))
            .shadow(color: .black.opacity(0.6), radius: 10, y: 8)
            .accessibilityHidden(true)
    }
}
