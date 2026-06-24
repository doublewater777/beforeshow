import AVFoundation
import Photos
import PhotosUI
import SwiftData
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import WebKit

struct CurrentAllToolsRow: View {
    let summary: String

    var body: some View {
        HStack(spacing: BSSpacing.md) {
            Text("全部工具")
                .font(BSFont.headline)
                .foregroundColor(BSColor.textSecondary)

            Spacer(minLength: BSSpacing.sm)

            Text(summary)
                .font(BSFont.caption)
                .foregroundColor(BSColor.textTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(BSColor.textTertiary)
        }
        .padding(BSSpacing.md)
        .background(Color.white.opacity(0.045))
        .clipShape(RoundedRectangle(cornerRadius: BSRadius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: BSRadius.lg)
                .stroke(BSColor.border, lineWidth: 1)
        )
    }
}

struct CurrentShowAllToolsView: View {
    let show: Show

    private let columns = [
        GridItem(.flexible(), spacing: BSSpacing.md),
        GridItem(.flexible(), spacing: BSSpacing.md)
    ]

    var body: some View {
        ZStack {
            CurrentShowStageBackground()
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: BSSpacing.lg) {
                    VStack(alignment: .leading, spacing: BSSpacing.sm) {
                        Text("全部工具")
                            .font(.system(size: 32, weight: .bold))
                            .foregroundColor(BSColor.textPrimary)
                        Text("围绕这场现场，你可以做的准备和记录。")
                            .font(BSFont.body)
                            .foregroundColor(BSColor.textTertiary)
                    }

                    LazyVGrid(columns: columns, spacing: BSSpacing.md) {
                        TonightFirstListenEntryView(show: show, presentation: .tile)

                        NavigationLink {
                            RoundTripPlanView(show: show)
                        } label: {
                            CurrentToolTile(
                                iconName: "tram.fill",
                                title: "往返计划",
                                subtitle: "去程和返程安排",
                                accent: BSColor.Accent.travel
                            )
                        }

                        NavigationLink {
                            CandidateSongsView(show: show)
                        } label: {
                            CurrentToolTile(
                                iconName: "mic.fill",
                                title: "候选曲目",
                                subtitle: "编辑推测歌单",
                                accent: BSColor.Accent.candidate
                            )
                        }

                        NavigationLink {
                            ShowPreparationView(show: show)
                        } label: {
                            CurrentToolTile(
                                iconName: "sparkles",
                                title: "现场准备",
                                subtitle: "准备事项和提醒",
                                accent: BSColor.Accent.prepare
                            )
                        }

                        NavigationLink {
                            ShowVideosView(show: show)
                        } label: {
                            CurrentToolTile(
                                iconName: "play.rectangle.fill",
                                title: "现场视频",
                                subtitle: "开场前先看现场",
                                accent: BSColor.Accent.video
                            )
                        }

                        NavigationLink {
                            ShowFragmentListView(show: show)
                        } label: {
                            CurrentToolTile(
                                iconName: "sparkles.rectangle.stack",
                                title: "现场碎片",
                                subtitle: "照片、视频和语音",
                                accent: BSColor.Accent.fragment
                            )
                        }
                    }
                    .buttonStyle(.plain)

                    Text("这些工具都围绕当前现场展开")
                        .font(BSFont.caption)
                        .foregroundColor(BSColor.textTertiary.opacity(0.74))
                        .frame(maxWidth: .infinity)
                        .padding(.top, BSSpacing.lg)
                }
                .padding(BSSpacing.md)
                .padding(.bottom, BSSpacing.xl)
            }
            .scrollIndicators(.hidden)
        }
        .toolbarBackground(.hidden, for: .navigationBar)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct CurrentToolTile: View {
    let iconName: String
    let title: String
    let subtitle: String
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: BSSpacing.sm) {
            Image(systemName: iconName)
                .font(.system(size: 19, weight: .semibold))
                .foregroundColor(accent)
                .frame(width: 40, height: 40)
                .background(accent.opacity(0.13))
                .clipShape(RoundedRectangle(cornerRadius: BSRadius.md))

            Text(title)
                .font(BSFont.headline)
                .foregroundColor(BSColor.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.82)

            Text(subtitle)
                .font(BSFont.caption)
                .foregroundColor(BSColor.textTertiary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 138, alignment: .topLeading)
        .padding(BSSpacing.md)
        .background(Color.white.opacity(0.045))
        .clipShape(RoundedRectangle(cornerRadius: BSRadius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: BSRadius.lg)
                .stroke(BSColor.border, lineWidth: 1)
        )
    }
}

struct ShowVideosView: View {
    enum DebugState {
        case normal([ShowVideo])
        case empty
        case generating
        case webview([ShowVideo])
    }

    let show: Show
    var debugState: DebugState?

    @Query private var videos: [ShowVideo]
    @State private var navigator = ShowVideoWebViewNavigator()

    private let libraryService = ShowVideoLibraryService()

    private var visibleVideos: [ShowVideo] {
        switch debugState {
        case .normal(let videos), .webview(let videos):
            return videos
        case .empty, .generating:
            return []
        case nil:
            return videos
        }
    }

    private var sections: [ShowVideoSection] {
        libraryService.sections(for: show.id, videos: visibleVideos)
    }

    private var hasVideos: Bool {
        sections.contains { !$0.videos.isEmpty }
    }

    private var isGenerating: Bool {
        if case .generating = debugState {
            return true
        }
        return false
    }

    var body: some View {
        BSStageScaffold(title: "现场视频", subtitle: "开场前，先看几场真正的现场。", bottomPadding: 96) {
            Text(currentShowTitle)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(BSColor.textSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(Color.white.opacity(0.06))
                        .overlay(
                            Capsule()
                                .stroke(Color.white.opacity(0.12), lineWidth: 1)
                        )
                )

            if isGenerating {
                BSLoadingStatePanel(
                    title: "正在整理现场视频",
                    message: "会整理可打开的 B站现场视频条目。"
                )
            }

            if hasVideos {
                ForEach(sections, id: \.category) { section in
                    if !section.videos.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(section.category.title)
                                .font(.system(size: 20, weight: .bold))
                                .foregroundColor(BSColor.textPrimary)
                            VStack(spacing: 12) {
                                ForEach(section.videos) { video in
                                    ShowVideoCardView(video: video) {
                                        navigator.open(video)
                                    }
                                }
                            }
                        }
                    }
                }
            } else if !isGenerating {
                BSEmptyPanel(
                    iconName: "play.rectangle",
                    title: "现场视频无内容",
                    message: "还没有整理出可看的 B站现场视频。",
                    buttonTitle: "整理现场视频",
                    buttonIconName: "sparkles"
                ) {}
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: Binding(
            get: { navigator.presentedVideo },
            set: { video in
                if video == nil {
                    navigator.close()
                }
            }
        )) { video in
            ShowVideoWebViewSheet(video: video) {
                navigator.close()
            }
        }
        .onAppear {
            if case .webview(let videos) = debugState,
               let first = videos.first {
                navigator.open(first)
            }
        }
    }

    private var currentShowTitle: String {
        let artist = show.artist?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !artist.isEmpty {
            return "\(artist) · \(show.name)"
        }
        return show.name
    }
}

private struct ShowVideoCardView: View {
    let video: ShowVideo
    let onOpen: () -> Void

    private var presentation: ShowVideoCardPresentation {
        ShowVideoCardPresentation(video: video)
    }

    var body: some View {
        Button(action: onOpen) {
            HStack(alignment: .top, spacing: 12) {
                ShowVideoThumbnailView(video: video)

                VStack(alignment: .leading, spacing: 6) {
                    Text(presentation.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(BSColor.textPrimary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    Text(presentation.sourceText)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Color.white.opacity(0.70))
                        .lineLimit(1)

                    Text(presentation.reason)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(Color.white.opacity(0.84))
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.078),
                        Color.white.opacity(0.045)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.white.opacity(0.13), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct ShowVideoThumbnailView: View {
    let video: ShowVideo

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if let urlString = video.thumbnailURL,
               let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    default:
                        ShowVideoPlaceholderCover()
                    }
                }
            } else {
                ShowVideoPlaceholderCover()
            }

            Text(video.durationText)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(Color.white.opacity(0.72))
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color.black.opacity(0.58))
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .padding(6)
        }
        .frame(width: 108, height: 78)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.09), lineWidth: 1)
        )
    }
}

private struct ShowVideoPlaceholderCover: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.49, green: 0.81, blue: 1.0).opacity(0.34),
                    Color(red: 0.70, green: 0.53, blue: 1.0).opacity(0.24),
                    Color(red: 1.0, green: 0.70, blue: 0.28).opacity(0.22)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [
                    Color.white.opacity(0.44),
                    .clear
                ],
                center: .center,
                startRadius: 0,
                endRadius: 18
            )

            HStack(spacing: 18) {
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.38), .clear],
                            startPoint: .bottom,
                            endPoint: .top
                        )
                    )
                    .frame(width: 28, height: 92)
                    .blur(radius: 7)
                    .rotationEffect(.degrees(-22), anchor: .bottom)
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.38), .clear],
                            startPoint: .bottom,
                            endPoint: .top
                        )
                    )
                    .frame(width: 28, height: 92)
                    .blur(radius: 7)
                    .rotationEffect(.degrees(18), anchor: .bottom)
            }
            .offset(y: 18)
        }
    }
}

private struct ShowVideoWebViewSheet: View {
    let video: ShowVideo
    let onClose: () -> Void

    var body: some View {
        NavigationStack {
            ShowVideoWebView(url: video.bilibiliURL)
                .ignoresSafeArea(edges: .bottom)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("关闭", action: onClose)
                            .foregroundColor(BSColor.textPrimary)
                    }
                    ToolbarItem(placement: .principal) {
                        VStack(spacing: 2) {
                            Text(video.title)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(BSColor.textPrimary)
                                .lineLimit(1)
                            Text("bilibili.com")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(BSColor.textTertiary)
                        }
                    }
                }
                .toolbarBackground(Color.black, for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
    }
}

private struct ShowVideoWebView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        WKWebView()
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        if webView.url != url {
            webView.load(URLRequest(url: url))
        }
    }
}

struct TonightFirstListenEntryView: View {
    enum Presentation {
        case row
        case tile
    }

    let show: Show
    var presentation: Presentation = .row

    @Environment(\.modelContext) private var modelContext
    @Query private var candidateGroups: [CandidateSongGroup]
    @Query private var candidateSongs: [CandidateSong]
    @Query private var artistInterests: [ArtistInterestItem]
    @AppStorage(ProEntitlementStorage.appStorageKey) private var entitlementRawValue = ""
    @AppStorage(ProUsageStorage.usedFreeGenerationFeaturesKey) private var usedFreeGenerationFeaturesRawValue = ""

    @State private var isGenerating = false
    @State private var message: String?
    @State private var showsProMembership = false

    private let editingService = CandidateSongEditingService()
    private let gate = ProFeatureGate()

    private var showGroups: [CandidateSongGroup] {
        candidateGroups.filter { $0.showID == show.id }
    }

    private var showArtistInterests: [ArtistInterestItem] {
        artistInterests.filter { $0.showID == show.id }
    }

    private var pickedSong: CandidateSong? {
        TonightFirstListenService().pickSong(
            groups: showGroups,
            songs: candidateSongs,
            artistInterests: showArtistInterests
        )
    }

    private var entitlement: ProEntitlementState {
        ProEntitlementStorage.decode(entitlementRawValue)
    }

    private var canGenerate: Bool {
        gate.canGenerate(
            feature: .candidateSongs,
            hasUsedFreeAllowance: ProUsageStorage
                .decodeUsedFreeGenerationFeatures(usedFreeGenerationFeaturesRawValue)
                .contains(.candidateSongs),
            entitlement: entitlement
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                if canGenerate {
                    Task {
                        await generateCandidateSongs()
                    }
                } else {
                    presentProLimit(message: "免费体验已用完，开通 Pro 后可以重复生成候选曲目。")
                }
            } label: {
                entryLabel
            }
            .buttonStyle(.plain)
            .disabled(isGenerating)

            if let message {
                VStack(alignment: .leading, spacing: 8) {
                    Text(message)
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.58))

                    if !canGenerate {
                        Button("开通 Pro") {
                            showsProMembership = true
                        }
                        .font(.system(size: 13, weight: .semibold))
                    }
                }
                .padding(.horizontal, 4)
            }
        }
        .sheet(isPresented: $showsProMembership) {
            ProMembershipSheetView()
        }
    }

    @ViewBuilder
    private var entryLabel: some View {
        switch presentation {
        case .row:
            CurrentFeatureRow(
                iconName: isGenerating ? "hourglass" : "music.note",
                title: "今晚先听",
                subtitle: subtitle,
                accent: BSColor.Accent.music
            )
        case .tile:
            CurrentToolTile(
                iconName: isGenerating ? "hourglass" : "music.note",
                title: "今晚先听",
                subtitle: subtitle,
                accent: BSColor.Accent.music
            )
        }
    }

    private var subtitle: String {
        if isGenerating {
            return "正在生成候选曲目"
        }

        if let pickedSong {
            return "\(pickedSong.songName) - \(pickedSong.artist)"
        }

        return TonightFirstListenService.emptyPrompt
    }

    @MainActor
    private func generateCandidateSongs() async {
        guard canGenerate else {
            presentProLimit(message: "免费体验已用完，开通 Pro 后可以重复生成候选曲目。")
            return
        }

        isGenerating = true
        defer { isGenerating = false }

        do {
            let service = Self.defaultGenerationService()
            let inputs = try await service.generate(for: show, artistInterests: showArtistInterests)
            replaceCandidateSongs(with: inputs)
            usedFreeGenerationFeaturesRawValue = ProUsageStorage.markUsed(
                .candidateSongs,
                in: usedFreeGenerationFeaturesRawValue
            )
            message = "候选曲目已更新。"
        } catch {
            message = "暂时没生成成功，请稍后再试。"
        }
    }

    @MainActor
    private func replaceCandidateSongs(with inputs: [CandidateSongInput]) {
        let showGroupIDs = Set(showGroups.map(\.id))
        for song in candidateSongs where showGroupIDs.contains(song.groupID) {
            modelContext.delete(song)
        }
        for group in showGroups {
            modelContext.delete(group)
        }

        do {
            let group = try CandidateSongGroup(
                showID: show.id,
                uncertaintyNote: "候选曲目来自公开信息推测，不代表官方歌单。"
            )
            modelContext.insert(group)

            for song in try editingService.makeSongs(groupID: group.id, inputs: inputs) {
                modelContext.insert(song)
            }

            try modelContext.save()
        } catch {
            message = "候选曲目保存失败。"
        }
    }

    private static func defaultGenerationService() -> RemoteCandidateSongGenerationService {
        let baseURL = URL(string: "https://beforeshow-d2g0gv0zz4cc249dc-1312569550.ap-shanghai.app.tcloudbase.com/generate")!
        return RemoteCandidateSongGenerationService(
            baseURL: baseURL,
            appInstanceId: UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString,
            appSignature: "beforeshow-app-signature-v1"
        )
    }

    private func presentProLimit(message: String) {
        self.message = message
        showsProMembership = true
    }
}

struct CandidateSongsView: View {
    let show: Show

    @Environment(\.modelContext) private var modelContext
    @Query private var candidateGroups: [CandidateSongGroup]
    @Query private var candidateSongs: [CandidateSong]
    @Query private var artistInterests: [ArtistInterestItem]
    @AppStorage(ProEntitlementStorage.appStorageKey) private var entitlementRawValue = ""
    @AppStorage(ProUsageStorage.usedFreeGenerationFeaturesKey) private var usedFreeGenerationFeaturesRawValue = ""

    @State private var newSongName = ""
    @State private var isGenerating = false
    @State private var message: String?
    @State private var showsReplacementConfirmation = false
    @State private var showsProLimit = false
    @State private var showsProMembership = false
    @State private var toast: BSToastPayload?

    private let editingService = CandidateSongEditingService()
    private let gate = ProFeatureGate()

    private var showGroups: [CandidateSongGroup] {
        candidateGroups.filter { $0.showID == show.id }
    }

    private var sortedShowGroups: [CandidateSongGroup] {
        showGroups.sorted { $0.createdAt < $1.createdAt }
    }

    private var showArtistInterests: [ArtistInterestItem] {
        artistInterests.filter { $0.showID == show.id }
    }

    private var visibleSongs: [CandidateSong] {
        let groupIDs = Set(showGroups.map(\.id))
        let groupOrder = Dictionary(uniqueKeysWithValues: sortedShowGroups.enumerated().map { ($1.id, $0) })
        return candidateSongs
            .filter { groupIDs.contains($0.groupID) }
            .sorted { first, second in
                let firstGroupOrder = groupOrder[first.groupID] ?? Int.max
                let secondGroupOrder = groupOrder[second.groupID] ?? Int.max
                if firstGroupOrder == secondGroupOrder {
                    return first.order < second.order
                }
                return firstGroupOrder < secondGroupOrder
            }
    }

    private var uncertaintyNote: String {
        sortedShowGroups.first?.uncertaintyNote ?? "这是根据公开信息和过往演出推测的候选曲目。你可以保留、移除、补充或调整顺序，不保证现场一定演出。"
    }

    var body: some View {
        BSStageScaffold(title: "候选曲目", subtitle: show.name, bottomPadding: 96) {
            BSGlassPanel {
                Text(uncertaintyNote)
                    .font(BSFont.body)
                    .foregroundColor(BSColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if isGenerating {
                BSLoadingStatePanel(
                    title: "正在生成候选曲目",
                    message: "会先保存一版可编辑的推测歌单，你仍然可以删改顺序和歌曲。"
                )
            }

            VStack(alignment: .leading, spacing: BSSpacing.sm) {
                BSSectionHeader(title: "推测歌单")
                if visibleSongs.isEmpty {
                    emptySongState
                } else {
                    ForEach(Array(visibleSongs.enumerated()), id: \.element.id) { index, song in
                        CandidateSongRowView(index: index + 1, song: song) {
                            remove(song)
                        }
                    }
                }
            }

            HStack(spacing: BSSpacing.sm) {
                TextField("添加歌曲...", text: $newSongName)
                    .bsInputField()

                Button("添加") {
                    addSong()
                }
                .font(BSFont.caption)
                .foregroundColor(.black)
                .padding(.horizontal, 18)
                .padding(.vertical, 13)
                .background(Color.white.opacity(canAddSong ? 1 : 0.46))
                .clipShape(RoundedRectangle(cornerRadius: BSRadius.md))
                .disabled(!canAddSong)
            }

            Button {
                requestGeneration()
            } label: {
                HStack {
                    if isGenerating {
                        ProgressView()
                            .tint(.black)
                    }
                    Text(visibleSongs.isEmpty ? "生成候选曲目" : "重新生成候选曲目")
                }
            }
            .buttonStyle(BSSecondaryButtonStyle())
            .disabled(isGenerating)

            Text("列表顺序表达推测的现场演出顺序。重新生成会覆盖当前列表。")
                .font(BSFont.caption)
                .foregroundColor(BSColor.textTertiary)
                .fixedSize(horizontal: false, vertical: true)

            if let message {
                Text(message)
                    .font(BSFont.caption)
                    .foregroundColor(BSColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .alert("重新生成候选曲目？", isPresented: $showsReplacementConfirmation) {
            Button("取消", role: .cancel) {}
            Button("覆盖", role: .destructive) {
                Task {
                    await generateCandidateSongs()
                }
            }
        } message: {
            Text("重新生成会用新的推测列表替换当前候选曲目。")
        }
        .sheet(isPresented: $showsProMembership) {
            ProMembershipSheetView()
        }
        .sheet(isPresented: $showsProLimit) {
            BSProLimitSheet(
                title: ProLimitReason.candidateSongsRegeneration.title,
                message: ProLimitReason.candidateSongsRegeneration.message,
                onPrimary: {
                    showsProLimit = false
                    showsProMembership = true
                },
                onSecondary: {
                    showsProLimit = false
                }
            )
        }
        .bsToastOverlay(toast)
    }

    private var emptySongState: some View {
        BSEmptyPanel(
            iconName: "music.mic",
            title: "候选曲目无歌曲",
            message: "还没有候选曲目。可以先生成一版，再按你的直觉删改。"
        )
    }

    private var canAddSong: Bool {
        !newSongName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var fallbackArtistName: String {
        let artist = show.artist?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return artist.isEmpty ? show.name : artist
    }

    private var entitlement: ProEntitlementState {
        ProEntitlementStorage.decode(entitlementRawValue)
    }

    private var canGenerate: Bool {
        gate.canGenerate(
            feature: .candidateSongs,
            hasUsedFreeAllowance: ProUsageStorage
                .decodeUsedFreeGenerationFeatures(usedFreeGenerationFeaturesRawValue)
                .contains(.candidateSongs),
            entitlement: entitlement
        )
    }

    private func addSong() {
        do {
            let group = try mutableSongGroup()
            let existingSongs = candidateSongs.filter { $0.groupID == group.id }
            let song = try editingService.addSong(
                to: existingSongs,
                groupID: group.id,
                songName: newSongName,
                artist: fallbackArtistName
            )
            modelContext.insert(song)
            try modelContext.save()
            newSongName = ""
            message = "已添加到候选曲目。"
            presentToast(.success, message: "已添加到候选曲目")
        } catch {
            message = "这首歌暂时没有添加成功。"
            presentToast(.failure, message: "添加失败")
        }
    }

    private func remove(_ song: CandidateSong) {
        let siblings = candidateSongs.filter { $0.groupID == song.groupID }
        _ = editingService.remove(songID: song.id, from: siblings)
        modelContext.delete(song)
        do {
            try modelContext.save()
            message = "已移除这首候选曲目。"
            presentToast(.neutral, message: "已移除")
        } catch {
            message = "移除失败，请稍后再试。"
            presentToast(.failure, message: "移除失败")
        }
    }

    private func requestGeneration() {
        guard canGenerate else {
            message = "免费体验已用完，开通 Pro 后可以重复生成候选曲目。"
            showsProLimit = true
            return
        }

        if visibleSongs.isEmpty {
            Task {
                await generateCandidateSongs()
            }
        } else {
            showsReplacementConfirmation = true
        }
    }

    @MainActor
    private func generateCandidateSongs() async {
        guard canGenerate else {
            message = "免费体验已用完，开通 Pro 后可以重复生成候选曲目。"
            showsProLimit = true
            return
        }

        isGenerating = true
        defer { isGenerating = false }

        do {
            let inputs = try await Self.defaultGenerationService().generate(for: show, artistInterests: showArtistInterests)
            replaceCandidateSongs(with: inputs)
            usedFreeGenerationFeaturesRawValue = ProUsageStorage.markUsed(.candidateSongs, in: usedFreeGenerationFeaturesRawValue)
            message = "候选曲目已更新。"
            presentToast(.success, message: "候选曲目已更新")
        } catch {
            message = "暂时没生成成功，请稍后再试。"
            presentToast(.failure, message: "生成失败")
        }
    }

    @MainActor
    private func replaceCandidateSongs(with inputs: [CandidateSongInput]) {
        let showGroupIDs = Set(showGroups.map(\.id))
        for song in candidateSongs where showGroupIDs.contains(song.groupID) {
            modelContext.delete(song)
        }
        for group in showGroups {
            modelContext.delete(group)
        }

        do {
            let group = try CandidateSongGroup(
                showID: show.id,
                uncertaintyNote: "候选曲目来自公开信息推测，不代表官方歌单。"
            )
            modelContext.insert(group)

            for song in try editingService.makeSongs(groupID: group.id, inputs: inputs) {
                modelContext.insert(song)
            }

            try modelContext.save()
        } catch {
            message = "候选曲目保存失败。"
            presentToast(.failure, message: "保存失败")
        }
    }

    private func mutableSongGroup() throws -> CandidateSongGroup {
        if let group = sortedShowGroups.first {
            return group
        }

        let group = try CandidateSongGroup(
            showID: show.id,
            uncertaintyNote: "候选曲目来自公开信息推测，不代表官方歌单。"
        )
        modelContext.insert(group)
        return group
    }

    private static func defaultGenerationService() -> RemoteCandidateSongGenerationService {
        let baseURL = URL(string: "https://beforeshow-d2g0gv0zz4cc249dc-1312569550.ap-shanghai.app.tcloudbase.com/generate")!
        return RemoteCandidateSongGenerationService(
            baseURL: baseURL,
            appInstanceId: UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString,
            appSignature: "beforeshow-app-signature-v1"
        )
    }

    private func presentToast(_ tone: BSToastTone, message: String) {
        let payload = BSToastPayload(tone: tone, message: message)
        toast = payload
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            if toast == payload {
                toast = nil
            }
        }
    }
}

private struct CandidateSongRowView: View {
    let index: Int
    let song: CandidateSong
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: BSSpacing.sm) {
            Text("\(index)")
                .font(BSFont.tag)
                .foregroundColor(BSColor.textTertiary)
                .frame(width: 28, height: 28)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: BSRadius.sm))
                .overlay(
                    RoundedRectangle(cornerRadius: BSRadius.sm)
                        .stroke(BSColor.border, lineWidth: 1)
                )

            VStack(alignment: .leading, spacing: BSSpacing.xs) {
                Text(song.songName)
                    .font(BSFont.body.weight(.semibold))
                    .foregroundColor(BSColor.textPrimary)
                    .lineLimit(1)
                Text(song.artist)
                    .font(BSFont.caption)
                    .foregroundColor(BSColor.textTertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: BSSpacing.sm)

            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(BSColor.textTertiary)
                    .frame(width: 30, height: 30)
                    .background(Color.white.opacity(0.05))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(Color.white.opacity(0.035))
        .clipShape(RoundedRectangle(cornerRadius: BSRadius.md))
        .overlay(
            RoundedRectangle(cornerRadius: BSRadius.md)
                .stroke(BSColor.border, lineWidth: 1)
        )
    }
}

struct CurrentFeatureRow: View {
    let iconName: String
    let title: String
    let subtitle: String
    let accent: Color

    init(
        iconName: String,
        title: String,
        subtitle: String,
        accent: Color = BSColor.textPrimary
    ) {
        self.iconName = iconName
        self.title = title
        self.subtitle = subtitle
        self.accent = accent
    }

    var body: some View {
        HStack(spacing: BSSpacing.md) {
            Image(systemName: iconName)
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(accent)
                .frame(width: 40, height: 40)
                .background(accent.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: BSRadius.md))

            VStack(alignment: .leading, spacing: BSSpacing.xs) {
                Text(title)
                    .font(BSFont.headline)
                    .foregroundColor(BSColor.textPrimary)
                Text(subtitle)
                    .font(BSFont.caption)
                    .foregroundColor(BSColor.textTertiary)
                    .lineLimit(2)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(BSColor.textTertiary)
        }
        .padding(BSSpacing.md)
        .background(Color.white.opacity(0.055))
        .clipShape(RoundedRectangle(cornerRadius: BSRadius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: BSRadius.lg)
                .stroke(BSColor.borderProminent, lineWidth: 1)
        )
    }
}

struct RoundTripPlanView: View {
    let show: Show

    @Environment(\.modelContext) private var modelContext
    @Query private var plans: [RoundTripPlan]
    @AppStorage(ProEntitlementStorage.appStorageKey) private var entitlementRawValue = ""
    @AppStorage(ProUsageStorage.usedFreeGenerationFeaturesKey) private var usedFreeGenerationFeaturesRawValue = ""
    @State private var outboundText = ""
    @State private var returnText = ""
    @State private var returnNote = ""
    @State private var returnIsUndecided = true
    @State private var origin = ""
    @State private var destination = ""
    @State private var hotel = ""
    @State private var meetingPoint = ""
    @State private var notes = ""
    @State private var selectedDirection: RoundTripDirection = .outbound
    @State private var isGeneratingDirection: RoundTripDirection?
    @State private var message: String?
    @State private var showsProLimit = false
    @State private var showsProMembership = false
    @State private var toast: BSToastPayload?
    @State private var didLoadPlan = false

    private let gate = ProFeatureGate()

    private var plan: RoundTripPlan? {
        plans.first { $0.showID == show.id }
    }

    var body: some View {
        BSStageScaffold(title: "往返计划", subtitle: show.name) {
            Picker("方向", selection: $selectedDirection) {
                ForEach(RoundTripDirection.allCases, id: \.self) { direction in
                    Text(direction.displayName).tag(direction)
                }
            }
            .pickerStyle(.segmented)
            .tint(.white)

            if let isGeneratingDirection {
                BSLoadingStatePanel(
                    title: "正在生成\(isGeneratingDirection.displayName)计划",
                    message: "会根据你填写的方向信息生成一版可编辑草稿，不替代地图导航。"
                )
            }

            if selectedDirection == .outbound {
                outboundPanel
            } else {
                returnPanel
            }

            Text("生成草稿只会使用你填写的方向信息和现场基础信息；结果是可编辑草稿，不替代地图导航。")
                .font(BSFont.caption)
                .foregroundColor(BSColor.textTertiary)

            if let message {
                Text(message)
                    .font(BSFont.caption)
                    .foregroundColor(BSColor.textSecondary)
                    .padding(.horizontal, BSSpacing.xs)
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: loadPlanIfNeeded)
        .sheet(isPresented: $showsProMembership) {
            ProMembershipSheetView()
        }
        .sheet(isPresented: $showsProLimit) {
            BSProLimitSheet(
                title: ProLimitReason.roundTripRegeneration.title,
                message: ProLimitReason.roundTripRegeneration.message,
                onPrimary: {
                    showsProLimit = false
                    showsProMembership = true
                },
                onSecondary: {
                    showsProLimit = false
                }
            )
        }
        .bsToastOverlay(toast)
    }

    private var outboundPanel: some View {
        VStack(alignment: .leading, spacing: BSSpacing.md) {
            directionFields([
                ("出发地", $origin, "从哪里出发"),
                ("集合点", $meetingPoint, "入口、朋友汇合点"),
                ("备注", $notes, "偏好或限制")
            ])

            BSSectionHeader(title: "去程安排")
            TextEditor(text: $outboundText)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 180)
                .bsInputField()

            HStack(spacing: BSSpacing.sm) {
                Button {
                    Task { await generateDraft(direction: .outbound) }
                } label: {
                    generationLabel(title: "生成草稿", direction: .outbound)
                }
                .buttonStyle(BSSecondaryButtonStyle())
                .disabled(isGeneratingDirection != nil)

                Button("保存去程") {
                    mutablePlan().saveOutbound(outboundText)
                    try? modelContext.save()
                    message = "去程已保存在本机。"
                    presentToast(.success, message: "去程已保存")
                }
                .buttonStyle(BSPrimaryButtonStyle())
            }
        }
    }

    private var returnPanel: some View {
        VStack(alignment: .leading, spacing: BSSpacing.md) {
            directionFields([
                ("目的地", $destination, "散场后回哪里"),
                ("酒店", $hotel, "酒店或临时落脚点"),
                ("集合点", $meetingPoint, "散场集合位置")
            ])

            BSGlassPanel {
                Toggle(isOn: $returnIsUndecided) {
                    VStack(alignment: .leading, spacing: BSSpacing.xs) {
                        Text("返程先未定")
                            .font(BSFont.headline)
                            .foregroundColor(BSColor.textPrimary)
                        Text("先记下方向，不用立刻决定")
                            .font(BSFont.caption)
                            .foregroundColor(BSColor.textTertiary)
                    }
                }
                .tint(BSColor.Accent.travel)
            }

            BSSectionHeader(title: returnIsUndecided ? "返程备注" : "返程安排")
            TextEditor(text: returnIsUndecided ? $returnNote : $returnText)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 150)
                .bsInputField()

            HStack(spacing: BSSpacing.sm) {
                Button {
                    Task { await generateDraft(direction: .return) }
                } label: {
                    generationLabel(title: "生成草稿", direction: .return)
                }
                .buttonStyle(BSSecondaryButtonStyle())
                .disabled(isGeneratingDirection != nil)

                Button(returnIsUndecided ? "保存备注" : "保存返程") {
                    if returnIsUndecided {
                        mutablePlan().markReturnUndecided(note: returnNote)
                    } else {
                        mutablePlan().saveReturn(returnText)
                    }
                    try? modelContext.save()
                    message = returnIsUndecided ? "未定返程已保存在本机。" : "返程已保存在本机。"
                    presentToast(.success, message: returnIsUndecided ? "返程备注已保存" : "返程已保存")
                }
                .buttonStyle(BSPrimaryButtonStyle())
            }
        }
    }

    private func directionFields(_ fields: [(String, Binding<String>, String)]) -> some View {
        BSGlassPanel {
            VStack(alignment: .leading, spacing: BSSpacing.sm) {
                BSSectionHeader(title: "方向信息")
                ForEach(Array(fields.enumerated()), id: \.offset) { _, field in
                    HStack(spacing: BSSpacing.sm) {
                        Text(field.0)
                            .font(BSFont.caption)
                            .foregroundColor(BSColor.textTertiary)
                            .frame(width: 54, alignment: .leading)
                        TextField(field.2, text: field.1)
                            .bsInputField()
                    }
                }
            }
        }
    }

    private func mutablePlan() -> RoundTripPlan {
        if let plan {
            return plan
        }

        let plan = RoundTripPlan(showID: show.id)
        modelContext.insert(plan)
        return plan
    }

    private func loadPlanIfNeeded() {
        guard !didLoadPlan else { return }
        didLoadPlan = true

        guard let plan else { return }
        outboundText = plan.outboundContent ?? ""
        returnText = plan.returnContent ?? ""
        returnNote = plan.returnNote ?? ""
        returnIsUndecided = plan.returnState == .undecided
    }

    private var entitlement: ProEntitlementState {
        ProEntitlementStorage.decode(entitlementRawValue)
    }

    private func canGenerate(_ feature: ProFeature) -> Bool {
        gate.canGenerate(
            feature: feature,
            hasUsedFreeAllowance: ProUsageStorage
                .decodeUsedFreeGenerationFeatures(usedFreeGenerationFeaturesRawValue)
                .contains(feature),
            entitlement: entitlement
        )
    }

    @ViewBuilder
    private func generationLabel(title: String, direction: RoundTripDirection) -> some View {
        HStack {
            if isGeneratingDirection == direction {
                ProgressView()
            }
            Text(title)
        }
    }

    @MainActor
    private func generateDraft(direction: RoundTripDirection) async {
        let feature: ProFeature = direction == .outbound ? .outboundTripDraft : .returnTripDraft
        guard canGenerate(feature) else {
            message = "免费体验已用完，开通 Pro 后可以重复生成往返计划。"
            showsProLimit = true
            return
        }

        let request = RoundTripDraftRequest(
            show: show,
            direction: direction,
            origin: origin,
            destination: destination,
            hotel: hotel,
            meetingPoint: meetingPoint,
            notes: notes
        )
        guard request.hasEnoughDirectionInformation else {
            message = direction == .outbound ? "请先填写出发地或集合点。" : "请先填写目的地、酒店、集合点或备注。"
            presentToast(.neutral, message: "请先补充方向信息")
            return
        }

        isGeneratingDirection = direction
        defer { isGeneratingDirection = nil }

        do {
            let draft = try await Self.defaultGenerationService().generate(for: request)
            switch direction {
            case .outbound:
                outboundText = draft.editableText
            case .return:
                returnIsUndecided = false
                returnText = draft.editableText
            }
            usedFreeGenerationFeaturesRawValue = ProUsageStorage.markUsed(feature, in: usedFreeGenerationFeaturesRawValue)
            message = "草稿已生成，确认后可以保存。"
            presentToast(.success, message: "草稿已生成")
        } catch RoundTripDraftError.insufficientDirectionInformation {
            message = "请先补充方向信息。"
            presentToast(.neutral, message: "请先补充方向信息")
        } catch {
            message = "暂时没生成成功，请稍后再试。"
            presentToast(.failure, message: "生成失败")
        }
    }

    private static func defaultGenerationService() -> RemoteRoundTripDraftGenerationService {
        let baseURL = URL(string: "https://beforeshow-d2g0gv0zz4cc249dc-1312569550.ap-shanghai.app.tcloudbase.com/generate")!
        return RemoteRoundTripDraftGenerationService(
            baseURL: baseURL,
            appInstanceId: UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString,
            appSignature: "beforeshow-app-signature-v1"
        )
    }

    private func presentToast(_ tone: BSToastTone, message: String) {
        let payload = BSToastPayload(tone: tone, message: message)
        toast = payload
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            if toast == payload {
                toast = nil
            }
        }
    }
}

struct ShowPreparationView: View {
    let show: Show

    @Environment(\.modelContext) private var modelContext
    @Query private var plans: [ShowPreparationPlan]
    @State private var notes = ""
    @State private var reminderEnabled = false
    @State private var reminderDate = Date()
    @State private var didLoadPlan = false
    @State private var message: String?

    private let guide = ShowPreparationGuide()

    private var plan: ShowPreparationPlan? {
        plans.first { $0.showID == show.id }
    }

    var body: some View {
        BSStageScaffold(title: "现场准备", subtitle: show.name) {
            VStack(alignment: .leading, spacing: BSSpacing.md) {
                BSSectionHeader(title: "准备事项")
                ForEach(guide.sections(for: show)) { section in
                    VStack(alignment: .leading, spacing: BSSpacing.sm) {
                        Text(section.title)
                            .font(BSFont.caption)
                            .foregroundColor(BSColor.textSecondary)
                        ForEach(section.suggestions) { suggestion in
                            preparationSuggestionRow(suggestion)
                        }
                    }
                }
            }

            BSGlassPanel {
                VStack(alignment: .leading, spacing: BSSpacing.md) {
                    Toggle(isOn: $reminderEnabled) {
                        VStack(alignment: .leading, spacing: BSSpacing.xs) {
                            Text("准备提醒")
                                .font(BSFont.headline)
                                .foregroundColor(BSColor.textPrimary)
                            Text("到点前把状态拉回来")
                                .font(BSFont.caption)
                                .foregroundColor(BSColor.textTertiary)
                        }
                    }
                    .tint(BSColor.Accent.prepare)

                    if reminderEnabled {
                        DatePicker("提醒时间", selection: $reminderDate)
                            .datePickerStyle(.compact)
                            .foregroundColor(BSColor.textSecondary)
                    }

                    Button("保存提醒") {
                        mutablePlan().updateReminderDate(reminderEnabled ? reminderDate : nil)
                        try? modelContext.save()
                        message = "准备提醒时间已保存在本机。"
                    }
                    .buttonStyle(BSPrimaryButtonStyle())
                }
            }

            VStack(alignment: .leading, spacing: BSSpacing.sm) {
                BSSectionHeader(title: "个人备注")
                TextField("给自己留一点准备备注", text: $notes, axis: .vertical)
                    .lineLimit(3...6)
                    .bsInputField()
                Button("保存备注") {
                    mutablePlan().updateNotes(notes)
                    try? modelContext.save()
                    message = "准备备注已保存在本机。"
                }
                .buttonStyle(BSSecondaryButtonStyle())
            }

            if let message {
                Text(message)
                    .font(BSFont.caption)
                    .foregroundColor(BSColor.textSecondary)
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: loadPlanIfNeeded)
        .onChange(of: reminderEnabled) { _, newValue in
            if !newValue {
                mutablePlan().updateReminderDate(nil)
                try? modelContext.save()
            }
        }
        .onChange(of: reminderDate) { _, newValue in
            guard reminderEnabled else { return }
            mutablePlan().updateReminderDate(newValue)
            try? modelContext.save()
        }
    }

    private func preparationSuggestionRow(_ suggestion: ShowPreparationSuggestion) -> some View {
        let checked = mutablePlan().isChecked(suggestion.text)
        return Button {
            mutablePlan().setChecked(!checked, suggestionText: suggestion.text)
            try? modelContext.save()
        } label: {
            HStack(alignment: .top, spacing: BSSpacing.sm) {
                Image(systemName: checked ? "checkmark.square.fill" : "square")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(checked ? BSColor.Accent.prepare : BSColor.textTertiary)
                Text(suggestion.text)
                    .font(BSFont.body)
                    .foregroundColor(checked ? BSColor.textTertiary : BSColor.textPrimary)
                    .strikethrough(checked, color: BSColor.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(14)
            .background(checked ? BSColor.Accent.prepare.opacity(0.08) : Color.white.opacity(0.035))
            .clipShape(RoundedRectangle(cornerRadius: BSRadius.md))
            .overlay(
                RoundedRectangle(cornerRadius: BSRadius.md)
                    .stroke(checked ? BSColor.Accent.prepare.opacity(0.26) : BSColor.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func mutablePlan() -> ShowPreparationPlan {
        if let plan {
            return plan
        }

        let plan = ShowPreparationPlan(showID: show.id)
        modelContext.insert(plan)
        return plan
    }

    private func loadPlanIfNeeded() {
        guard !didLoadPlan else { return }
        didLoadPlan = true
        guard let plan else { return }
        notes = plan.notes ?? ""
        if let savedReminderDate = plan.reminderDate {
            reminderEnabled = true
            reminderDate = savedReminderDate
        }
    }
}

struct ShowFragmentListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ShowFragment.createdAt) private var fragments: [ShowFragment]

    let show: Show
    @State private var text = ""
    @State private var selectedMediaItems: [PhotosPickerItem] = []
    @State private var pendingGalleryReferences: [(localIdentifier: String, kind: ShowFragmentGalleryMediaKind)] = []
    @State private var pendingMediaPreviews: [PendingFragmentMediaPreview] = []
    @State private var audioRecorder: AVAudioRecorder?
    @State private var pendingAudioRelativePath: String?
    @State private var pendingAudioDuration: TimeInterval?
    @State private var pendingAudioURL: URL?
    @State private var isRecordingAudio = false
    @State private var isShowingAudioDrawer = false
    @State private var composerExpanded = true
    @State private var message: String?
    @State private var editingFragment: ShowFragment?
    @State private var deletingFragment: ShowFragment?
    @State private var toast: BSToastPayload?

    private var showFragments: [ShowFragment] {
        ShowFragment.sortedByCreationTime(fragments.filter { $0.show.id == show.id })
    }

    var body: some View {
        BSStageScaffold(title: "现场碎片", subtitle: show.name, bottomPadding: 96) {
            composer
                .onChange(of: selectedMediaItems) { _, newItems in
                    Task {
                        await updatePendingMedia(from: newItems)
                    }
                }

            VStack(alignment: .leading, spacing: BSSpacing.sm) {
                BSSectionHeader(title: "已保存")
                if showFragments.isEmpty {
                    BSEmptyPanel(
                        iconName: "sparkles.rectangle.stack",
                        title: "现场碎片为空",
                        message: "还没有现场碎片。保存照片、视频、文字或语音后会出现在这里。"
                    )
                } else {
                    ForEach(showFragments) { fragment in
                        FragmentTimelineCard(
                            fragment: fragment,
                            onEdit: {
                                editingFragment = fragment
                            },
                            onDelete: {
                                deletingFragment = fragment
                            }
                        )
                    }
                }
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editingFragment) { fragment in
            FragmentEditorSheet(fragment: fragment) {
                presentToast(.success, message: "碎片已更新")
            } onFailed: {
                presentToast(.failure, message: "更新失败")
            }
        }
        .sheet(item: $deletingFragment) { fragment in
            BSDangerConfirmationSheet(
                title: "删除现场碎片？",
                message: "这条文字、相册引用和本地语音文件都会从 BeforeShow 中移除。",
                destructiveTitle: "删除",
                onConfirm: {
                    deleteAfterDismissingConfirmation(fragment)
                },
                onCancel: {
                    deletingFragment = nil
                }
            )
        }
        .sheet(isPresented: $isShowingAudioDrawer) {
            FragmentAudioCaptureSheet(
                audioRecorder: audioRecorder,
                pendingAudioURL: pendingAudioURL,
                pendingAudioDuration: pendingAudioDuration,
                isRecordingAudio: isRecordingAudio,
                onStart: startAudioRecording,
                onStop: stopAudioRecording,
                onDismiss: {
                    isShowingAudioDrawer = false
                }
            )
        }
        .bsToastOverlay(toast)
    }

    private var composer: some View {
        BSGlassPanel {
            VStack(alignment: .leading, spacing: BSSpacing.md) {
                HStack {
                    Text("添加新的现场碎片")
                        .font(BSFont.headline)
                        .foregroundColor(BSColor.textPrimary)
                    Spacer()
                    Button {
                        withAnimation(.easeInOut(duration: 0.22)) {
                            composerExpanded.toggle()
                        }
                    } label: {
                        Image(systemName: composerExpanded ? "chevron.up" : "plus")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(BSColor.textPrimary)
                            .frame(width: 32, height: 32)
                            .background(Color.white.opacity(0.08))
                            .clipShape(Circle())
                    }
                }

                if composerExpanded {
                    TextField("写下一点这一场里的瞬间", text: $text, axis: .vertical)
                        .lineLimit(3...6)
                        .bsInputField()

                    HStack(spacing: BSSpacing.sm) {
                        PhotosPicker(
                            selection: $selectedMediaItems,
                            maxSelectionCount: 12,
                            matching: .any(of: [.images, .videos])
                        ) {
                            Label("照片/视频", systemImage: "photo.stack")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(BSSecondaryButtonStyle())

                        Button {
                            isShowingAudioDrawer = true
                        } label: {
                            Label(pendingAudioURL == nil ? "语音片段" : "查看语音", systemImage: pendingAudioURL == nil ? "mic.circle" : "waveform")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(BSSecondaryButtonStyle())
                    }

                    if !pendingMediaPreviews.isEmpty {
                        PendingMediaPreviewStrip(previews: pendingMediaPreviews)
                    }

                    if isRecordingAudio {
                        FragmentAudioPlaybackRow(
                            title: "正在录音",
                            subtitle: "录完后可以试听",
                            audioURL: nil,
                            duration: audioRecorder?.currentTime,
                            isRecording: true,
                            audioRecorder: audioRecorder
                        )
                    } else if let pendingAudioURL {
                        FragmentAudioPlaybackRow(
                            title: "语音片段",
                            subtitle: "保存前可以试听",
                            audioURL: pendingAudioURL,
                            duration: pendingAudioDuration,
                            isRecording: false
                        )
                    }

                    Button("保存碎片") {
                        saveFragment()
                    }
                    .buttonStyle(BSPrimaryButtonStyle())
                    .disabled(!canSaveFragment || isRecordingAudio)

                    if let message {
                        Text(message)
                            .font(BSFont.caption)
                            .foregroundColor(BSColor.textTertiary)
                    }
                }
            }
        }
    }

    private var canSaveFragment: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !pendingGalleryReferences.isEmpty
            || pendingAudioRelativePath != nil
    }

    private func saveFragment() {
        do {
            let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
            let fragment = try ShowFragment(show: show, text: trimmedText.isEmpty ? nil : trimmedText)
            for reference in pendingGalleryReferences {
                _ = fragment.addGalleryMediaReference(
                    assetLocalIdentifier: reference.localIdentifier,
                    kind: reference.kind
                )
            }

            if let pendingAudioRelativePath {
                _ = fragment.attachAudioReference(
                    relativePath: pendingAudioRelativePath,
                    duration: pendingAudioDuration
                )
            }

            modelContext.insert(fragment)
            try modelContext.save()
            text = ""
            selectedMediaItems = []
            pendingGalleryReferences = []
            pendingMediaPreviews = []
            pendingAudioRelativePath = nil
            pendingAudioDuration = nil
            pendingAudioURL = nil
            message = "已保存在本机。"
            presentToast(.success, message: "碎片已保存")
        } catch {
            message = "请先写一点内容，或添加照片、视频、语音片段。"
            presentToast(.failure, message: "保存失败")
        }
    }

    private func deleteAfterDismissingConfirmation(_ fragment: ShowFragment) {
        deletingFragment = nil
        Task { @MainActor in
            await Task.yield()
            delete(fragment)
        }
    }

    private func delete(_ fragment: ShowFragment) {
        do {
            try LocalAppDataDeletionService(audioStorage: .applicationSupport())
                .deleteFragment(fragment, in: modelContext)
            try modelContext.save()
            deletingFragment = nil
            message = "现场碎片已删除。"
            presentToast(.neutral, message: "碎片已删除")
        } catch {
            message = "删除失败，请稍后再试。"
            presentToast(.failure, message: "删除失败")
        }
    }

    private func presentToast(_ tone: BSToastTone, message: String) {
        let payload = BSToastPayload(tone: tone, message: message)
        toast = payload
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            if toast == payload {
                toast = nil
            }
        }
    }

    private func toggleAudioRecording() {
        if isRecordingAudio {
            stopAudioRecording()
        } else {
            startAudioRecording()
        }
    }

    private func startAudioRecording() {
        do {
            let storage = ShowFragmentAudioStorage.applicationSupport()
            let relativePath = "FragmentAudio/\(UUID().uuidString).m4a"
            let url = storage.rootDirectory.appendingPathComponent(relativePath, isDirectory: false)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default)
            try session.setActive(true)

            let recorder = try AVAudioRecorder(
                url: url,
                settings: [
                    AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                    AVSampleRateKey: 44_100,
                    AVNumberOfChannelsKey: 1,
                    AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue
                ]
            )
            recorder.record()
            audioRecorder = recorder
            pendingAudioRelativePath = relativePath
            pendingAudioURL = url
            pendingAudioDuration = nil
            isRecordingAudio = true
            audioRecorder?.isMeteringEnabled = true
            message = "正在录音。"
        } catch {
            message = "无法开始录音，请检查麦克风权限。"
        }
    }

    private func stopAudioRecording() {
        pendingAudioDuration = audioRecorder?.currentTime
        audioRecorder?.stop()
        audioRecorder = nil
        isRecordingAudio = false
        message = "语音片段已添加，保存后会留在这个现场碎片里。"
    }

    @MainActor
    private func updatePendingMedia(from items: [PhotosPickerItem]) async {
        var references: [(localIdentifier: String, kind: ShowFragmentGalleryMediaKind)] = []
        var previews: [PendingFragmentMediaPreview] = []

        for item in items {
            let kind: ShowFragmentGalleryMediaKind = item.supportedContentTypes.contains { type in
                type.conforms(to: .movie)
            } ? .video : .photo

            if let localIdentifier = item.itemIdentifier {
                references.append((localIdentifier, kind))
            }

            let image = await loadPreviewImage(from: item)
            previews.append(PendingFragmentMediaPreview(kind: kind, image: image))
        }

        pendingGalleryReferences = references
        pendingMediaPreviews = previews
    }

    private func loadPreviewImage(from item: PhotosPickerItem) async -> UIImage? {
        guard let data = try? await item.loadTransferable(type: Data.self) else {
            return nil
        }

        return UIImage(data: data)
    }
}

private struct PendingFragmentMediaPreview: Identifiable {
    let id = UUID()
    let kind: ShowFragmentGalleryMediaKind
    let image: UIImage?
}

private struct PendingMediaPreviewStrip: View {
    let previews: [PendingFragmentMediaPreview]

    var body: some View {
        VStack(alignment: .leading, spacing: BSSpacing.sm) {
            HStack(spacing: BSSpacing.xs) {
                Image(systemName: "photo.stack")
                Text("已选择 \(previews.count) 个照片/视频")
            }
            .font(BSFont.caption)
            .foregroundColor(BSColor.textTertiary)

            ScrollView(.horizontal) {
                HStack(spacing: BSSpacing.sm) {
                    ForEach(previews) { preview in
                        FragmentMediaThumbnail(image: preview.image, kind: preview.kind)
                            .frame(width: 78, height: 78)
                    }
                }
                .padding(.vertical, 1)
            }
            .scrollIndicators(.hidden)
        }
    }
}

private struct FragmentAudioCaptureSheet: View {
    let audioRecorder: AVAudioRecorder?
    let pendingAudioURL: URL?
    let pendingAudioDuration: TimeInterval?
    let isRecordingAudio: Bool
    let onStart: () -> Void
    let onStop: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: BSSpacing.lg) {
            Capsule()
                .fill(Color.white.opacity(0.22))
                .frame(width: 42, height: 4)

            VStack(alignment: .leading, spacing: BSSpacing.xs) {
                Text("语音片段")
                    .font(BSFont.headline)
                    .foregroundColor(BSColor.textPrimary)
                Text(isRecordingAudio ? "正在收录这一刻的声音" : "录完后可以先试听，再保存到现场碎片。")
                    .font(BSFont.caption)
                    .foregroundColor(BSColor.textTertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            FragmentAudioPlaybackRow(
                title: isRecordingAudio ? "录音中" : "语音预览",
                subtitle: isRecordingAudio ? "点击停止后可试听" : "点击试听",
                audioURL: pendingAudioURL,
                duration: pendingAudioDuration,
                isRecording: isRecordingAudio,
                audioRecorder: audioRecorder,
                waveformWidth: 188
            )

            HStack(spacing: BSSpacing.sm) {
                Button(action: isRecordingAudio ? onStop : onStart) {
                    Label(isRecordingAudio ? "停止录音" : "开始录音", systemImage: isRecordingAudio ? "stop.circle.fill" : "mic.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(BSPrimaryButtonStyle())

                Button("完成") {
                    onDismiss()
                }
                .buttonStyle(BSSecondaryButtonStyle())
                .disabled(isRecordingAudio)
            }
        }
        .padding(.horizontal, BSSpacing.lg)
        .padding(.top, BSSpacing.md)
        .padding(.bottom, BSSpacing.xl)
        .presentationDetents([.height(312)])
        .presentationDragIndicator(.hidden)
        .preferredColorScheme(.dark)
        .background(Color.black)
    }
}

private struct FragmentEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let fragment: ShowFragment
    var onSaved: () -> Void
    var onFailed: () -> Void

    @State private var text: String
    @State private var message: String?

    init(fragment: ShowFragment, onSaved: @escaping () -> Void, onFailed: @escaping () -> Void) {
        self.fragment = fragment
        self.onSaved = onSaved
        self.onFailed = onFailed
        _text = State(initialValue: fragment.text ?? "")
    }

    var body: some View {
        VStack(spacing: BSSpacing.lg) {
            Capsule()
                .fill(Color.white.opacity(0.22))
                .frame(width: 42, height: 4)

            VStack(alignment: .leading, spacing: BSSpacing.md) {
                VStack(alignment: .leading, spacing: BSSpacing.xs) {
                    Text("编辑现场碎片")
                        .font(BSFont.headline)
                        .foregroundColor(BSColor.textPrimary)
                    Text("只修改这条碎片的文字，照片、视频和语音会继续保留。")
                        .font(BSFont.caption)
                        .foregroundColor(BSColor.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                TextField("写下一点这一场里的瞬间", text: $text, axis: .vertical)
                    .lineLimit(4...8)
                    .bsInputField()

                if let message {
                    Text(message)
                        .font(BSFont.caption)
                        .foregroundColor(BSColor.Accent.fragment)
                }
            }

            HStack(spacing: BSSpacing.sm) {
                Button("取消") {
                    dismiss()
                }
                .buttonStyle(BSSecondaryButtonStyle())

                Button("保存") {
                    save()
                }
                .buttonStyle(BSPrimaryButtonStyle())
            }
        }
        .padding(.horizontal, BSSpacing.lg)
        .padding(.top, BSSpacing.md)
        .padding(.bottom, BSSpacing.xl)
        .presentationDetents([.height(360)])
        .presentationDragIndicator(.hidden)
        .preferredColorScheme(.dark)
        .background(Color.black)
    }

    private func save() {
        do {
            try fragment.updateText(text)
            try modelContext.save()
            onSaved()
            dismiss()
        } catch {
            message = "文字不能为空。"
            onFailed()
        }
    }
}

private extension ShowFragmentAudioReference {
    var durationText: String {
        guard let duration else { return "" }
        return "\(Int(duration.rounded())) 秒"
    }
}

private struct FragmentTimelineCard: View {
    let fragment: ShowFragment
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: BSSpacing.sm) {
            HStack(spacing: BSSpacing.sm) {
                Text(fragment.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(BSFont.caption)
                    .foregroundColor(BSColor.textTertiary.opacity(0.78))

                Spacer(minLength: BSSpacing.sm)

                Button(action: onEdit) {
                    Image(systemName: "pencil")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(BSColor.textSecondary)
                        .frame(width: 32, height: 32)
                        .background(Color.white.opacity(0.06))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("编辑现场碎片")

                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(BSColor.Accent.fragment)
                        .frame(width: 32, height: 32)
                        .background(BSColor.Accent.fragment.opacity(0.10))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("删除现场碎片")
            }

            if let text = fragment.text {
                Text(text)
                    .font(BSFont.body)
                    .foregroundColor(BSColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !fragment.galleryMediaReferences.isEmpty {
                HStack(spacing: BSSpacing.xs) {
                    ForEach(fragment.galleryMediaReferences.prefix(6)) { reference in
                        GalleryMediaThumbnailView(reference: reference)
                            .frame(width: 58, height: 58)
                    }
                }
            }

            if let audioReference = fragment.audioReference {
                FragmentAudioPlaybackRow(
                    title: "语音片段",
                    subtitle: audioReference.durationText,
                    audioURL: ShowFragmentAudioStorage.applicationSupport().url(for: audioReference),
                    duration: audioReference.duration,
                    isRecording: false
                )
            }

        }
        .padding(BSSpacing.md)
        .background(Color.white.opacity(0.035))
        .clipShape(RoundedRectangle(cornerRadius: BSRadius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: BSRadius.lg)
                .stroke(BSColor.border, lineWidth: 1)
        )
    }
}

private struct FragmentMediaThumbnail: View {
    let image: UIImage?
    let kind: ShowFragmentGalleryMediaKind

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(0.055))
                    .overlay(
                        Image(systemName: kind == .video ? "video.fill" : "photo.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(BSColor.textTertiary)
                    )
            }

            if kind == .video {
                Image(systemName: "play.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(BSColor.textPrimary)
                    .frame(width: 22, height: 22)
                    .background(Color.black.opacity(0.52))
                    .clipShape(Circle())
                    .padding(5)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(BSColor.border, lineWidth: 1)
        )
    }
}

private struct GalleryMediaThumbnailView: View {
    let reference: ShowFragmentGalleryMediaReference
    @State private var image: UIImage?
    @State private var requestedAssetLocalIdentifier: String?

    var body: some View {
        FragmentMediaThumbnail(image: image, kind: reference.kind)
            .task(id: reference.assetLocalIdentifier) {
                guard requestedAssetLocalIdentifier != reference.assetLocalIdentifier else { return }
                requestedAssetLocalIdentifier = reference.assetLocalIdentifier
                image = await loadThumbnail()
            }
    }

    private func loadThumbnail() async -> UIImage? {
        await withCheckedContinuation { continuation in
            let result = PHAsset.fetchAssets(
                withLocalIdentifiers: [reference.assetLocalIdentifier],
                options: nil
            )
            guard let asset = result.firstObject else {
                continuation.resume(returning: nil)
                return
            }

            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.resizeMode = .fast
            options.isNetworkAccessAllowed = false
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: CGSize(width: 180, height: 180),
                contentMode: .aspectFill,
                options: options
            ) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }
}

private struct FragmentAudioPlaybackRow: View {
    let title: String
    let subtitle: String
    let audioURL: URL?
    let duration: TimeInterval?
    let isRecording: Bool
    var audioRecorder: AVAudioRecorder?
    var waveformWidth: CGFloat = 112

    @State private var audioPlayer: AVAudioPlayer?
    @State private var isPlaying = false
    @State private var waveformSamples: [Double] = []

    var body: some View {
        HStack(spacing: BSSpacing.sm) {
            Button {
                togglePlayback()
            } label: {
                Image(systemName: isRecording ? "waveform" : (isPlaying ? "pause.fill" : "play.fill"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(BSColor.textPrimary)
                    .frame(width: 32, height: 32)
                    .background(Color.white.opacity(0.09))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(audioURL == nil || isRecording)
            .accessibilityLabel(isPlaying ? "暂停语音片段" : "试听语音片段")

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(BSColor.textSecondary)
                Text(detailText)
                    .font(BSFont.caption)
                    .foregroundColor(BSColor.textTertiary)
            }

            Spacer(minLength: 0)

            if isRecording {
                RecordingWaveformView(recorder: audioRecorder)
                    .frame(width: waveformWidth, height: 28)
            } else {
                AudioWaveformView(samples: waveformSamples, isActive: isPlaying)
                    .frame(width: waveformWidth, height: 28)
            }
        }
        .padding(10)
        .background(Color.white.opacity(0.035))
        .clipShape(RoundedRectangle(cornerRadius: BSRadius.md))
        .overlay(
            RoundedRectangle(cornerRadius: BSRadius.md)
                .stroke(BSColor.border, lineWidth: 1)
        )
        .task(id: audioURL) {
            await loadWaveformSamples()
        }
    }

    private var detailText: String {
        if isRecording {
            return "录音中"
        }
        if !subtitle.isEmpty {
            return subtitle
        }
        guard let duration else {
            return "点击试听"
        }
        return "\(Int(duration.rounded())) 秒"
    }

    private func togglePlayback() {
        guard let audioURL else { return }

        if isPlaying {
            audioPlayer?.pause()
            isPlaying = false
            return
        }

        do {
            let player = try AVAudioPlayer(contentsOf: audioURL)
            player.prepareToPlay()
            player.play()
            audioPlayer = player
            isPlaying = true

            Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64((max(player.duration, 0.5) * 1_000_000_000).rounded()))
                if !player.isPlaying {
                    isPlaying = false
                }
            }
        } catch {
            isPlaying = false
        }
    }

    @MainActor
    private func loadWaveformSamples() async {
        guard let audioURL else {
            waveformSamples = []
            return
        }

        do {
            waveformSamples = try AudioWaveformSampler().samples(from: audioURL, bucketCount: 28)
        } catch {
            waveformSamples = []
        }
    }
}

private struct RecordingWaveformView: View {
    let recorder: AVAudioRecorder?
    @State private var samples = Array(repeating: 0.12, count: 28)
    @State private var tick = 0

    var body: some View {
        AudioWaveformView(samples: samples, isActive: true)
            .task {
                while !Task.isCancelled {
                    let normalized: Double
                    if let recorder {
                        recorder.updateMeters()
                        let power = recorder.averagePower(forChannel: 0)
                        normalized = max(0.08, min(1.0, Double((power + 54) / 54)))
                    } else {
                        let phase = Double(tick) * 0.72
                        normalized = 0.18 + 0.58 * abs(sin(phase))
                    }

                    samples.removeFirst()
                    samples.append(normalized)
                    tick += 1
                    try? await Task.sleep(nanoseconds: 90_000_000)
                }
            }
    }
}

private struct AudioWaveformView: View {
    let samples: [Double]
    var isActive = false

    private var displaySamples: [Double] {
        samples.isEmpty
            ? [0.26, 0.48, 0.32, 0.62, 0.38, 0.55, 0.30, 0.45, 0.36, 0.58, 0.31, 0.50, 0.28, 0.40]
            : samples
    }

    var body: some View {
        HStack(alignment: .center, spacing: 3) {
            ForEach(Array(displaySamples.enumerated()), id: \.offset) { _, sample in
                Capsule()
                    .fill(isActive ? BSColor.Accent.fragment.opacity(0.92) : BSColor.textTertiary.opacity(0.55))
                    .frame(maxWidth: .infinity)
                    .frame(height: max(5, CGFloat(sample) * 26))
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }
}

#if DEBUG
struct DebugFragmentPreviewStateView: View {
    var body: some View {
        BSStageScaffold(title: "现场碎片", subtitle: "预览状态", bottomPadding: 96) {
            BSGlassPanel {
                VStack(alignment: .leading, spacing: BSSpacing.md) {
                    Text("添加新的现场碎片")
                        .font(BSFont.headline)
                        .foregroundColor(BSColor.textPrimary)

                    Text("排队时听到里面在试音，鼓点一响整个人就紧张了。")
                        .font(BSFont.body)
                        .foregroundColor(BSColor.textPrimary)
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.white.opacity(0.045))
                        .clipShape(RoundedRectangle(cornerRadius: BSRadius.md))

                    PendingMediaPreviewStrip(previews: [
                        PendingFragmentMediaPreview(kind: .photo, image: nil),
                        PendingFragmentMediaPreview(kind: .video, image: nil),
                        PendingFragmentMediaPreview(kind: .photo, image: nil)
                    ])

                    FragmentAudioPlaybackRow(
                        title: "语音片段",
                        subtitle: "12 秒",
                        audioURL: nil,
                        duration: 12,
                        isRecording: false,
                        waveformWidth: 168
                    )

                    Button("保存碎片") {}
                        .buttonStyle(BSPrimaryButtonStyle())
                }
            }

            VStack(alignment: .leading, spacing: BSSpacing.sm) {
                BSSectionHeader(title: "已保存")
                VStack(alignment: .leading, spacing: BSSpacing.sm) {
                    Text("散场后回头看了一眼灯牌，觉得这场会记很久。")
                        .font(BSFont.body)
                        .foregroundColor(BSColor.textPrimary)

                    HStack(spacing: BSSpacing.xs) {
                        FragmentMediaThumbnail(image: nil, kind: .photo)
                            .frame(width: 58, height: 58)
                        FragmentMediaThumbnail(image: nil, kind: .video)
                            .frame(width: 58, height: 58)
                    }

                    FragmentAudioPlaybackRow(
                        title: "语音片段",
                        subtitle: "8 秒",
                        audioURL: nil,
                        duration: 8,
                        isRecording: false,
                        waveformWidth: 168
                    )
                }
                .padding(BSSpacing.md)
                .background(Color.white.opacity(0.035))
                .clipShape(RoundedRectangle(cornerRadius: BSRadius.lg))
                .overlay(
                    RoundedRectangle(cornerRadius: BSRadius.lg)
                        .stroke(BSColor.border, lineWidth: 1)
                )
            }
        }
    }
}

struct DebugFragmentAudioDrawerPreviewView: View {
    var body: some View {
        ZStack(alignment: .bottom) {
            CurrentShowStageBackground()
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: BSSpacing.lg) {
                Spacer()
                Text("现场碎片")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundColor(BSColor.textPrimary)
                Text("语音片段从底部抽屉开始录制。")
                    .font(BSFont.body)
                    .foregroundColor(BSColor.textTertiary)
                Spacer()
            }
            .padding(.horizontal, BSSpacing.md)

            FragmentAudioCaptureSheet(
                audioRecorder: nil,
                pendingAudioURL: nil,
                pendingAudioDuration: nil,
                isRecordingAudio: true,
                onStart: {},
                onStop: {},
                onDismiss: {}
            )
            .background(Color.black)
        }
        .preferredColorScheme(.dark)
    }
}
#endif
