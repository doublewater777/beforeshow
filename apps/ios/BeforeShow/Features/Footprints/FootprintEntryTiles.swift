import SwiftData
import SwiftUI

/// One door per Footprints room; each tile is a live miniature of the room behind it.
struct FootprintEntryTiles: View {
    let archive: FootprintArchiveSnapshot
    let covers: [UUID: FootprintCover]
    let allShows: [Show]
    var columnCount = 2

    @Query private var setlistMemories: [ShowSetlistMemory]
    @Query private var merchItems: [MerchItem]
    @Query private var fragments: [MemoryFragment]
    @Query private var assets: [ShowAsset]
    @State private var isReadingBook = false

    private enum Door: Hashable { case years, artists, venues, cities, badges, candle, setlist, companions, merch, ledger, book }

    var body: some View {
        let anniversary = FootprintAnniversaryFinder.featured(in: FootprintAnniversaryFinder.upcoming(in: archive.shows))
        let more = FootprintMoreArchiveData(archive: archive, memories: setlistMemories, merch: merchItems)
        let badges = FootprintBadgeCatalog.badges(FootprintBadgeCatalog.facts(archive: archive, memories: setlistMemories, merch: merchItems, fragments: fragments, assets: assets))
        let doors: [Door] = [.years, .artists, .venues, .cities, .badges] + (anniversary == nil ? [] : [.candle])
            + (more.songs.isEmpty ? [] : [.setlist])
            + (more.bands.isEmpty ? [] : [.companions])
            + (more.shelves.isEmpty ? [] : [.merch])
            + (more.hasLedger ? [.ledger] : [])
            + [.book]
        VStack(spacing: 12) {
            ForEach(Array(stride(from: 0, to: doors.count, by: columnCount)), id: \.self) { start in
                HStack(spacing: 12) {
                    let end = min(start + columnCount, doors.count)
                    ForEach(doors[start..<end], id: \.self) { door in
                        link(door, anniversary: anniversary, more: more, badges: badges)
                    }
                    ForEach(0..<(columnCount - (end - start)), id: \.self) { _ in
                        Color.clear.frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .fullScreenCover(isPresented: $isReadingBook) {
            FootprintBookView(
                book: FootprintBook(archived: archive.shows, next: FootprintStagePolicy.nextUpcoming(allShows, archived: archive.shows, now: Date())),
                archive: archive,
                covers: covers
            )
        }
    }

    @ViewBuilder
    private func link(_ door: Door, anniversary: FootprintAnniversary?, more: FootprintMoreArchiveData, badges: [FootprintBadge]) -> some View {
        switch door {
        case .years:
            NavigationLink { FootprintVinylYearsView(archive: archive, covers: covers) } label: { yearsTile }
                .buttonStyle(BSPressStyle())
        case .artists:
            NavigationLink { FootprintConstellationView(archive: archive) } label: { artistsTile }
                .buttonStyle(BSPressStyle())
        case .venues:
            NavigationLink { FootprintNeonVenuesView(archive: archive) } label: { venuesTile }
                .buttonStyle(BSPressStyle())
        case .cities:
            NavigationLink { FootprintCityMapView(archive: archive, covers: covers, allShows: allShows) } label: { citiesTile }
                .buttonStyle(BSPressStyle())
        case .candle:
            if let anniversary {
                NavigationLink {
                    FootprintCandleView(archive: archive, covers: covers, anniversary: anniversary)
                } label: { candleTile(anniversary) }
                    .buttonStyle(BSPressStyle())
            }
        case .badges:
            NavigationLink { FootprintBadgeWallView(archive: archive) } label: { badgesTile(badges) }
                .buttonStyle(BSPressStyle())
        case .setlist:
            NavigationLink { FootprintSetlistView(archive: archive, songs: more.songs) } label: { setlistTile(more.songs) }
                .buttonStyle(BSPressStyle())
        case .companions:
            NavigationLink { FootprintCompanionBandsView(archive: archive, bands: more.bands) } label: { companionsTile(more.bands) }
                .buttonStyle(BSPressStyle())
        case .merch:
            NavigationLink { FootprintMerchCabinetView(archive: archive, shelves: more.shelves) } label: { merchTile(more.shelves) }
                .buttonStyle(BSPressStyle())
        case .ledger:
            NavigationLink { FootprintLedgerView(archive: archive) } label: { ledgerTile }
                .buttonStyle(BSPressStyle())
        case .book:
            Button { isReadingBook = true } label: { bookTile }
                .buttonStyle(BSPressStyle())
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
        return tile(title: BSLocalization.text("城市"), subtitle: subtitle, background: AnyShapeStyle(FootprintRoomPalette.mapNight)) {
            FootprintMiniCityLights(counts: stops.filter { !$0.isNext }.map(\.count))
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

    private var bookTile: some View {
        let years = [archive.years.last?.year, archive.years.first?.year].compactMap { $0 }
        let span = years.first == years.last ? years.first.map(String.init) ?? "" : "\(years[0])–\(years[1])"
        return tile(
            title: BSLocalization.text("回忆册"),
            subtitle: BSLocalization.format("%1$@ · %2$lld 页", span, archive.shows.count + archive.years.count + 4),
            background: AnyShapeStyle(FootprintRoomPalette.bookRoom)
        ) {
            FootprintMiniBook(cover: archive.shows.first.map { show in AnyView(FootprintResolvedCoverImage(show: show, cover: covers[show.id])) })
        }
    }

    func tile<Art: View>(
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

/// A closed cloth volume with the latest poster in its window.
private struct FootprintMiniBook: View {
    let cover: AnyView?

    var body: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 3).fill(FootprintRoomPalette.paperEdge).frame(width: 62, height: 84).offset(x: 4, y: 3)
            ZStack {
                LinearGradient(colors: [FootprintRoomPalette.bookCloth, FootprintRoomPalette.bookClothDeep], startPoint: .topLeading, endPoint: .bottomTrailing)
                Rectangle().stroke(FootprintRoomPalette.foil.opacity(0.4)).padding(5).padding(.leading, 5)
                VStack(spacing: 5) {
                    (cover ?? AnyView(Color.black))
                        .frame(width: 28, height: 37)
                        .clipped()
                    Text(BSLocalization.text("足迹"))
                        .font(.system(size: 11, weight: .black, design: .serif))
                        .foregroundStyle(FootprintRoomPalette.foil)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                .padding(.leading, 5)
            }
            .frame(width: 62, height: 84)
            .clipShape(UnevenRoundedRectangle(topLeadingRadius: 2, bottomLeadingRadius: 2, bottomTrailingRadius: 5, topTrailingRadius: 5))
        }
        .rotationEffect(.degrees(-6))
        .shadow(color: .black.opacity(0.6), radius: 10, y: 8)
        .accessibilityHidden(true)
    }
}

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

/// The city map in miniature: a few warm lights on the dark, biggest where you went most.
private struct FootprintMiniCityLights: View {
    let counts: [Int]

    var body: some View {
        Canvas { canvas, size in
            // Fixed spots so the tile reads as a map, sized by your busiest cities.
            let spots: [CGPoint] = [CGPoint(x: 0.62, y: 0.55), CGPoint(x: 0.78, y: 0.36), CGPoint(x: 0.3, y: 0.42), CGPoint(x: 0.5, y: 0.26), CGPoint(x: 0.7, y: 0.78)]
            let ranked = counts.sorted(by: >)
            for (spot, count) in zip(spots, ranked) {
                let r = 6 + sqrt(Double(count)) * 3.4
                let p = CGPoint(x: spot.x * size.width, y: spot.y * size.height)
                canvas.fill(
                    Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)),
                    with: .radialGradient(
                        Gradient(colors: [FootprintRoomPalette.bulb, FootprintRoomPalette.bulbGlow.opacity(0.6), .clear]),
                        center: p, startRadius: 0, endRadius: r
                    )
                )
                canvas.fill(Path(ellipseIn: CGRect(x: p.x - 1.5, y: p.y - 1.5, width: 3, height: 3)), with: .color(FootprintRoomPalette.neonCore))
            }
        }
        .accessibilityHidden(true)
    }
}
