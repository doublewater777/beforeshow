import SwiftData
import SwiftUI

/// 当前 tab 模块下方的「歌单 / 此刻 / 留下的东西」：与足迹详情同一组记录行，换成首页的磨砂模块。
struct CurrentShowRecordSection: View {
    let show: Show
    let phase: HomeShowPhase

    var body: some View {
        if let title = CurrentShowRecordKit.title(for: phase) {
            VStack(alignment: .leading, spacing: 10) {
                Text(title)
                    .font(BSFont.Editorial.caps(13))
                    .tracking(1.5)
                    .foregroundStyle(BSColor.Stage.foreground)
                    .padding(.leading, 4)
                    .accessibilityAddTraits(.isHeader)
                ShowRecordRows(show: show, kinds: CurrentShowRecordKit.kinds(for: phase), phase: phase)
                    .bsGlassCard(cornerRadius: 24)
            }
        }
    }
}

/// 每行只开一层：现场听到了 / 花销各一张 sheet，周边直接相机或相册；保存结果留在行内。
struct ShowRecordRows: View {
    let show: Show
    let kinds: [CurrentShowRecordKind]
    var phase: HomeShowPhase = .ended

    @Query private var setlist: [ShowSetlistMemory]
    @State private var isShowingSetlist = false
    @State private var isShowingSpending = false
    @State private var merchSource: MerchCaptureSource?
    @State private var merchFailed = false

    init(show: Show, kinds: [CurrentShowRecordKind], phase: HomeShowPhase = .ended) {
        self.show = show
        self.kinds = kinds
        self.phase = phase
        let showID = show.id
        _setlist = Query(filter: #Predicate<ShowSetlistMemory> { $0.showID == showID })
    }

    private var rows: [CurrentShowRecordRow] {
        let facts = CurrentShowRecordFacts(
            setlistCount: setlist.count,
            playedSetlistCount: setlist.filter(\.isPlayed).count,
            merchCount: show.merchItems.count,
            ticketPriceText: show.formattedSpending(show.ticketPrice),
            travelCostText: show.formattedSpending(show.travelCost)
        )
        return kinds.map { CurrentShowRecordKit.row($0, phase: phase, facts: facts) }
    }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                if index > 0 { Divider().overlay(Color.white.opacity(0.1)).padding(.leading, 52) }
                if row.kind == .merch {
                    MerchCaptureMenu(source: $merchSource) { label(row) }.buttonStyle(.plain)
                } else {
                    Button {
                        if row.kind == .setlist { isShowingSetlist = true } else { isShowingSpending = true }
                    } label: {
                        VStack(spacing: 0) {
                            label(row)
                            // After the show the songs heard are listed right under their row.
                            if row.kind == .setlist, phase == .ended || phase == .inactive, setlist.contains(where: \.isPlayed) {
                                PlayedSongsPreview(memories: setlist)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .sheet(isPresented: $isShowingSetlist) { ShowSetlistSheet(show: show, forcedPhase: phase) }
        .sheet(isPresented: $isShowingSpending) { ShowSpendingSheet(show: show) }
        .merchCapture($merchSource, show: show) { saved in merchFailed = !saved }
        .onChange(of: merchSource) { _, source in if source != nil { merchFailed = false } }
    }

    private func label(_ row: CurrentShowRecordRow) -> some View {
        let failed = row.kind == .merch && merchFailed
        return HStack(spacing: 12) {
            Image(systemName: row.iconName)
                .font(.system(size: 17))
                .foregroundStyle(BSColor.Stage.foreground.opacity(row.isFilled ? 0.9 : 0.4))
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(BSColor.Stage.foreground)
                if let subtitle = failed ? BSLocalization.text("照片没有保存，请重试") : row.subtitle {
                    Text(subtitle)
                        .font(.system(size: 12.5))
                        .foregroundStyle(failed ? BSColor.Stage.live : BSColor.Stage.muted)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 10)
            Text(row.action)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(row.emphasizesAction ? BSColor.Stage.accent : BSColor.Stage.foreground.opacity(0.4))
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 60)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .animation(.easeOut(duration: 0.2), value: row)
    }
}

struct PlayedSong: Equatable {
    let title: String
    let artist: String
    let artworkURL: URL?
    let isMostSurprising: Bool
}

enum PlayedSongs {
    /// Songs ticked as played, in setlist order, named from the catalog when it has them.
    static func resolve(_ memories: [ShowSetlistMemory], catalog: [CatalogSong]) -> [PlayedSong] {
        memories
            .filter(\.isPlayed)
            .sorted {
                if let o1 = $0.order, let o2 = $1.order, o1 != o2 { return o1 < o2 }
                return $0.createdAt < $1.createdAt
            }
            .map { memory in
                let song = memory.catalogSongID.flatMap { id in catalog.first { $0.appleMusicSongID == id } }
                return PlayedSong(
                    title: song?.title ?? memory.manualTitle ?? BSLocalization.text("现场听到了"),
                    artist: song?.artistName ?? memory.manualArtistName ?? "",
                    artworkURL: song?.artworkURL.flatMap(URL.init(string:)),
                    isMostSurprising: memory.isMostSurprising
                )
            }
    }
}

/// The first few songs heard, under the 现场听到了 row; the row opens the full list.
private struct PlayedSongsPreview: View {
    let memories: [ShowSetlistMemory]
    @Query private var catalog: [CatalogSong]

    private static let limit = 3

    var body: some View {
        let songs = PlayedSongs.resolve(memories, catalog: catalog)
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(songs.prefix(Self.limit).enumerated()), id: \.offset) { _, song in
                HStack(spacing: 10) {
                    ListeningArtwork(url: song.artworkURL, title: song.title)
                        .frame(width: 36, height: 36)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(song.title)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(BSColor.Stage.foreground)
                            .lineLimit(1)
                        Text(song.artist)
                            .font(.system(size: 12))
                            .foregroundStyle(BSColor.Stage.muted)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 6)
                    if song.isMostSurprising {
                        Label(BSLocalization.text("最惊喜"), systemImage: "sparkle")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(BSColor.Stage.accent)
                    }
                }
            }
            if songs.count > Self.limit {
                Text(BSLocalization.format("还有 %lld 首", songs.count - Self.limit))
                    .font(.system(size: 12))
                    .foregroundStyle(BSColor.Stage.muted)
            }
        }
        .padding(.leading, 52)
        .padding(.trailing, 16)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}
