import SwiftData
import SwiftUI

/// 从「听」已缓存的专辑曲目里挑选歌曲加入歌单。
struct ShowSetlistCatalogPickerSheet: View {
    let artists: [ArtistSlot]
    let onAdd: ([ShowSetlistRecording.Song]) -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var artistIndex = 0
    @State private var catalog: [String: [ShowSetlistRecording.Song]] = [:]
    @State private var selected: Set<ShowSetlistRecording.Song> = []

    private var currentArtist: ArtistSlot? {
        artists.indices.contains(artistIndex) ? artists[artistIndex] : nil
    }

    private var currentSongs: [ShowSetlistRecording.Song] {
        guard let name = currentArtist?.name else { return [] }
        return catalog[name] ?? []
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if artists.count > 1 { artistTabs.padding(.vertical, 8) }
                list
            }
            .background(Color.black.ignoresSafeArea())
            .navigationTitle(BSLocalization.text("选择专辑曲目"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                BSChromeToolbarCloseButton(accessibilityLabel: "关闭") { dismiss() }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        onAdd(Array(selected))
                        dismiss()
                    } label: {
                        Text(BSLocalization.format("加入 (%lld)", selected.count))
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .disabled(selected.isEmpty)
                    .tint(BSColor.Stage.foreground)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .preferredColorScheme(.dark)
        .task { load() }
    }

    private var artistTabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(artists.enumerated()), id: \.offset) { index, artist in
                    let isOn = index == artistIndex
                    Button { artistIndex = index } label: {
                        Text(artist.name)
                            .font(.system(size: 13, weight: isOn ? .semibold : .regular))
                            .foregroundStyle(isOn ? BSColor.Stage.background : BSColor.Stage.foreground.opacity(0.7))
                            .padding(.horizontal, 14)
                            .frame(height: 32)
                            .background(isOn ? AnyShapeStyle(BSColor.Stage.foreground) : AnyShapeStyle(Color.white.opacity(0.08)), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(isOn ? BSColor.Stage.background : BSColor.Stage.foreground.opacity(0.7))
                }
            }
            .padding(.horizontal, 16)
        }
    }

    @ViewBuilder
    private var list: some View {
        if currentSongs.isEmpty {
            VStack(spacing: 10) {
                Spacer()
                Text(BSLocalization.text("未找到已缓存的曲目"))
                    .font(.system(size: 15))
                    .foregroundStyle(BSColor.Stage.muted)
                Text(BSLocalization.text("在「听」中浏览专辑后即可在此快速选择"))
                    .font(.system(size: 12))
                    .foregroundStyle(BSColor.Stage.dim)
                Spacer()
            }
        } else {
            List {
                Section {
                    Button {
                        if selected.isSuperset(of: currentSongs) {
                            selected.subtract(currentSongs)
                        } else {
                            selected.formUnion(currentSongs)
                        }
                    } label: {
                        HStack {
                            Text(selected.isSuperset(of: currentSongs) ? BSLocalization.text("取消全选") : BSLocalization.text("全选此艺人"))
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(BSColor.Stage.accent)
                            Spacer()
                        }
                    }
                    .buttonStyle(.plain)
                }

                Section {
                    ForEach(currentSongs, id: \.self) { song in
                        let isOn = selected.contains(song)
                        Button {
                            if isOn { selected.remove(song) } else { selected.insert(song) }
                        } label: {
                            HStack {
                                Text(song.title)
                                    .font(.system(size: 15))
                                    .foregroundStyle(BSColor.Stage.foreground)
                                Spacer()
                                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 18))
                                    .foregroundStyle(isOn ? BSColor.Stage.foreground : Color.white.opacity(0.25))
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
        }
    }

    private func load() {
        for artist in artists {
            catalog[artist.name] = ShowSetlistCatalog.songs(for: artist, in: modelContext)
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
