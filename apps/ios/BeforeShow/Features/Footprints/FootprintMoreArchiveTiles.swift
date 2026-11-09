import SwiftUI

/// Everything the four newer rooms need, built once per render of the doors.
struct FootprintMoreArchiveData {
    let songs: [FootprintSetlistSong]
    let bands: [FootprintCompanionBand]
    let shelves: [FootprintMerchShelf]
    let hasLedger: Bool

    init(archive: FootprintArchiveSnapshot, memories: [ShowSetlistMemory], merch: [MerchItem]) {
        songs = FootprintSetlistArchive.songs(memories: memories, shows: archive.shows)
        bands = FootprintCompanionArchive.bands(shows: archive.shows)
        shelves = FootprintMerchArchive.shelves(items: merch, shows: archive.shows)
        hasLedger = archive.shows.contains(where: \.hasAnySpending)
    }
}

extension FootprintEntryTiles {
    func setlistTile(_ songs: [FootprintSetlistSong]) -> some View {
        let repeated = songs.filter { $0.count > 1 }.count
        let subtitle = repeated > 0
            ? BSLocalization.format("%1$lld 首 · %2$lld 首听过不止一次", songs.count, repeated)
            : BSLocalization.format("%lld 首", songs.count)
        return tile(title: BSLocalization.text("曲目"), subtitle: subtitle, background: AnyShapeStyle(FootprintRoomPalette.setlistFloor)) {
            VStack(alignment: .leading, spacing: 3) {
                ForEach(songs.prefix(3)) { song in
                    Text(song.title)
                        .font(.custom("Noteworthy-Bold", size: 13))
                        .lineLimit(1)
                }
            }
            .foregroundStyle(FootprintRoomPalette.setlistInk)
            .padding(10)
            .frame(width: 96, height: 80, alignment: .topLeading)
            .background(FootprintRoomPalette.setlistPaper, in: RoundedRectangle(cornerRadius: 2))
            .overlay(alignment: .top) {
                Rectangle().fill(FootprintRoomPalette.tape.opacity(0.85)).frame(width: 34, height: 10).offset(y: -5)
            }
            .rotationEffect(.degrees(-4))
            .shadow(color: .black.opacity(0.6), radius: 8, y: 6)
            .accessibilityHidden(true)
        }
    }

    func companionsTile(_ bands: [FootprintCompanionBand]) -> some View {
        let subtitle = bands.first.map {
            BSLocalization.format("%1$lld 位 · 和%2$@最多", bands.count, $0.name)
        } ?? ""
        let maxCount = CGFloat(max(1, bands.first?.count ?? 1))
        return tile(title: BSLocalization.text("同行"), subtitle: subtitle, background: AnyShapeStyle(Color(white: 0.07))) {
            VStack(alignment: .leading, spacing: 7) {
                ForEach(Array(bands.prefix(3).enumerated()), id: \.offset) { index, band in
                    HStack(spacing: 0) {
                        FootprintRoomPalette.wristbands[index % FootprintRoomPalette.wristbands.count]
                            .frame(width: 50 + 50 * CGFloat(band.count) / maxCount, height: 16)
                            .clipShape(UnevenRoundedRectangle(bottomTrailingRadius: 3, topTrailingRadius: 3))
                        RoundedRectangle(cornerRadius: 2).fill(FootprintRoomPalette.clasp).frame(width: 10, height: 14)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityHidden(true)
        }
    }

    func merchTile(_ shelves: [FootprintMerchShelf]) -> some View {
        let items = shelves.flatMap(\.items)
        return tile(
            title: BSLocalization.text("周边柜"),
            subtitle: BSLocalization.format("%1$lld 件 · %2$lld 层", items.count, shelves.count),
            background: AnyShapeStyle(FootprintRoomPalette.cabinetRoom)
        ) {
            VStack(spacing: 0) {
                HStack(alignment: .bottom, spacing: 6) {
                    ForEach(items.prefix(3)) { item in
                        FootprintLocalPhoto(url: item.photoURL(cutout: true), contentMode: item.cutoutRelativePath == nil ? .fill : .fit)
                            .frame(width: 30, height: 38)
                            .clipShape(RoundedRectangle(cornerRadius: item.cutoutRelativePath == nil ? 5 : 0))
                    }
                }
                Rectangle().fill(FootprintRoomPalette.glassShelf.opacity(0.2)).frame(width: 110, height: 5)
            }
            .padding(10)
            .background(LinearGradient(colors: [FootprintRoomPalette.cabinetLight.opacity(0.14), .clear], startPoint: .top, endPoint: .bottom))
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(FootprintRoomPalette.cabinetFrame, lineWidth: 4))
            .accessibilityHidden(true)
        }
    }

    func badgesTile(_ badges: [FootprintBadge]) -> some View {
        let earned = badges.reduce(0) { $0 + $1.tier }
        let fresh = FootprintBadgeSeenStore(defaults: badgeDefaults).unseen(in: badges).count
        let subtitle = fresh > 0
            ? BSLocalization.format("已得 %1$lld 枚 · 新 %2$lld", earned, fresh)
            : BSLocalization.format("已得 %lld 枚", earned)
        return tile(title: BSLocalization.text("徽章"), subtitle: subtitle, background: AnyShapeStyle(Color(white: 0.07))) {
            HStack(spacing: -10) {
                ForEach(Array(badges.prefix(3).enumerated()), id: \.element.id) { index, badge in
                    FootprintBadgePin(badge: badge, size: 52)
                        .rotationEffect(.degrees(Double(index - 1) * 8))
                        .zIndex(Double(3 - index))
                }
            }
            .overlay(alignment: .topTrailing) {
                if fresh > 0 {
                    Circle().fill(BSColor.Stage.accent).frame(width: 8, height: 8).offset(x: 6, y: -2)
                }
            }
        }
    }

    var ledgerTile: some View {
        let recorded = archive.shows.filter(\.hasAnySpending).count
        return tile(
            title: BSLocalization.text("账本"),
            subtitle: BSLocalization.format("记了 %lld 场", recorded),
            background: AnyShapeStyle(Color(white: 0.06))
        ) {
            VStack(spacing: 5) {
                Capsule().fill(FootprintRoomPalette.receiptInk).frame(width: 40, height: 4)
                ForEach(0..<4, id: \.self) { row in
                    HStack {
                        Capsule().fill(FootprintRoomPalette.receiptInk.opacity(0.35)).frame(width: [34, 28, 38, 24][row], height: 3)
                        Spacer()
                        Capsule().fill(FootprintRoomPalette.receiptInk.opacity(0.55)).frame(width: 14, height: 3)
                    }
                }
            }
            .padding(10)
            .frame(width: 72, height: 86, alignment: .top)
            .background(FootprintRoomPalette.receiptPaper)
            .rotationEffect(.degrees(3))
            .shadow(color: .black.opacity(0.6), radius: 8, y: 6)
            .accessibilityHidden(true)
        }
    }
}
