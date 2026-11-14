import PhotosUI
import SwiftData
import SwiftUI

/// 歌单 · 三个阶段（开场前 / 演出中 / 散场后）
/// 随现场生命周期切换展示形态与打勾、导入逻辑。
struct ShowSetlistSheet: View {
    let show: Show
    var forcedPhase: HomeShowPhase? = nil

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var items: [SetlistSongItem] = []
    @State private var draft = ""
    @State private var isDraftFocused = false
    @State private var isCatalogPickerPresented = false
    @State private var selectedScreenshot: PhotosPickerItem?
    @State private var isRecognizingScreenshot = false
    @State private var toggles = 0
    @State private var saveFailed = false
    @State private var playFeedback = false
    @State private var debugPhase: HomeShowPhase? = nil
    @State private var isExporting = false

    struct SetlistSongItem: Identifiable, Hashable {
        let id: UUID
        var catalogSongID: String?
        var title: String
        var artistName: String
        var wasPlayed: Bool
        var isExtra: Bool
        var order: Int
    }

    private var phase: HomeShowPhase {
        debugPhase ?? forcedPhase ?? HomeShowPhase(timeState: CurrentShowTimeState(timing: show.timingFields, calendar: show.timingCalendar(), now: Date()))
    }

    private var isBefore: Bool { phase == .pre }
    private var isLive: Bool { phase == .live }
    private var isAfter: Bool { phase == .ended || phase == .inactive }

    private var displayRows: [SetlistSongItem] {
        if isAfter {
            return items.filter(\.wasPlayed)
        }
        return items
    }

    private var playedCount: Int {
        items.filter(\.wasPlayed).count
    }

    private var titleText: String {
        isAfter ? BSLocalization.text("现场听到了") : BSLocalization.text("歌单")
    }

    private var subtitleText: String {
        if isBefore {
            return BSLocalization.format("%lld 首", items.count)
        } else if isLive {
            return BSLocalization.format("已唱 %1$lld / %2$lld", playedCount, items.count)
        } else {
            return BSLocalization.format("%lld 首", playedCount)
        }
    }

    private var inputHint: String {
        if isBefore {
            return BSLocalization.text("加一首")
        } else if isLive {
            return BSLocalization.text("唱了不在单上的")
        } else {
            return BSLocalization.text("补一首")
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if isBefore, !items.isEmpty {
                        playInListenButton
                    }
                    if !isLive, !displayRows.isEmpty {
                        exportButton
                    }
                    songList
                    if saveFailed {
                        Text(BSLocalization.text("没有保存，请重试"))
                            .font(.system(size: 13))
                            .foregroundStyle(BSColor.Stage.live)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 90)
            }
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom) {
                bottomBar
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
            }
            .background(Color.black.ignoresSafeArea())
            .navigationTitle(titleText)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 2) {
                        Text(titleText)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(BSColor.Stage.foreground)
                        Text(subtitleText)
                            .font(.system(size: 11))
                            .foregroundStyle(BSColor.Stage.muted)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) {
                        #if DEBUG
                        withAnimation {
                            switch phase {
                            case .pre: debugPhase = .live
                            case .live: debugPhase = .ended
                            case .ended, .inactive: debugPhase = .pre
                            }
                        }
                        #endif
                    }
                }
                BSChromeToolbarCloseButton(accessibilityLabel: "关闭") { dismiss() }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: commit) { Image(systemName: "checkmark") }
                        .tint(BSColor.Stage.foreground)
                        .foregroundStyle(BSColor.Stage.foreground)
                        .accessibilityLabel(BSLocalization.text("完成"))
                }
            }
        }
        .sensoryFeedback(.selection, trigger: toggles)
        .sensoryFeedback(.success, trigger: playFeedback)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(.regularMaterial)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $isCatalogPickerPresented) {
            ShowSetlistCatalogPickerSheet(artists: show.artists) { songs in
                appendSongs(songs)
            }
        }
        .playlistExport(isPresented: $isExporting) {
            displayRows.map { PlaylistExport.Song(title: $0.title, artistName: $0.artistName) }
        }
        .onChange(of: selectedScreenshot) { _, item in
            guard let item else { return }
            selectedScreenshot = nil
            Task { await processScreenshot(item) }
        }
        .task { load() }
    }

    // MARK: - Play in Listen Button (开场前)

    private var playInListenButton: some View {
        Button(action: playInListen) {
            Label(BSLocalization.text("在「听」里播放"), systemImage: "play.fill")
                .lineLimit(1)
        }
        .buttonStyle(BSPrimaryButtonStyle())
    }

    private var exportButton: some View {
        Button { isExporting = true } label: {
            Label(BSLocalization.text("导出到音乐 App"), systemImage: "square.and.arrow.up")
                .lineLimit(1)
        }
        .buttonStyle(BSSecondaryButtonStyle())
    }

    // MARK: - Song List

    @ViewBuilder
    private var songList: some View {
        let rows = displayRows
        if rows.isEmpty {
            VStack(spacing: 8) {
                Text(BSLocalization.text("还没有曲目"))
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(BSColor.Stage.muted)
                Text(BSLocalization.text("支持截图识别、从专辑选择或直接手输"))
                    .font(.system(size: 12))
                    .foregroundStyle(BSColor.Stage.dim)
            }
            .frame(maxWidth: .infinity, minHeight: 120)
        } else {
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    if index > 0 {
                        Divider().overlay(Color.white.opacity(0.10)).padding(.leading, 16)
                    }
                    songRow(row, index: index + 1)
                }
            }
            .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Color.white.opacity(0.16), lineWidth: 0.5))
        }
    }

    private func songRow(_ row: SetlistSongItem, index: Int) -> some View {
        Button {
            toggleRow(row)
        } label: {
            HStack(spacing: 12) {
                Text("\(index)")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(BSColor.Stage.muted)
                    .frame(width: 24, alignment: .leading)

                Text(row.title)
                    .font(.system(size: 15, weight: row.wasPlayed && isLive ? .semibold : .regular))
                    .foregroundStyle(rowTextColor(row))
                    .lineLimit(1)

                Spacer(minLength: 8)

                if !isBefore {
                    ZStack {
                        if row.wasPlayed {
                            Circle().fill(Color.white)
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .heavy))
                                .foregroundStyle(Color(red: 11/255, green: 13/255, blue: 18/255))
                        } else {
                            Circle().strokeBorder(Color.white.opacity(0.25), lineWidth: 1.5)
                        }
                    }
                    .frame(width: 24, height: 24)
                }
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 50)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func rowTextColor(_ row: SetlistSongItem) -> Color {
        if row.isExtra {
            return Color(red: 232/255, green: 199/255, blue: 142/255)
        }
        if isBefore {
            return BSColor.Stage.foreground
        }
        if row.wasPlayed {
            return BSColor.Stage.foreground
        }
        return BSColor.Stage.foreground.opacity(0.35)
    }

    private func toggleRow(_ row: SetlistSongItem) {
        guard isLive else { return }
        guard let idx = items.firstIndex(where: { $0.id == row.id }) else { return }
        items[idx].wasPlayed.toggle()
        toggles += 1
    }

    // MARK: - Bottom Glass Bar

    private var bottomBar: some View {
        HStack(spacing: 8) {
            PhotosPicker(selection: $selectedScreenshot, matching: .images) {
                Image(systemName: "text.viewfinder")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(BSColor.Stage.foreground)
                    .frame(width: 44, height: 44)
                    .background(Color.white.opacity(0.10), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(BSLocalization.text("从截图导入"))

            Button {
                isCatalogPickerPresented = true
            } label: {
                Image(systemName: "opticaldisc")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(BSColor.Stage.foreground)
                    .frame(width: 44, height: 44)
                    .background(Color.white.opacity(0.10), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(BSLocalization.text("从「听」已拉取的专辑曲目里选"))

            HStack {
                TextField(inputHint, text: $draft)
                    .font(.system(size: 15))
                    .foregroundStyle(BSColor.Stage.foreground)
                    .submitLabel(.done)
                    .onSubmit(addDraft)
            }
            .padding(.horizontal, 14)
            .frame(height: 44)
            .background(Color.white.opacity(0.08), in: Capsule())
        }
        .padding(8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(Color.white.opacity(0.18), lineWidth: 0.5))
    }

    private func addDraft() {
        let title = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        let artist = show.artistNames.first ?? ""
        let isExtra = isLive
        let wasPlayed = !isBefore
        let newItem = SetlistSongItem(
            id: UUID(),
            catalogSongID: nil,
            title: title,
            artistName: artist,
            wasPlayed: wasPlayed,
            isExtra: isExtra,
            order: items.count + 1
        )
        items.append(newItem)
        draft = ""
        toggles += 1
    }

    private func appendSongs(_ songs: [ShowSetlistRecording.Song]) {
        for song in songs {
            if !items.contains(where: { ShowSetlistRecording.normalized($0.title) == ShowSetlistRecording.normalized(song.title) }) {
                items.append(SetlistSongItem(
                    id: UUID(),
                    catalogSongID: song.catalogSongID,
                    title: song.title,
                    artistName: song.artistName,
                    wasPlayed: !isBefore,
                    isExtra: false,
                    order: items.count + 1
                ))
            }
        }
        toggles += 1
    }

    private func processScreenshot(_ pickerItem: PhotosPickerItem) async {
        isRecognizingScreenshot = true
        defer { isRecognizingScreenshot = false }
        guard let data = try? await pickerItem.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else { return }
        if let result = await SetlistOCRRecognizer.recognize(from: image, showArtist: show.artistNames.first) {
            let artist = result.artistName ?? show.artistNames.first ?? ""
            for title in result.songTitles {
                if !items.contains(where: { ShowSetlistRecording.normalized($0.title) == ShowSetlistRecording.normalized(title) }) {
                    items.append(SetlistSongItem(
                        id: UUID(),
                        catalogSongID: nil,
                        title: title,
                        artistName: artist,
                        wasPlayed: !isBefore,
                        isExtra: false,
                        order: items.count + 1
                    ))
                }
            }
            toggles += 1
        }
    }

    // MARK: - Play in Listen Action

    private func playInListen() {
        let songs = items.map { ShowSetlistRecording.Song(catalogSongID: $0.catalogSongID, title: $0.title, artistName: $0.artistName) }
        let disc = ShowSetlistPlayback.disc(
            songs,
            show: show,
            kind: .preview,
            title: BSLocalization.text("预习歌单"),
            catalog: ShowSetlistPlayback.catalog(for: songs, in: modelContext)
        )
        Task { @MainActor in
            if await ShowSetlistPlayback.play(disc) { playFeedback.toggle() }
        }
    }

    // MARK: - Persistence

    private func load() {
        let memories = (try? ShowSetlistRecording.memories(showID: show.id, in: modelContext)) ?? []
        items = memories.enumerated().map { index, mem in
            let isPlayedDefault = mem.wasPlayed ?? true
            return SetlistSongItem(
                id: mem.id,
                catalogSongID: mem.catalogSongID,
                title: mem.manualTitle ?? "",
                artistName: mem.manualArtistName ?? "",
                wasPlayed: mem.wasPlayed ?? (isBefore ? false : isPlayedDefault),
                isExtra: mem.isMostSurprising,
                order: mem.order ?? (index + 1)
            )
        }
        .filter { !$0.title.isEmpty }
        .sorted { $0.order < $1.order }
    }

    private func commit() {
        do {
            let existing = (try? ShowSetlistRecording.memories(showID: show.id, in: modelContext)) ?? []
            for mem in existing {
                modelContext.delete(mem)
            }
            for (index, item) in items.enumerated() {
                let memory = ShowSetlistMemory(
                    id: item.id,
                    showID: show.id,
                    catalogSongID: item.catalogSongID,
                    manualTitle: item.title,
                    manualArtistName: item.artistName,
                    isMostSurprising: item.isExtra,
                    wasPlayed: item.wasPlayed,
                    order: index + 1
                )
                modelContext.insert(memory)
            }
            try modelContext.save()
            dismiss()
        } catch {
            modelContext.rollback()
            saveFailed = true
        }
    }
}
