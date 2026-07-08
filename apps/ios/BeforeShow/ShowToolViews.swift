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

private struct BSTipPromptCard: View {
    let iconName: String
    let eyebrow: String
    let message: String
    var accent: Color = BSColor.Accent.music
    var buttonTitle: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(accent.opacity(0.22))
                    .frame(width: 38, height: 38)
                    .blur(radius: 12)

                Image(systemName: iconName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(accent)
                    .frame(width: 36, height: 36)
                    .background(Color.white.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.white.opacity(0.10), lineWidth: 0.5)
                    )
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(eyebrow)
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(1.2)
                    .foregroundColor(BSColor.textTertiary)
                    .textCase(.uppercase)

                Text(message)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(BSColor.textSecondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            if let buttonTitle, let action {
                Button(buttonTitle, action: action)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.black.opacity(0.88))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(BSColor.brandGradientSoft))
                    .clipShape(Capsule())
            }
        }
        .padding(13)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color.white.opacity(0.055))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.white.opacity(0.10), lineWidth: 0.75)
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
                        NavigationLink {
                            RoundTripPlanView(show: show)
                        } label: {
                            CurrentToolTile(
                                iconName: "tram.fill",
                                title: "去程计划",
                                subtitle: "怎么去、几点到",
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

    @Environment(\.modelContext) private var modelContext
    @Query private var videos: [ShowVideo]
    @State private var navigator = ShowVideoWebViewNavigator()
    @State private var message: String?
    @State private var toast: BSToastPayload?

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
            BSTipPromptCard(
                iconName: "play.rectangle.fill",
                eyebrow: "Tips · 现场预热",
                message: hasVideos
                    ? "不用补课，挑一条有感觉的看就好。先让耳朵和眼睛知道今晚会发生什么。"
                    : "还没整理现场视频，可以先找几条真正的现场，开场前看看氛围。",
                accent: BSColor.Accent.video,
                buttonTitle: hasVideos ? nil : "找几条看看",
                action: hasVideos ? nil : { organizeFixtureVideos() }
            )

            Text(currentShowTitle)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(BSColor.textTertiary)

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
                    title: "还没有现场视频",
                    message: "不用一下看很多，先整理几条有现场感的就够了。",
                    buttonTitle: "找几条看看",
                    buttonIconName: "sparkles"
                ) {
                    organizeFixtureVideos()
                }
            }

            if let message {
                Text(message)
                    .font(BSFont.caption)
                    .foregroundColor(BSColor.textSecondary)
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
        .bsToastOverlay(toast)
    }

    private var currentShowTitle: String {
        let artist = show.artist?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !artist.isEmpty {
            return "\(artist) · \(show.name)"
        }
        return show.name
    }

    private func organizeFixtureVideos() {
        guard !hasVideos else { return }
        for video in ShowVideoFixture.videos(for: show.id) {
            modelContext.insert(video)
        }
        do {
            try modelContext.save()
            message = "已经先整理几条现场视频。"
            presentToast(.success, message: "现场视频已整理")
        } catch {
            message = "暂时没整理成功，请稍后再试。"
            presentToast(.failure, message: "整理失败")
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
    @State private var newSongArtist = ""
    @State private var showsAddSong = false
    @State private var isGenerating = false
    @State private var message: String?
    @State private var lastGenerationFailed = false
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

    var body: some View {
        BSStageScaffold(title: "候选曲目", subtitle: show.name) {
            if isGenerating {
                BSLoadingStatePanel(
                    title: "正在生成候选曲目",
                    message: "会保存一版可编辑的歌单，你可以删改和调整顺序。"
                )
            }

            if visibleSongs.isEmpty {
                if !isGenerating {
                    emptySongState
                    Button {
                        requestGeneration()
                    } label: {
                        Text(lastGenerationFailed ? "重试" : "生成候选曲目")
                    }
                    .buttonStyle(BSPrimaryButtonStyle())
                    .padding(.top, BSSpacing.sm)
                }
            } else {
                BSTipPromptCard(
                    iconName: "music.note",
                    eyebrow: "Tips · 演前预热",
                    message: "可以先挑几首听起来。",
                    accent: BSColor.Accent.candidate
                )

                songListSections
                addSongDisclosure

                if lastGenerationFailed {
                    Button {
                        requestGeneration()
                    } label: {
                        Text("重试")
                    }
                    .buttonStyle(BSPrimaryButtonStyle())
                    .disabled(isGenerating)
                } else {
                    Button {
                        requestGeneration()
                    } label: {
                        HStack {
                            if isGenerating {
                                ProgressView()
                                    .tint(.black)
                            }
                            Text("重新生成候选曲目")
                        }
                    }
                    .buttonStyle(BSSecondaryButtonStyle())
                    .disabled(isGenerating)
                }
            }

            Text("这只是演前预热，不是官方歌单。重新生成会换一版猜测。")
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
            Button("重新生成", role: .destructive) {
                Task {
                    await generateCandidateSongs()
                }
            }
        } message: {
            Text("会用新的推测替换生成的曲目，保留你手动补充的。")
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
            title: "还没有候选曲目",
            message: "可以先生成一版，再按你的判断调整顺序。"
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

    private var songListSections: some View {
        let generatedGroups = sortedShowGroups.filter { !$0.isUserCurated }
        let userCuratedGroups = sortedShowGroups.filter { $0.isUserCurated }

        return VStack(alignment: .leading, spacing: BSSpacing.lg) {
            if !generatedGroups.isEmpty {
                VStack(alignment: .leading, spacing: BSSpacing.sm) {
                    BSSectionHeader(title: "先挑几首听")
                    ForEach(generatedGroups) { group in
                        songGroupSection(for: group)
                    }
                }
            }
            if !userCuratedGroups.isEmpty {
                VStack(alignment: .leading, spacing: BSSpacing.sm) {
                    BSSectionHeader(title: "我补充的")
                    ForEach(userCuratedGroups) { group in
                        songGroupSection(for: group)
                    }
                }
            }
        }
        .disabled(isGenerating)
    }

    @ViewBuilder
    private func songGroupSection(for group: CandidateSongGroup) -> some View {
        let songs = songsInGroup(group)
        if !songs.isEmpty {
            VStack(alignment: .leading, spacing: BSSpacing.sm) {
                if let artistName = group.artistName {
                    Text(artistName)
                        .font(BSFont.body.weight(.semibold))
                        .foregroundColor(BSColor.textSecondary)
                        .padding(.top, BSSpacing.xs)
                }
                ForEach(Array(songs.enumerated()), id: \.element.id) { index, song in
                    CandidateSongRowView(
                        index: index + 1,
                        canMoveUp: index > 0,
                        canMoveDown: index < songs.count - 1,
                        song: song,
                        onMoveUp: { move(song, direction: .up) },
                        onMoveDown: { move(song, direction: .down) },
                        onRemove: { remove(song) }
                    )
                }
            }
        }
    }

    private func songsInGroup(_ group: CandidateSongGroup) -> [CandidateSong] {
        candidateSongs
            .filter { $0.groupID == group.id }
            .sorted { $0.order < $1.order }
    }

    private var addSongDisclosure: some View {
        VStack(spacing: BSSpacing.sm) {
            if showsAddSong {
                BSGlassPanel {
                    VStack(alignment: .leading, spacing: BSSpacing.sm) {
                        TextField("歌名", text: $newSongName)
                            .bsInputField()
                            .accessibilityLabel("歌名")
                        TextField("艺人，默认 \(fallbackArtistName)", text: $newSongArtist)
                            .bsInputField()
                            .accessibilityLabel("艺人")
                        Button {
                            addSong()
                        } label: {
                            Text("添加")
                        }
                        .buttonStyle(BSPrimaryButtonStyle())
                        .disabled(!canAddSong)
                    }
                }
            }
            Button {
                showsAddSong.toggle()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: showsAddSong ? "chevron.down" : "plus")
                        .font(.system(size: 12, weight: .semibold))
                    Text(showsAddSong ? "收起" : "补充一首")
                        .font(BSFont.caption)
                }
                .foregroundColor(BSColor.textSecondary)
            }
            .buttonStyle(.plain)
            .disabled(isGenerating)
        }
    }

    private func addSong() {
        let trimmedName = newSongName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        let trimmedArtist = newSongArtist.trimmingCharacters(in: .whitespacesAndNewlines)
        let artist = trimmedArtist.isEmpty ? fallbackArtistName : trimmedArtist

        do {
            let group = try mutableUserCuratedGroup()
            let existingSongs = candidateSongs.filter { $0.groupID == group.id }
            let song = try editingService.addSong(
                to: existingSongs,
                groupID: group.id,
                songName: trimmedName,
                artist: artist
            )
            song.isUserAdded = true
            modelContext.insert(song)
            try modelContext.save()
            newSongName = ""
            newSongArtist = ""
            showsAddSong = false
            message = "已添加到候选曲目。"
            presentToast(.success, message: "已添加")
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

    private enum MoveDirection {
        case up
        case down
    }

    private func move(_ song: CandidateSong, direction: MoveDirection) {
        let siblings = candidateSongs
            .filter { $0.groupID == song.groupID }
            .sorted { $0.order < $1.order }
        guard let sourceIndex = siblings.firstIndex(where: { $0.id == song.id }) else { return }
        let destinationIndex = direction == .up ? sourceIndex - 1 : sourceIndex + 1
        guard siblings.indices.contains(destinationIndex) else { return }
        _ = editingService.moveSong(in: siblings, from: sourceIndex, to: destinationIndex)
        do {
            try modelContext.save()
        } catch {
            presentToast(.failure, message: "移动失败")
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
            try replaceCandidateSongs(with: inputs)
            usedFreeGenerationFeaturesRawValue = ProUsageStorage.markUsed(.candidateSongs, in: usedFreeGenerationFeaturesRawValue)
            lastGenerationFailed = false
            message = "候选曲目已更新。"
            presentToast(.success, message: "候选曲目已更新")
        } catch {
            modelContext.rollback()
            lastGenerationFailed = true
            message = "暂时没生成成功，请稍后再试。"
            presentToast(.failure, message: "生成失败")
        }
    }

    @MainActor
    private func replaceCandidateSongs(with inputs: [CandidateSongInput]) throws {
        let showGroupIDs = Set(showGroups.map(\.id))
        let oldSongs = candidateSongs.filter { showGroupIDs.contains($0.groupID) }
        let oldGroups = showGroups

        let preservedInputs = oldSongs
            .filter { $0.isUserAdded }
            .sorted { $0.order < $1.order }
            .map { CandidateSongInput(songName: $0.songName, artist: $0.artist) }

        let grouped = editingService.groupedInputsByArtist(
            inputs: inputs,
            artistInterests: showArtistInterests
        )

        for entry in grouped {
            let group = try CandidateSongGroup(
                showID: show.id,
                artistInterestID: entry.artistInterestID,
                artistName: entry.artistName,
                uncertaintyNote: "候选曲目来自公开信息推测，不代表官方歌单。"
            )
            modelContext.insert(group)

            for song in try editingService.makeSongs(groupID: group.id, inputs: entry.songs) {
                modelContext.insert(song)
            }
        }

        if !preservedInputs.isEmpty {
            let group = try CandidateSongGroup(
                showID: show.id,
                uncertaintyNote: "候选曲目来自公开信息推测，不代表官方歌单。",
                isUserCurated: true
            )
            modelContext.insert(group)
            for song in try editingService.makeSongs(groupID: group.id, inputs: preservedInputs) {
                song.isUserAdded = true
                modelContext.insert(song)
            }
        }

        for song in oldSongs {
            modelContext.delete(song)
        }
        for group in oldGroups {
            modelContext.delete(group)
        }

        try modelContext.save()
    }

    private func mutableUserCuratedGroup() throws -> CandidateSongGroup {
        if let group = showGroups.first(where: { $0.isUserCurated }) {
            return group
        }

        let group = try CandidateSongGroup(
            showID: show.id,
            uncertaintyNote: "候选曲目来自公开信息推测，不代表官方歌单。",
            isUserCurated: true
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
    let canMoveUp: Bool
    let canMoveDown: Bool
    let song: CandidateSong
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: BSSpacing.sm) {
            Text("\(index)")
                .font(BSFont.caption.weight(.semibold))
                .foregroundColor(BSColor.Accent.candidate)
                .frame(width: 28, height: 28)
                .background(BSColor.Accent.candidate.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: BSRadius.sm))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
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

            moveButton("chevron.up", label: "上移", enabled: canMoveUp, action: onMoveUp)
            moveButton("chevron.down", label: "下移", enabled: canMoveDown, action: onMoveDown)

            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(BSColor.textTertiary)
                    .frame(width: 40, height: 40)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("移除")
        }
        .padding(14)
        .background(Color.white.opacity(0.035))
        .clipShape(RoundedRectangle(cornerRadius: BSRadius.md))
        .overlay(
            RoundedRectangle(cornerRadius: BSRadius.md)
                .stroke(BSColor.border, lineWidth: 1)
        )
    }

    private func moveButton(
        _ systemName: String,
        label: String,
        enabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(enabled ? BSColor.textSecondary : BSColor.textTertiary.opacity(0.35))
                .frame(width: 40, height: 40)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(label)
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
    @Query(sort: \SavedOrigin.updatedAt, order: .reverse) private var savedOrigins: [SavedOrigin]

    @State private var origin = ""
    @State private var destination = ""
    @State private var meetingPoint = ""
    @State private var targetArrivalAt = Date()
    @State private var selectedMode: DepartureTransportMode = .publicTransit
    @State private var recommendations: [DepartureTransportMode: DepartureTransportOption] = [:]
    @State private var isSearchingOptions = false
    @State private var searchError: String?
    @State private var showsManualSave = false
    @State private var showsAdvanced = false
    @State private var showsVenueEditor = false
    @State private var manualMode: DepartureTransportMode = .publicTransit
    @State private var manualLeaveAt = Date()
    @State private var manualArriveAt = Date()
    @State private var manualSummary = ""
    @State private var toast: BSToastPayload?
    @State private var didLoadPlan = false

    @StateObject private var locator = OriginLocator()

    private let routeProvider: DepartureRouteProviding = MapKitDepartureRouteProvider()
    private let modeDisplayOrder: [DepartureTransportMode] = [.publicTransit, .taxiReference, .driving]

    init(show: Show) {
        self.show = show
        let showID = show.id
        _plans = Query(
            filter: #Predicate<RoundTripPlan> { $0.showID == showID },
            sort: [SortDescriptor(\RoundTripPlan.updatedAt, order: .reverse)]
        )
    }

    private var plan: RoundTripPlan? {
        plans.first
    }

    private var savedOrigin: SavedOrigin? {
        savedOrigins.first
    }

    private var hasSavedDeparturePlan: Bool {
        plan?.hasSavedDeparturePlan == true
    }

    private var showDestination: ShowDepartureDestination {
        show.departureDestination
    }

    private var trimmedOrigin: String {
        origin.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedDestination: String {
        destination.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canRecommend: Bool {
        !trimmedOrigin.isEmpty && !trimmedDestination.isEmpty
    }

    private var currentRecommendation: DepartureTransportOption? {
        recommendations[selectedMode]
    }

    private var hasAnyRecommendation: Bool {
        !recommendations.isEmpty
    }

    private var defaultTargetArrivalAt: Date {
        Calendar.current.date(byAdding: .hour, value: -1, to: effectiveStartDate) ?? effectiveStartDate
    }

    private var effectiveStartDate: Date {
        let calendar = Calendar.current
        let day = calendar.dateComponents([.year, .month, .day], from: show.effectiveDate)
        let clock = calendar.dateComponents([.hour, .minute, .second], from: show.startTime)
        return calendar.date(
            from: DateComponents(
                calendar: calendar,
                year: day.year,
                month: day.month,
                day: day.day,
                hour: clock.hour,
                minute: clock.minute,
                second: clock.second
            )
        ) ?? show.startTime
    }

    private var isShowStarted: Bool {
        effectiveStartDate <= Date()
    }

    var body: some View {
        BSStageScaffold(title: "去程计划", subtitle: show.name) {
            BSTipPromptCard(
                iconName: "tram.fill",
                eyebrow: "Tips · 怎么去",
                message: hasSavedDeparturePlan
                    ? "出门方案已经保存好了。当天首页会提醒你几点出门、怎么去。"
                    : "填上出发地，路线会按这场现场的信息自动生成。",
                accent: BSColor.Accent.travel
            )

            recommendationPanel

            actionArea

            destinationReadOnlySection

            if showsManualSave {
                manualSavePanel
            }

            advancedSection

            Text("BeforeShow 只保存出门方案，不替代实时地图导航。出发前请打开地图确认实时路况和班次。")
                .font(BSFont.caption)
                .foregroundColor(BSColor.textTertiary)
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: loadPlanIfNeeded)
        .sheet(isPresented: $showsVenueEditor) {
            ShowDraftEditorView(
                title: "编辑现场",
                draft: ShowDraft(show: show),
                saveTitle: "保存"
            ) { draft in
                applyShowDraft(draft)
                destination = show.departureDestination.text
            }
        }
        .bsToastOverlay(toast)
    }

    private var recommendationPanel: some View {
        BSGlassPanel {
            VStack(alignment: .leading, spacing: BSSpacing.md) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("出发地")
                        .font(BSFont.caption)
                        .foregroundColor(BSColor.textTertiary)
                    HStack(spacing: BSSpacing.xs) {
                        TextField("家、公司或酒店", text: $origin)
                            .bsInputField()
                            .accessibilityLabel("出发地")
                            .submitLabel(.search)
                            .onSubmit {
                                if canRecommend {
                                    Task { await searchRecommendations(force: false) }
                                }
                            }
                        if locator.isLocating {
                            ProgressView()
                                .tint(BSColor.textPrimary)
                                .frame(width: 38, height: 38)
                        } else {
                            Button {
                                Task { await handleLocate() }
                            } label: {
                                Image(systemName: "location.fill")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(BSColor.Accent.travel)
                                    .frame(width: 38, height: 38)
                                    .background(Color.white.opacity(0.045))
                                    .clipShape(RoundedRectangle(cornerRadius: BSRadius.md))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: BSRadius.md)
                                            .stroke(BSColor.border, lineWidth: 1)
                                    )
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("使用当前位置")
                        }
                    }
                }

                Divider().overlay(BSColor.border)

                recommendationContent

                Picker("交通方式", selection: $selectedMode) {
                    ForEach(modeDisplayOrder, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityLabel("交通方式")
            }
        }
    }

    @ViewBuilder
    private var recommendationContent: some View {
        if isSearchingOptions && !hasAnyRecommendation {
            HStack(spacing: BSSpacing.sm) {
                ProgressView().tint(BSColor.textPrimary)
                Text("正在按希望到达时间倒推出门时间…")
                    .font(BSFont.caption)
                    .foregroundColor(BSColor.textTertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else if let option = currentRecommendation {
            recommendationDetail(option)
        } else if !canRecommend {
            Text(trimmedDestination.isEmpty
                ? "这场还没填场馆地址，没法查路线。"
                : "填上出发地，就能生成出门方案。")
                .font(BSFont.caption)
                .foregroundColor(BSColor.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Text("\(selectedMode.displayName)暂时没查到路线。")
                    .font(BSFont.caption)
                    .foregroundColor(BSColor.textTertiary)
                if !hasSavedDeparturePlan {
                    Button("换种方式看看，或手动保存") {
                        prepareManualEntry()
                        showsManualSave = true
                    }
                    .font(BSFont.caption)
                    .foregroundColor(BSColor.Accent.travel)
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func recommendationDetail(_ option: DepartureTransportOption) -> some View {
        VStack(alignment: .leading, spacing: BSSpacing.xs) {
            HStack(spacing: 8) {
                Image(systemName: option.mode.iconName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(BSColor.Accent.travel)
                Text(option.experienceTag)
                    .font(BSFont.tag)
                    .foregroundColor(BSColor.Accent.travel)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(BSColor.Accent.travel.opacity(0.12))
                    .clipShape(Capsule())
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(timeText(option.leaveAt))
                    .font(.system(size: 28, weight: .light))
                    .foregroundColor(BSColor.textPrimary)
                Text("出门")
                    .font(BSFont.caption)
                    .foregroundColor(BSColor.textTertiary)
            }

            Text("约 \(option.durationText) · \(timeText(option.arriveAt)) 到场")
                .font(BSFont.body)
                .foregroundColor(BSColor.textSecondary)

            Text(option.summary)
                .font(BSFont.caption)
                .foregroundColor(BSColor.textTertiary)
                .fixedSize(horizontal: false, vertical: true)

            if isShowStarted {
                Text("这场已经开场，时间仅用于记录。")
                    .font(BSFont.caption)
                    .foregroundColor(BSColor.Accent.music.opacity(0.9))
            }
        }
    }

    @ViewBuilder
    private var actionArea: some View {
        if let plan = plan, hasSavedDeparturePlan {
            VStack(spacing: BSSpacing.sm) {
                savedSummaryCard(plan)
                Button {
                    openSavedMap()
                } label: {
                    Text("打开地图")
                }
                .buttonStyle(BSPrimaryButtonStyle())

                if let option = currentRecommendation, !isSearchingOptions {
                    Button {
                        save(option)
                    } label: {
                        Text("换成这个方案")
                    }
                    .buttonStyle(BSSecondaryButtonStyle())
                }
            }
        } else if let option = currentRecommendation, !isSearchingOptions {
            Button {
                save(option)
            } label: {
                Text("保存出门提醒")
            }
            .buttonStyle(BSPrimaryButtonStyle())
        }
    }

    private func savedSummaryCard(_ plan: RoundTripPlan) -> some View {
        BSGlassPanel {
            HStack(spacing: BSSpacing.sm) {
                Image(systemName: plan.savedDepartureMode?.iconName ?? "location.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(BSColor.Accent.travel)
                    .frame(width: 34, height: 34)
                    .background(BSColor.Accent.travel.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 11))

                VStack(alignment: .leading, spacing: 3) {
                    Text("已保存出门方案")
                        .font(BSFont.headline)
                        .foregroundColor(BSColor.textPrimary)
                    Text(savedDepartureTimeLine(plan))
                        .font(BSFont.caption)
                        .foregroundColor(BSColor.textTertiary)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var destinationReadOnlySection: some View {
        BSGlassPanel {
            VStack(alignment: .leading, spacing: BSSpacing.xs) {
                Text("到场地址")
                    .font(BSFont.headline)
                    .foregroundColor(BSColor.textPrimary)

                if showDestination.quality == .missing {
                    Text("这场还没有场馆地址，没法查路线。")
                        .font(BSFont.caption)
                        .foregroundColor(BSColor.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("去编辑现场补地址") {
                        showsVenueEditor = true
                    }
                    .buttonStyle(BSSecondaryButtonStyle())
                } else {
                    VStack(alignment: .leading, spacing: 3) {
                        if let venueName = showDestination.venueName {
                            Text(venueName)
                                .font(BSFont.body)
                                .foregroundColor(BSColor.textPrimary)
                        }
                        if let city = showDestination.city {
                            Text(city)
                                .font(BSFont.caption)
                                .foregroundColor(BSColor.textTertiary)
                        }
                        if let address = showDestination.address {
                            Text(address)
                                .font(BSFont.caption)
                                .foregroundColor(BSColor.textSecondary)
                        }
                    }
                    if let guidance = showDestination.guidance {
                        Text(guidance)
                            .font(BSFont.caption)
                            .foregroundColor(BSColor.Accent.travel.opacity(0.92))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Button("编辑现场信息") {
                        showsVenueEditor = true
                    }
                    .buttonStyle(BSSecondaryButtonStyle())
                }
            }
        }
    }

    private var advancedSection: some View {
        DisclosureGroup(isExpanded: $showsAdvanced) {
            VStack(alignment: .leading, spacing: BSSpacing.md) {
                VStack(alignment: .leading, spacing: BSSpacing.xs) {
                    DatePicker("希望到达", selection: $targetArrivalAt, displayedComponents: [.date, .hourAndMinute])
                        .font(BSFont.caption)
                        .foregroundColor(BSColor.textSecondary)
                        .datePickerStyle(.compact)
                        .accessibilityLabel("希望到达时间")
                    Text("默认开场前 1 小时到，改了要重新生成才会更新。")
                        .font(BSFont.caption)
                        .foregroundColor(BSColor.textTertiary)
                }

                directionField(label: "集合点", placeholder: "入口、朋友汇合点", text: $meetingPoint)

                Button {
                    Task { await searchRecommendations(force: true) }
                } label: {
                    HStack {
                        if isSearchingOptions {
                            ProgressView().tint(.black)
                        }
                        Text("重新生成方案")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(BSPrimaryButtonStyle())
                .disabled(!canRecommend || isSearchingOptions)
            }
            .padding(.top, BSSpacing.sm)
        } label: {
            Text(showsAdvanced ? "收起更多" : "更多")
                .font(BSFont.caption)
                .foregroundColor(BSColor.textSecondary)
        }
        .tint(BSColor.textSecondary)
    }

    private var manualSavePanel: some View {
        BSGlassPanel {
            VStack(alignment: .leading, spacing: BSSpacing.sm) {
                VStack(alignment: .leading, spacing: BSSpacing.xs) {
                    Text("手动保存一个方案")
                        .font(BSFont.headline)
                        .foregroundColor(BSColor.textPrimary)
                    Text(searchError ?? "查不到路线时，可以自己填出门和到达时间。")
                        .font(BSFont.caption)
                        .foregroundColor(BSColor.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Picker("交通方式", selection: $manualMode) {
                    ForEach(modeDisplayOrder, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                DatePicker("出门时间", selection: $manualLeaveAt, displayedComponents: [.date, .hourAndMinute])
                    .font(BSFont.caption)
                    .foregroundColor(BSColor.textSecondary)
                    .datePickerStyle(.compact)

                DatePicker("预计到达", selection: $manualArriveAt, displayedComponents: [.date, .hourAndMinute])
                    .font(BSFont.caption)
                    .foregroundColor(BSColor.textSecondary)
                    .datePickerStyle(.compact)

                directionField(label: "方案摘要", placeholder: "比如地铁到场，A 口集合", text: $manualSummary)

                Button("保存手动方案") {
                    saveManualDeparture()
                }
                .buttonStyle(BSPrimaryButtonStyle())
            }
        }
    }

    private func directionField(label: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(BSFont.caption)
                .foregroundColor(BSColor.textTertiary)
            TextField(placeholder, text: text)
                .bsInputField()
                .accessibilityLabel(label)
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

        targetArrivalAt = defaultTargetArrivalAt
        manualArriveAt = defaultTargetArrivalAt
        manualLeaveAt = Calendar.current.date(byAdding: .minute, value: -45, to: defaultTargetArrivalAt) ?? defaultTargetArrivalAt
        destination = show.departureDestination.text

        // 出发地优先级：本场已保存 > 常用出发地 > 空
        if let savedPlanOrigin = plan?.departureOrigin, !savedPlanOrigin.isEmpty {
            origin = savedPlanOrigin
        } else if let originText = savedOrigin?.addressText, !originText.isEmpty {
            origin = originText
        }

        if let plan {
            destination = plan.departureDestination ?? show.departureDestination.text
            meetingPoint = plan.departureMeetingPoint ?? ""
            if let arriveAt = plan.departureArriveAt {
                targetArrivalAt = arriveAt
                manualArriveAt = arriveAt
            }
            if let leaveAt = plan.departureLeaveAt {
                manualLeaveAt = leaveAt
            }
            if let mode = plan.savedDepartureMode {
                manualMode = mode
                selectedMode = mode
            }
            manualSummary = plan.departureSummary ?? ""
        }

        if canRecommend {
            Task { await searchRecommendations(force: false) }
        }
    }

    @MainActor
    private func searchRecommendations(force: Bool) async {
        guard canRecommend else {
            searchError = trimmedDestination.isEmpty
                ? "这场还没填场馆地址，去编辑现场补一下。"
                : "请先填写出发地。"
            presentToast(.neutral, message: trimmedDestination.isEmpty ? "请先补场馆地址" : "请先填写出发地")
            return
        }

        isSearchingOptions = true
        defer { isSearchingOptions = false }

        let request = DepartureRouteRequest(
            show: show,
            origin: trimmedOrigin,
            destination: trimmedDestination,
            meetingPoint: meetingPoint,
            targetArrivalAt: targetArrivalAt,
            preferredModes: modeDisplayOrder,
            notes: nil
        )

        do {
            let options = try await routeProvider.searchOptions(for: request)
            var newRecommendations: [DepartureTransportMode: DepartureTransportOption] = [:]
            for option in options {
                newRecommendations[option.mode] = option
            }
            recommendations = newRecommendations
            searchError = nil

            if newRecommendations.isEmpty {
                searchError = "没查到路线。请把到场地址写得更具体，或检查出发地。"
                if !hasSavedDeparturePlan {
                    showsManualSave = true
                    prepareManualEntry()
                    presentToast(.failure, message: "暂时没拿到路线")
                }
            } else {
                showsManualSave = false
                if recommendations[selectedMode] == nil {
                    selectedMode = modeDisplayOrder.first(where: { recommendations[$0] != nil }) ?? selectedMode
                }
                if force {
                    presentToast(.success, message: "已重新生成")
                }
            }
        } catch {
            recommendations = [:]
            searchError = errorMessage(for: error)
            if !hasSavedDeparturePlan {
                showsManualSave = true
                prepareManualEntry()
                if manualSummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    manualSummary = "\(manualMode.displayName)到 \(trimmedDestination)"
                }
                presentToast(.failure, message: "暂时没拿到路线")
            }
        }
    }

    private func errorMessage(for error: Error) -> String {
        if let providerError = error as? DepartureRouteProviderError {
            switch providerError {
            case .providerUnavailable:
                return "地图服务暂时不可用，可以手动保存出门提醒。"
            case .geocodingFailed:
                return "出发地或到场地址没识别到，写得更具体试试，或手动保存。"
            case .noOptions:
                return "没查到路线。请把到场地址写得更具体，或检查出发地。"
            case .missingOrigin, .missingDestination:
                return "出发地和到场地址都要填。"
            }
        }
        return "没查到路线。请把到场地址写得更具体，或检查出发地，也可以先手动保存出门提醒。"
    }

    @MainActor
    private func handleLocate() async {
        do {
            let resolved = try await locator.requestCurrentOrigin()
            origin = resolved.addressText
            if canRecommend {
                await searchRecommendations(force: false)
            }
        } catch {
            let message = (error as? OriginLocator.LocatorError)?.errorDescription
                ?? "暂时拿不到当前位置，可以手动填出发地。"
            presentToast(.neutral, message: message)
        }
    }

    private func prepareManualEntry() {
        manualArriveAt = targetArrivalAt
        if manualLeaveAt >= targetArrivalAt {
            manualLeaveAt = Calendar.current.date(byAdding: .minute, value: -45, to: targetArrivalAt) ?? targetArrivalAt
        }
        if recommendations[manualMode] == nil {
            manualMode = modeDisplayOrder.first(where: { recommendations[$0] != nil }) ?? selectedMode
        }
    }

    private func save(_ option: DepartureTransportOption) {
        mutablePlan().saveDeparture(
            option: option,
            origin: trimmedOrigin,
            destination: trimmedDestination,
            meetingPoint: meetingPoint
        )
        do {
            try modelContext.save()
            upsertSavedOrigin(addressText: trimmedOrigin)
            searchError = nil
            presentToast(.success, message: "出门方案已保存")
        } catch {
            presentToast(.failure, message: "保存失败")
        }
    }

    private func saveManualDeparture() {
        guard !trimmedOrigin.isEmpty else {
            presentToast(.neutral, message: "请先填写出发地")
            return
        }
        guard !trimmedDestination.isEmpty else {
            presentToast(.neutral, message: "请补充到场地址")
            return
        }

        let summary = manualSummary.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalSummary = summary.isEmpty ? "\(manualMode.displayName)到 \(trimmedDestination)" : summary
        mutablePlan().saveManualDeparture(
            origin: trimmedOrigin,
            destination: trimmedDestination,
            leaveAt: manualLeaveAt,
            arriveAt: manualArriveAt,
            mode: manualMode,
            summary: finalSummary,
            meetingPoint: meetingPoint
        )
        do {
            try modelContext.save()
            upsertSavedOrigin(addressText: trimmedOrigin)
            searchError = nil
            showsManualSave = false
            presentToast(.success, message: "出门方案已保存")
        } catch {
            presentToast(.failure, message: "保存失败")
        }
    }

    private func upsertSavedOrigin(addressText: String) {
        let trimmed = addressText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if let savedOrigin, savedOrigin.addressText != trimmed {
            savedOrigin.addressText = trimmed
            savedOrigin.name = trimmed
            savedOrigin.updatedAt = Date()
        } else if savedOrigin == nil {
            modelContext.insert(SavedOrigin(name: trimmed, addressText: trimmed))
        }
        try? modelContext.save()
    }

    @MainActor
    private func openSavedMap() {
        if let plan = plan, let option = savedOption(from: plan), let url = option.navigationURL {
            UIApplication.shared.open(url)
            return
        }
        if let plan = plan,
           let url = Self.appleMapsDirectionsURL(origin: plan.departureOrigin, destination: plan.departureDestination) {
            UIApplication.shared.open(url)
            return
        }
        presentToast(.neutral, message: "暂无地图链接，请手动打开地图")
    }

    private func savedOption(from plan: RoundTripPlan) -> DepartureTransportOption? {
        guard let mode = plan.savedDepartureMode,
              let leaveAt = plan.departureLeaveAt,
              let arriveAt = plan.departureArriveAt,
              let duration = plan.departureDurationMinutes,
              let summary = plan.departureSummary,
              let provider = plan.savedDepartureProvider else {
            return nil
        }
        return DepartureTransportOption(
            id: plan.id.uuidString,
            mode: mode,
            leaveAt: leaveAt,
            arriveAt: arriveAt,
            durationMinutes: duration,
            distanceMeters: plan.departureDistanceMeters,
            summary: summary,
            experienceTag: plan.departureExperienceTag ?? "已保存",
            provider: provider,
            navigationURL: plan.savedDepartureNavigationURL,
            capturedAt: plan.departureCapturedAt ?? plan.updatedAt
        )
    }

    private func savedDepartureTimeLine(_ plan: RoundTripPlan) -> String {
        guard let mode = plan.savedDepartureMode,
              let leaveAt = plan.departureLeaveAt,
              let arriveAt = plan.departureArriveAt,
              let duration = plan.departureDurationMinutes else {
            return "出发前打开地图确认实时路线"
        }
        return "\(timeText(leaveAt)) 出门 · \(mode.displayName)约 \(duration) 分钟 · \(timeText(arriveAt)) 到"
    }

    private func timeText(_ date: Date) -> String {
        let calendar = Calendar.current
        let showDay = calendar.startOfDay(for: effectiveStartDate)
        let day = calendar.startOfDay(for: date)
        if day == showDay {
            return Self.timeFormatter.string(from: date)
        }
        let clock = Self.timeFormatter.string(from: date)
        let dayDiff = calendar.dateComponents([.day], from: showDay, to: day).day ?? 0
        if dayDiff == 1 {
            return "次日 \(clock)"
        }
        if dayDiff > 1 {
            return "\(calendar.component(.month, from: date))/\(calendar.component(.day, from: date)) \(clock)"
        }
        return "前日 \(clock)"
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    nonisolated static func appleMapsDirectionsURL(origin: String?, destination: String?) -> URL? {
        guard let destination,
              !destination.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        var components = URLComponents(string: "https://maps.apple.com/")
        var items: [URLQueryItem] = [URLQueryItem(name: "daddr", value: destination)]
        if let origin, !origin.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            items.insert(URLQueryItem(name: "saddr", value: origin), at: 0)
        }
        components?.queryItems = items
        return components?.url
    }

    private func applyShowDraft(_ draft: ShowDraft) {
        show.name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        show.date = draft.date
        show.startTime = draft.startTime
        show.endDate = draft.endDate
        show.endTime = draft.endTime
        show.city = trimmedOptional(draft.city)
        show.venueName = trimmedOptional(draft.venueName)
        show.venueAddress = trimmedOptional(draft.venueAddress)
        show.artist = trimmedOptional(draft.artist)
        show.seatSection = trimmedOptional(draft.seatSection)
        show.coverImageURL = trimmedOptional(draft.coverImageURL)
        show.artistAvatarURLs = draft.artistAvatarURLs
        show.type = draft.type
        try? modelContext.save()
    }

    private func trimmedOptional(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
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
    @State private var toast: BSToastPayload?

    private let guide = ShowPreparationGuide()

    private var plan: ShowPreparationPlan? {
        plans.first { $0.showID == show.id }
    }

    private var allSuggestions: [ShowPreparationSuggestion] {
        guide.sections(for: show).flatMap(\.suggestions)
    }

    private var checkedSuggestionCount: Int {
        guard let plan else { return 0 }
        return allSuggestions.filter { plan.isChecked($0.text) }.count
    }

    private var totalSuggestionCount: Int {
        allSuggestions.count
    }

    private var isPreparedEnough: Bool {
        totalSuggestionCount > 0 && checkedSuggestionCount == totalSuggestionCount
    }

    var body: some View {
        BSStageScaffold(title: "现场准备", subtitle: show.name) {
            BSTipPromptCard(
                iconName: isPreparedEnough ? "checkmark.seal.fill" : "sparkles",
                eyebrow: "Tips · 出门前",
                message: isPreparedEnough
                    ? "好，差不多准备好了。到点前再看一眼，就可以轻一点出门。"
                    : "不用像待办一样紧张，先轻轻确认几件会让你更从容的小事。",
                accent: BSColor.Accent.prepare
            )

            VStack(alignment: .leading, spacing: BSSpacing.md) {
                HStack {
                    BSSectionHeader(title: "出门前确认")
                    Spacer()
                    Text("\(checkedSuggestionCount)/\(totalSuggestionCount)")
                        .font(BSFont.caption)
                        .foregroundColor(isPreparedEnough ? BSColor.Accent.prepare : BSColor.textTertiary)
                }

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
                            Text("出门前轻轻提醒一下")
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
                        presentToast(.success, message: "提醒已保存")
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
                    presentToast(.success, message: "备注已保存")
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
        .bsToastOverlay(toast)
    }

    private func preparationSuggestionRow(_ suggestion: ShowPreparationSuggestion) -> some View {
        let checked = mutablePlan().isChecked(suggestion.text)
        return Button {
            mutablePlan().setChecked(!checked, suggestionText: suggestion.text)
            try? modelContext.save()
            if checked {
                presentToast(.neutral, message: "已取消确认")
            } else {
                presentToast(.success, message: "已确认")
            }
        } label: {
            HStack(alignment: .top, spacing: BSSpacing.sm) {
                Image(systemName: checked ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(checked ? BSColor.Accent.prepare : BSColor.textTertiary)
                    .frame(width: 28, height: 28)
                Text(suggestion.text)
                    .font(BSFont.body)
                    .foregroundColor(checked ? BSColor.textSecondary : BSColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Text(checked ? "已确认" : "轻点确认")
                    .font(BSFont.caption)
                    .foregroundColor(checked ? BSColor.Accent.prepare : BSColor.textTertiary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background((checked ? BSColor.Accent.prepare : Color.white).opacity(0.10))
                    .clipShape(Capsule())
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
        .accessibilityLabel("\(suggestion.text)，\(checked ? "已确认" : "未确认")")
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

struct ShowFragmentListView: View {
    private enum ComposerMode {
        case text
        case media
        case audio
    }

    @Environment(\.modelContext) private var modelContext
    @Query private var fragments: [ShowFragment]

    let show: Show
    @State private var text = ""
    @State private var selectedMediaItems: [PhotosPickerItem] = []
    @State private var pendingGalleryReferences: [(localIdentifier: String, kind: ShowFragmentGalleryMediaKind)] = []
    @State private var pendingMediaPreviews: [PendingFragmentMediaPreview] = []
    @StateObject private var audioRecorder = FragmentAudioRecorder()
    @State private var pendingAudioRelativePath: String?
    @State private var pendingAudioDuration: TimeInterval?
    @State private var pendingAudioURL: URL?
    @State private var isShowingAudioDrawer = false
    @State private var composerExpanded = false
    @State private var composerMode: ComposerMode?
    @State private var message: String?
    @State private var editingFragment: ShowFragment?
    @State private var deletingFragment: ShowFragment?
    @State private var pendingDelete: ShowFragment?
    @State private var toast: BSToastPayload?

    private var isRecordingAudio: Bool { audioRecorder.isRecording }

    private var showFragments: [ShowFragment] {
        fragments
    }

    init(show: Show) {
        self.show = show
        let id = show.id
        _fragments = Query(
            filter: #Predicate<ShowFragment> { $0.show.id == id },
            sort: \ShowFragment.createdAt, order: .reverse
        )
    }

    var body: some View {
        BSStageScaffold(title: "现场碎片", subtitle: show.name, bottomPadding: 96) {
            composer
                .onChange(of: selectedMediaItems) { _, newItems in
                    if !newItems.isEmpty {
                        composerExpanded = true
                        composerMode = .media
                    }
                    Task {
                        await updatePendingMedia(from: newItems)
                    }
                }

            VStack(alignment: .leading, spacing: BSSpacing.sm) {
                BSSectionHeader(title: "留下来的瞬间")
                if showFragments.isEmpty {
                    BSEmptyPanel(
                        iconName: "sparkles.rectangle.stack",
                        title: "还没有留下这一场",
                        message: "可以只写一句、存一张照片，或录一小段声音。"
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
        .sheet(item: $deletingFragment, onDismiss: {
            // 等 sheet 完全 dismiss 后再执行删除，避免动画期间修改 ModelContext 导致崩溃。
            if let fragment = pendingDelete {
                pendingDelete = nil
                delete(fragment)
            }
        }) { fragment in
            BSDangerConfirmationSheet(
                title: "删除现场碎片？",
                message: "这条文字、相册引用和本地语音文件都会从 BeforeShow 中移除。",
                destructiveTitle: "删除",
                onConfirm: {
                    pendingDelete = fragment
                    deletingFragment = nil
                },
                onCancel: {
                    deletingFragment = nil
                }
            )
        }
        .sheet(isPresented: $isShowingAudioDrawer, onDismiss: {
            // 用户在录音中直接下滑关闭抽屉时，停止并丢弃未保存的录音文件。
            if audioRecorder.isRecording {
                audioRecorder.stop()
                audioRecorder.discard()
                pendingAudioURL = nil
                pendingAudioRelativePath = nil
                pendingAudioDuration = nil
            }
        }) {
            FragmentAudioCaptureSheet(
                audioRecorder: audioRecorder.avAudioRecorder,
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
                    VStack(alignment: .leading, spacing: BSSpacing.xs) {
                        Text("留下一点这一刻")
                            .font(BSFont.headline)
                            .foregroundColor(BSColor.textPrimary)
                        Text("不用整理好，先留下就好。")
                            .font(BSFont.caption)
                            .foregroundColor(BSColor.textTertiary)
                    }
                    Spacer()
                    Button {
                        withAnimation(.easeInOut(duration: 0.22)) {
                            composerExpanded.toggle()
                            if composerExpanded && composerMode == nil {
                                composerMode = .text
                            }
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

                HStack(spacing: BSSpacing.sm) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.22)) {
                            composerExpanded = true
                            composerMode = .text
                        }
                    } label: {
                        Label("写一句", systemImage: "text.bubble")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(BSSecondaryButtonStyle())

                    PhotosPicker(
                        selection: $selectedMediaItems,
                        maxSelectionCount: 12,
                        matching: .any(of: [.images, .videos])
                    ) {
                        Label("照片", systemImage: "photo.stack")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(BSSecondaryButtonStyle())

                    Button {
                        composerExpanded = true
                        composerMode = .audio
                        isShowingAudioDrawer = true
                    } label: {
                        Label("语音", systemImage: "mic.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(BSSecondaryButtonStyle())
                }

                if composerExpanded {
                    if composerMode == .text || !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        TextField("写下一点这一场里的瞬间", text: $text, axis: .vertical)
                            .lineLimit(3...6)
                            .bsInputField()
                            .accessibilityLabel("现场碎片文字")
                    }

                    if !pendingMediaPreviews.isEmpty {
                        PendingMediaPreviewStrip(previews: pendingMediaPreviews)
                    }

                    if composerMode == .audio && pendingAudioURL == nil && !isRecordingAudio {
                        Button {
                            isShowingAudioDrawer = true
                        } label: {
                            Label("开始录一段声音", systemImage: "mic.circle.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(BSPrimaryButtonStyle())
                    } else if isRecordingAudio {
                        FragmentAudioPlaybackRow(
                            title: "正在录音",
                            subtitle: "录完后可以试听",
                            audioURL: nil,
                            duration: audioRecorder.avAudioRecorder?.currentTime,
                            isRecording: true,
                            audioRecorder: audioRecorder.avAudioRecorder
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
            // 文件已由碎片引用，转移所有权但不删除。
            audioRecorder.detach()
            composerExpanded = false
            composerMode = nil
            message = "这一刻留下来了。"
            presentToast(.success, message: "碎片已保存")
        } catch {
            message = "请先写一点内容，或添加照片、视频、语音片段。"
            presentToast(.failure, message: "保存失败")
        }
    }

    private func delete(_ fragment: ShowFragment) {
        do {
            try LocalAppDataDeletionService(audioStorage: .applicationSupport())
                .deleteFragment(fragment, in: modelContext)
            try modelContext.save()
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

    private func startAudioRecording() {
        do {
            try audioRecorder.start()
            pendingAudioRelativePath = audioRecorder.currentRelativePath
            pendingAudioURL = audioRecorder.currentURL
            pendingAudioDuration = nil
            message = "正在录音。"
        } catch {
            message = "无法开始录音，请检查麦克风权限。"
        }
    }

    private func stopAudioRecording() {
        if let snapshot = audioRecorder.stop() {
            pendingAudioURL = snapshot.url
            pendingAudioRelativePath = snapshot.relativePath
            pendingAudioDuration = snapshot.duration
        }
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
        BSDrawerSheet(detent: .height(312)) {
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
        BSDrawerSheet(detent: .height(360)) {
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

    @StateObject private var player = FragmentAudioPlayerController()
    @State private var waveformSamples: [Double] = []

    var body: some View {
        HStack(spacing: BSSpacing.sm) {
            Button {
                player.toggle(url: audioURL)
            } label: {
                Image(systemName: isRecording ? "waveform" : (player.isPlaying ? "pause.fill" : "play.fill"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(BSColor.textPrimary)
                    .frame(width: 32, height: 32)
                    .background(Color.white.opacity(0.09))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(audioURL == nil || isRecording)
            .accessibilityLabel(player.isPlaying ? "暂停语音片段" : "试听语音片段")

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
                AudioWaveformView(samples: waveformSamples, isActive: player.isPlaying)
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
