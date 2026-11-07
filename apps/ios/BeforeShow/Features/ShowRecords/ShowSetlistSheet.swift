import SwiftData
import SwiftUI

/// 「现场听到了」：按阵容艺人切换，从「听」已缓存的曲目里打勾；不在列表里的歌手动加。
/// 勾选只在本地暂存，点完成才写入；关闭放弃本次改动。
struct ShowSetlistSheet: View {
    let show: Show

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var artistIndex = 0
    @State private var catalog: [String: [ShowSetlistRecording.Song]] = [:]
    @State private var original: Set<ShowSetlistRecording.Song> = []
    @State private var selected: Set<ShowSetlistRecording.Song> = []
    @State private var manual: [ShowSetlistRecording.Song] = []
    @State private var draft = ""
    @State private var saveFailed = false
    @State private var toggles = 0
    @FocusState private var isDraftFocused: Bool

    private var artists: [ArtistSlot] { show.artists.filter { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty } }
    private var currentArtistName: String { artists.indices.contains(artistIndex) ? artists[artistIndex].name : "" }

    private var rows: [ShowSetlistRecording.Song] {
        let listed = catalog[currentArtistName] ?? []
        let extra = manual.filter {
            artists.count <= 1 || ShowSetlistRecording.normalized($0.artistName) == ShowSetlistRecording.normalized(currentArtistName)
        }
        return listed + extra.filter { song in !listed.contains { ShowSetlistRecording.normalized($0.title) == ShowSetlistRecording.normalized(song.title) } }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if artists.count > 1 { artistChips }
                    songList
                    if saveFailed {
                        Text(BSLocalization.text("没有保存，请重试"))
                            .font(.system(size: 13))
                            .foregroundStyle(BSColor.Stage.live)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 4)
                .padding(.bottom, 16)
            }
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom) { manualField.padding(.horizontal, 20).padding(.bottom, 8) }
            .background(Color.clear)
            .navigationTitle(BSLocalization.text("现场听到了"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                BSChromeToolbarCloseButton { dismiss() }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: commit) { Image(systemName: "checkmark") }
                        .tint(BSColor.Stage.foreground)
                        .foregroundStyle(BSColor.Stage.foreground)
                        .accessibilityLabel(BSLocalization.text("完成"))
                }
            }
        }
        .sensoryFeedback(.selection, trigger: toggles)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(.regularMaterial)
        .preferredColorScheme(.dark)
        .task { load() }
    }

    private var artistChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(artists.enumerated()), id: \.offset) { index, artist in
                    let isOn = index == artistIndex
                    Button { artistIndex = index } label: {
                        Text(artist.name)
                            .font(.system(size: 14, weight: isOn ? .semibold : .regular))
                            .foregroundStyle(isOn ? BSColor.Stage.background : BSColor.Stage.foreground.opacity(0.7))
                            .padding(.horizontal, 14)
                            .frame(height: 34)
                            .background(isOn ? AnyShapeStyle(BSColor.Stage.foreground.opacity(0.92)) : AnyShapeStyle(Color.white.opacity(0.08)), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private var songList: some View {
        if rows.isEmpty {
            Text(BSLocalization.text("还没有曲目"))
                .font(.system(size: 14))
                .foregroundStyle(BSColor.Stage.muted)
                .frame(maxWidth: .infinity, minHeight: 80)
        } else {
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element) { index, song in
                    if index > 0 { Divider().overlay(Color.white.opacity(0.12)).padding(.leading, 16) }
                    songRow(song)
                }
            }
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Color.white.opacity(0.14), lineWidth: 0.5))
        }
    }

    private func songRow(_ song: ShowSetlistRecording.Song) -> some View {
        let isOn = selected.contains(song)
        return Button {
            if isOn { selected.remove(song) } else { selected.insert(song) }
            toggles += 1
        } label: {
            HStack {
                Text(song.title)
                    .font(.system(size: 16, weight: isOn ? .semibold : .regular))
                    .foregroundStyle(isOn ? BSColor.Stage.foreground : BSColor.Stage.foreground.opacity(0.6))
                    .lineLimit(1)
                Spacer(minLength: 12)
                ZStack {
                    Circle().fill(isOn ? BSColor.Stage.foreground : .clear)
                    Circle().strokeBorder(Color.white.opacity(isOn ? 0 : 0.25), lineWidth: 1.5)
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(BSColor.Stage.background)
                        .opacity(isOn ? 1 : 0)
                }
                .frame(width: 24, height: 24)
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private var manualField: some View {
        HStack(spacing: 10) {
            Image(systemName: "plus")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(BSColor.Stage.muted)
            TextField(BSLocalization.text("不在列表里的歌"), text: $draft)
                .font(.system(size: 15))
                .foregroundStyle(BSColor.Stage.foreground)
                .focused($isDraftFocused)
                .submitLabel(.done)
                .onSubmit(addDraft)
        }
        .padding(.horizontal, 16)
        .frame(height: 50)
        .background(Color.white.opacity(0.06), in: Capsule())
        .overlay(Capsule().stroke(Color.white.opacity(0.14), lineWidth: 0.5))
    }

    private func addDraft() {
        let title = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        let song = ShowSetlistRecording.Song(catalogSongID: nil, title: title, artistName: currentArtistName)
        if !rows.contains(where: { ShowSetlistRecording.normalized($0.title) == ShowSetlistRecording.normalized(title) }) {
            manual.append(song)
        }
        if let existing = rows.first(where: { ShowSetlistRecording.normalized($0.title) == ShowSetlistRecording.normalized(title) }) {
            selected.insert(existing)
        }
        draft = ""
        toggles += 1
    }

    private func load() {
        for artist in artists {
            catalog[artist.name] = ShowSetlistCatalog.songs(for: artist, in: modelContext)
        }
        let memories = (try? ShowSetlistRecording.memories(showID: show.id, in: modelContext)) ?? []
        let catalogSongs = catalog.values.flatMap { $0 }
        var current: Set<ShowSetlistRecording.Song> = []
        for memory in memories {
            if let id = memory.catalogSongID, let song = catalogSongs.first(where: { $0.catalogSongID == id }) {
                current.insert(song)
            } else {
                let song = ShowSetlistRecording.Song(catalogSongID: memory.catalogSongID, title: memory.manualTitle ?? "", artistName: memory.manualArtistName ?? "")
                guard !song.title.isEmpty else { continue }
                manual.append(song)
                current.insert(song)
            }
        }
        original = current
        selected = current
    }

    private func commit() {
        do {
            for song in original.symmetricDifference(selected) {
                try ShowSetlistRecording.toggle(song, showID: show.id, in: modelContext)
            }
            try modelContext.save()
            dismiss()
        } catch {
            modelContext.rollback()
            saveFailed = true
        }
    }
}

/// 只读本地已缓存的「听」目录，不发网络请求。
@MainActor
enum ShowSetlistCatalog {
    static func songs(for artist: ArtistSlot, in context: ModelContext) -> [ShowSetlistRecording.Song] {
        let snapshots = (try? context.fetch(FetchDescriptor<ArtistCatalogSnapshot>())) ?? []
        let snapshot = artist.appleMusicArtistID.flatMap { id in snapshots.first { $0.artistID == id } }
            ?? snapshots.first { ShowSetlistRecording.normalized($0.artistName) == ShowSetlistRecording.normalized(artist.name) }
        guard let snapshot else { return [] }
        let ids = snapshot.orderedSongIDs.isEmpty ? snapshot.topSongIDs : snapshot.orderedSongIDs
        guard !ids.isEmpty else { return [] }
        let found = (try? context.fetch(FetchDescriptor<CatalogSong>(predicate: #Predicate { ids.contains($0.appleMusicSongID) }))) ?? []
        let byID = Dictionary(found.map { ($0.appleMusicSongID, $0) }, uniquingKeysWith: { first, _ in first })
        var seenTitles = Set<String>()
        return ids.compactMap { byID[$0] }.compactMap { song in
            guard seenTitles.insert(ShowSetlistRecording.normalized(song.title)).inserted else { return nil }
            return ShowSetlistRecording.Song(catalogSongID: song.appleMusicSongID, title: song.title, artistName: artist.name)
        }
    }
}
