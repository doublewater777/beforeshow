import SwiftData
import SwiftUI

/// 歌单 / 周边 / 花销各一张卡：内容简单时是半卡，有东西可看时占整行。每张卡只开一层：
/// 歌单、花销各一张 sheet，周边直接相机或相册；保存结果留在卡里。
struct ShowRecordCard: View {
    let show: Show
    let kind: CurrentShowRecordKind
    var phase: HomeShowPhase = .ended
    let surface: ShowModuleSurface

    @Query private var setlist: [ShowSetlistMemory]
    @State private var isShowingSetlist = false
    @State private var isShowingSpending = false
    @State private var merchSource: MerchCaptureSource?
    @State private var merchFailed = false
    @State private var editingMerch: MerchItem?
    @State private var viewingMerch: MerchItem?
    @Environment(\.modelContext) private var modelContext

    init(show: Show, kind: CurrentShowRecordKind, phase: HomeShowPhase = .ended, surface: ShowModuleSurface) {
        self.show = show
        self.kind = kind
        self.phase = phase
        self.surface = surface
        let showID = show.id
        _setlist = Query(filter: #Predicate<ShowSetlistMemory> { $0.showID == showID })
    }

    static func facts(show: Show, setlist: [ShowSetlistMemory]) -> CurrentShowRecordFacts {
        CurrentShowRecordFacts(
            setlistCount: setlist.count,
            playedSetlistCount: setlist.filter(\.isPlayed).count,
            merchCount: show.merchItems.count,
            ticketPriceText: show.formattedSpending(show.ticketPrice),
            travelCostText: show.formattedSpending(show.travelCost)
        )
    }

    var body: some View {
        let facts = Self.facts(show: show, setlist: setlist)
        let row = CurrentShowRecordKit.row(kind, phase: phase, facts: facts)
        let isFull = CurrentShowRecordKit.width(kind, phase: phase, facts: facts) == .full
        Group {
            if kind == .merch {
                if isFull {
                    VStack(alignment: .leading, spacing: 12) {
                        MerchCaptureMenu(source: $merchSource) { header(row) }.buttonStyle(.plain)
                        MerchStrip(
                            items: show.merchItems.sorted { $0.createdAt < $1.createdAt },
                            onView: { viewingMerch = $0 },
                            onEdit: { editingMerch = $0 },
                            onDelete: { item in Task { try? await MerchCaptureCoordinator.delete(item, in: modelContext) } }
                        )
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .showModuleCard(surface)
                } else {
                    MerchCaptureMenu(source: $merchSource) { half(row) }.buttonStyle(.plain)
                }
            } else {
                Button {
                    if kind == .setlist { isShowingSetlist = true } else { isShowingSpending = true }
                } label: {
                    if isFull { full(row, facts: facts) } else { half(row) }
                }
                .buttonStyle(.plain)
            }
        }
        .animation(.easeOut(duration: 0.2), value: row)
        .sheet(isPresented: $isShowingSetlist) { ShowSetlistSheet(show: show, forcedPhase: phase) }
        .sheet(isPresented: $isShowingSpending) { ShowSpendingSheet(show: show) }
        .sheet(item: $editingMerch) { MerchEditSheet(item: $0) }
        .fullScreenCover(item: $viewingMerch) { item in
            if let url = item.photoURL(cutout: false) { BSSingleImageViewer(source: .file(url)) }
        }
        .merchCapture($merchSource, show: show) { saved in merchFailed = !saved }
        .onChange(of: merchSource) { _, source in if source != nil { merchFailed = false } }
    }

    private var failureText: String? {
        kind == .merch && merchFailed ? BSLocalization.text("照片没有保存，请重试") : nil
    }

    private func header(_ row: CurrentShowRecordRow) -> some View {
        ShowModuleHeader(title: row.title, status: failureText ?? row.subtitle, action: row.action, emphasizesAction: row.emphasizesAction)
            .contentShape(Rectangle())
    }

    private func half(_ row: CurrentShowRecordRow) -> some View {
        ShowModuleIconCard(
            title: row.title,
            status: failureText ?? row.subtitle,
            action: row.action,
            emphasizesAction: row.emphasizesAction,
            iconName: row.iconName,
            surface: surface
        )
    }

    private func full(_ row: CurrentShowRecordRow, facts: CurrentShowRecordFacts) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            header(row)
            if kind == .setlist {
                PlayedSongsPreview(memories: setlist)
            } else {
                HStack(alignment: .top, spacing: 12) {
                    if let price = facts.ticketPriceText { amount(BSLocalization.text("票价"), price) }
                    if let travel = facts.travelCostText { amount(BSLocalization.text("路费"), travel) }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .showModuleCard(surface)
    }

    private func amount(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(BSColor.Stage.muted)
            Text(value)
                .font(BSFont.Editorial.serif(20))
                .foregroundStyle(BSColor.Stage.foreground)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
        ShowSetlistRecording.played(memories)
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
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

/// The merch kept from this show, under the 周边 row, each with its name: tap to look at it full screen, hold to edit or delete.
private struct MerchStrip: View {
    let items: [MerchItem]
    let onView: (MerchItem) -> Void
    let onEdit: (MerchItem) -> Void
    let onDelete: (MerchItem) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(items) { item in
                    let hasCutout = item.cutoutRelativePath != nil
                    Button { onView(item) } label: {
                        VStack(spacing: 4) {
                            FootprintLocalPhoto(url: item.photoURL(cutout: true), contentMode: hasCutout ? .fit : .fill)
                                .frame(width: 56, height: 64)
                                .background(Color.white.opacity(0.05))
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            Text(item.displayName)
                                .font(.system(size: 11))
                                .foregroundStyle(BSColor.Stage.muted)
                                .lineLimit(1)
                                .frame(width: 56)
                        }
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button { onEdit(item) } label: { Label(BSLocalization.text("编辑"), systemImage: "pencil") }
                        Button(role: .destructive) { onDelete(item) } label: { Label(BSLocalization.text("删除"), systemImage: "trash") }
                    }
                    .accessibilityLabel(item.displayName)
                }
            }
        }
    }
}
