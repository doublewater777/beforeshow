import SwiftData
import SwiftUI

#if canImport(MusicKit)
@preconcurrency import MusicKit
#endif

public struct ArtistWarmupRootView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Query(sort: \Show.date) private var shows: [Show]
    @Query private var selections: [CurrentShowSelection]
    @Query(sort: \ShowArtist.originalOrder) private var showArtists: [ShowArtist]
    @Query private var catalogSnapshots: [ArtistCatalogSnapshot]
    @Query private var catalogSongs: [CatalogSong]
    @Query private var familiarityRecords: [SongFamiliarityRecord]
    @Query private var impressions: [ShowSongImpression]
    @Query private var recallRecords: [ShowSetlistMemory]

    @State private var localPresentation: ArtistWarmupPresentationState?
    @State private var isSearchPresented = false
    @State private var isPermissionPresented = false
    @State private var isImpressionPresented = false
    @State private var isArtistConfirmed = false
    @State private var impressionWantsLive = false
    @State private var impressionHasFeeling = true
    @State private var impressionNote = ""
    @State private var selectedSongID: String?
    @State private var recallManualTitle = ""
    @State private var searchQuery = ""
    @State private var searchResults: [ArtistWarmupArtistCandidate] = []
    @State private var isSearchLoading = false
    @State private var warmupErrorMessage: String?
    @State private var authorizationStatus: ArtistWarmupAuthorizationStatus = .notDetermined
    @State private var subscriptionCapability: ArtistWarmupSubscriptionCapability?
    @State private var playbackStatus: MusicPlayer.PlaybackStatus = .stopped
    @State private var playbackTime: TimeInterval = 0
    @State private var coordinator: ArtistWarmupCoordinator?

    private let onDetailVisibilityChange: (Bool) -> Void
    private let musicService: ArtistWarmupCatalogProviding & ArtistWarmupMusicCapabilityProviding & ArtistWarmupPlaying

    public init(onDetailVisibilityChange: @escaping (Bool) -> Void) {
        self.onDetailVisibilityChange = onDetailVisibilityChange
        #if canImport(MusicKit)
        self.musicService = MusicKitArtistWarmupService()
        #else
        self.musicService = UnavailableArtistWarmupService()
        #endif
    }

    public var body: some View {
        let presentation = currentPresentation

        Group {
            switch presentation.screen {
            case .noCurrentShow:
                emptyState(presentation)
            case .unavailable:
                unavailableState(presentation)
            case .candidateConnection:
                candidateState(presentation)
            case .authorizationDenied:
                capabilityState(
                    presentation,
                    icon: "lock.slash",
                    title: "Apple Music 无权限",
                    message: "艺人身份已确认，但音乐访问尚未开启。你可以稍后在系统设置中允许访问。"
                )
            case .noSubscription:
                capabilityState(
                    presentation,
                    icon: "music.note.list",
                    title: "没有 Apple Music 订阅",
                    message: "仍可浏览曲库、写印象和手动补记听过；完整播放需要可播放的 Apple Music 内容。"
                )
            case .home:
                home(presentation)
            case .catalogLoading:
                catalog(presentation, isLoading: true)
            case .catalog:
                catalog(presentation, isLoading: false)
            case .player:
                player(presentation)
            case .postShowRecall:
                recall(presentation)
            }
        }
        .preferredColorScheme(.dark)
        .bsToastOverlay(
            warmupErrorMessage.map { BSToastPayload(tone: .failure, message: $0) },
            bottomPadding: 90
        )
        .onAppear {
            ensureFixtureLoaded()
            onDetailVisibilityChange(presentation.screen.hidesFloatingTab)
        }
        .task {
            guard ArtistWarmupDebugFixture.requestedState == nil else { return }
            configureCoordinator()
            await refreshMusicCapability()
            try? coordinator?.captureEligibleOpeningSnapshots()
        }
        .task(id: currentShowID) {
            guard ArtistWarmupDebugFixture.requestedState == nil else { return }
            await refreshCatalogsForConnectedArtists()
        }
        .task(id: playbackSampleToken) {
            guard ArtistWarmupDebugFixture.requestedState == nil else { return }
            await observePlaybackEvidence()
        }
        .task {
            guard ArtistWarmupDebugFixture.requestedState == nil else { return }
            await pollPlaybackSnapshot()
        }
        .onChange(of: presentation.screen) { _, screen in
            onDetailVisibilityChange(screen.hidesFloatingTab)
        }
        .sheet(isPresented: $isSearchPresented) {
            artistSearchSheet(presentation)
        }
        .sheet(isPresented: $isPermissionPresented) {
            permissionSheet(presentation)
        }
        .sheet(isPresented: $isImpressionPresented) {
            impressionSheet(presentation)
        }
    }

    private var currentPresentation: ArtistWarmupPresentationState {
        if let localPresentation {
            return localPresentation
        }

        if let fixtureState = ArtistWarmupDebugFixture.requestedState {
            return ArtistWarmupDebugFixture.make(fixtureState).presentation
        }

        return ArtistWarmupLivePresentationBuilder.make(
            shows: shows,
            selections: selections,
            showArtists: showArtists,
            catalogSnapshots: catalogSnapshots,
            catalogSongs: catalogSongs,
            familiarityRecords: familiarityRecords,
            impressions: impressions,
            recallRecords: recallRecords
            ,
            authorizationStatus: authorizationStatus,
            subscriptionCapability: subscriptionCapability
        )
    }

    private func configureCoordinator() {
        if coordinator == nil {
            coordinator = ArtistWarmupCoordinator(service: musicService, context: modelContext)
        }
    }

    private func refreshMusicCapability() async {
        authorizationStatus = await musicService.authorizationStatus()
        subscriptionCapability = try? await musicService.subscriptionCapability()
    }

    private func requestMusicAuthorization() async {
        authorizationStatus = await musicService.requestAuthorization()
        subscriptionCapability = try? await musicService.subscriptionCapability()
    }

    private func refreshCatalogsForConnectedArtists() async {
        guard let coordinator else { return }
        let artistIDs = showArtists
            .filter { $0.showID == currentShowID && $0.isConnectedToAppleMusic }
            .compactMap(\.appleMusicArtistID)

        for artistID in artistIDs {
            _ = try? await coordinator.refreshCatalog(artistID: artistID)
        }
    }

    private var playbackSampleToken: String {
        "\(currentShowID?.uuidString ?? "-")|\(playbackStatus)|\(playbackTime)"
    }

    private func pollPlaybackSnapshot() async {
        while !Task.isCancelled {
            let snapshot = musicService.playbackSnapshot()
            playbackTime = snapshot.currentTime
            playbackStatus = snapshot.isPlaying ? .playing : .paused
            if let songID = snapshot.songID {
                mutatePresentation { presentation in
                    presentation.nowPlayingSongID = songID
                }
            }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
    }

    private func observePlaybackEvidence() async {
        guard let coordinator,
              let snapshot = Optional(musicService.playbackSnapshot()),
              let songID = snapshot.songID,
              snapshot.isPlaying else {
            return
        }

        _ = try? coordinator.ingestPlaybackSample(coordinator.playbackSample(
            songID: songID,
            currentTime: snapshot.currentTime,
            duration: snapshot.duration ?? catalogSongs.first { $0.appleMusicSongID == songID }?.duration,
            isPlaying: snapshot.isPlaying,
            isPreview: subscriptionCapability?.canPlayCatalogContent != true
        ))
    }

    private func startWarmup(
        _ presentation: ArtistWarmupPresentationState,
        scope: ArtistWarmupQueueScope
    ) async {
        guard ArtistWarmupDebugFixture.requestedState == nil,
              let showID = currentShowID,
              let coordinator else {
            route(to: .player)
            return
        }

        do {
            let queue = try coordinator.warmupQueue(showID: showID, scope: scope)
            try await musicService.enqueue(queue, scopedTo: .allSongs)
            try await musicService.play()
            warmupErrorMessage = nil
            route(to: .player)
        } catch {
            warmupErrorMessage = queueErrorMessage(for: error)
        }
    }

    private func queueErrorMessage(for error: Error) -> String {
        if let warmupError = error as? ArtistWarmupMusicServiceError,
           case .emptyQueue = warmupError {
            return "想看和待定的艺人都没有可预热的歌曲。"
        }
        return "暂时无法开始预热，请稍后再试。"
    }

    private func familiaritySummary(for artist: ArtistWarmupPresentedArtist) -> String {
        if artist.familiarity.hasCompleteCatalog {
            return "\(artist.familiarity.tierLabel) · \(artist.familiarity.heardSongCount)/\(artist.familiarity.catalogSongCount) 首"
        }
        return "正在整理曲库"
    }

    private func ensureFixtureLoaded() {
        guard localPresentation == nil,
              let fixtureState = ArtistWarmupDebugFixture.requestedState else {
            return
        }
        localPresentation = ArtistWarmupDebugFixture.make(fixtureState).presentation
    }

    private func emptyState(_ presentation: ArtistWarmupPresentationState) -> some View {
        BSStageScaffold(title: "预热", subtitle: nil, bottomPadding: BSLayout.tabBarContentInset) {
            WarmupMessagePanel(
                icon: "music.note",
                title: presentation.showTitle,
                message: presentation.showSubtitle ?? "添加当前现场后再开始。",
                tint: BSColor.Stage.accent
            )
        }
    }

    private func unavailableState(_ presentation: ArtistWarmupPresentationState) -> some View {
        BSStageScaffold(title: "预热", subtitle: presentation.showTitle, bottomPadding: BSLayout.tabBarContentInset) {
            WarmupMessagePanel(
                icon: "calendar.badge.exclamationmark",
                title: "预热已停止",
                message: presentation.showSubtitle ?? "这场现场当前不可预热。",
                tint: BSColor.Stage.danger
            )

            artistStack(presentation.artists, showsIntentControls: false)
        }
    }

    private func candidateState(_ presentation: ArtistWarmupPresentationState) -> some View {
        BSStageScaffold(title: "预热", subtitle: presentation.showTitle, bottomPadding: BSLayout.tabBarContentInset) {
            eventContext(presentation)

            if let artist = presentation.artists.first {
                BSGlassPanel(padding: BSSpacing.roomy) {
                    VStack(alignment: .leading, spacing: BSSpacing.md) {
                        Text("APPLE MUSIC 艺人候选")
                            .font(BSFont.tag)
                            .foregroundColor(BSColor.Stage.accent)

                        HStack(alignment: .center, spacing: BSSpacing.md) {
                            WarmupArtistAvatar(name: artist.resolvedName, artworkURL: artist.artworkURL, size: 72)

                            VStack(alignment: .leading, spacing: BSSpacing.xs) {
                                Text(artist.resolvedName)
                                    .font(BSFont.V3.title2)
                                    .foregroundColor(BSColor.Stage.foreground)
                                    .lineLimit(2)

                                Text(isArtistConfirmed ? "艺人身份已确认" : "请确认这是要看的艺人")
                                    .font(BSFont.body)
                                    .foregroundColor(BSColor.Stage.muted)
                            }

                            Spacer(minLength: 0)
                        }

                        WarmupPrimaryButton(
                            title: isArtistConfirmed ? "连接 Apple Music" : "确认是这位",
                            icon: isArtistConfirmed ? "music.note" : "checkmark"
                        ) {
                            if isArtistConfirmed {
                                isPermissionPresented = true
                            } else {
                                isArtistConfirmed = true
                            }
                        }

                        HStack(spacing: BSSpacing.sm) {
                            WarmupSecondaryButton(title: "搜索更换", icon: "magnifyingglass") {
                                isSearchPresented = true
                            }
                            WarmupSecondaryButton(title: "暂不连接", icon: "xmark") {
                                deferConnecting()
                            }
                        }
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Apple Music 艺人候选，\(artist.resolvedName)")
            }
        }
    }

    private func capabilityState(
        _ presentation: ArtistWarmupPresentationState,
        icon: String,
        title: String,
        message: String
    ) -> some View {
        BSStageScaffold(title: "预热", subtitle: presentation.showTitle, bottomPadding: BSLayout.tabBarContentInset) {
            eventContext(presentation)
            WarmupMessagePanel(
                icon: icon,
                title: title,
                message: message,
                tint: BSColor.Stage.accent
            )
            artistStack(presentation.artists, showsIntentControls: false)
            catalogTeaser(presentation)
        }
    }

    private func home(_ presentation: ArtistWarmupPresentationState) -> some View {
        BSStageScaffold(title: "预热", subtitle: presentation.showTitle, bottomPadding: BSLayout.tabBarContentInset) {
            if presentation.artists.count <= 1, let artist = presentation.artists.first {
                compactEventContext(presentation)
                artistHero(artist, presentation: presentation)
            } else {
                eventContext(presentation)
                artistStack(presentation.artists, showsIntentControls: true)
                Text(presentation.hasEmptyWarmupQueue
                     ? "想看和待定都空了，预热不会偷偷换成别的艺人。"
                     : "想看优先，待定会穿插；不看不会进入预热队列。")
                    .font(BSFont.body)
                    .foregroundColor(BSColor.Stage.muted)
                    .accessibilityLabel(presentation.hasEmptyWarmupQueue
                                        ? "想看和待定都空了，预热不会偷偷换成别的艺人"
                                        : "想看优先，待定会穿插，不看不会进入预热队列")
            }

            if presentation.hasEmptyWarmupQueue {
                WarmupMessagePanel(
                    icon: "eye.slash",
                    title: "没有可预热的艺人",
                    message: "全部设为不看时，不会回退到任意艺人。改回想看或待定后再继续。",
                    tint: BSColor.Stage.accent
                )
            } else {
                WarmupPrimaryButton(title: "继续预热", icon: "play.fill") {
                    Task { await startWarmup(presentation, scope: .allArtists) }
                }
            }

            HStack(spacing: BSSpacing.sm) {
                WarmupSecondaryButton(title: "完整曲库", icon: "rectangle.stack") {
                    route(to: .catalog)
                }
                WarmupSecondaryButton(title: "补记听过", icon: "checkmark.circle") {
                    route(to: .catalog)
                }
            }
        }
    }

    private func catalog(_ presentation: ArtistWarmupPresentationState, isLoading: Bool) -> some View {
        BSStageScaffold(title: "曲库", subtitle: presentation.showTitle, bottomPadding: BSSpacing.xl) {
            HStack(spacing: BSSpacing.sm) {
                WarmupIconButton(icon: "chevron.left", label: "返回预热首页") {
                    route(to: .home)
                }
                Spacer()
                WarmupSecondaryButton(title: "随机探索", icon: "shuffle") {
                    route(to: .player)
                }
                .frame(maxWidth: 150)
            }

            if let artist = presentation.artists.first {
                familiarityCard(artist)
            }

            if isLoading {
                BSGlassPanel {
                    HStack(spacing: BSSpacing.md) {
                        ProgressView()
                            .tint(BSColor.Stage.accent)
                        Text("正在整理 Apple Music 音频曲库")
                            .font(BSFont.body)
                            .foregroundColor(BSColor.Stage.foreground)
                    }
                    .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
                }
            } else {
                ForEach(CatalogSongPresentationGroup.allCases, id: \.self) { group in
                    let songs = presentation.songs.filter { $0.category == group.catalogCategory }
                    if !songs.isEmpty {
                        section(group.rawValue) {
                            if group == .albums {
                                ForEach(albumGroups(from: songs), id: \.title) { album in
                                    albumMarkHeardButton(album)
                                    ForEach(album.songs) { song in
                                        catalogSongRow(song)
                                    }
                                }
                            } else {
                                ForEach(songs) { song in
                                    catalogSongRow(song)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func player(_ presentation: ArtistWarmupPresentationState) -> some View {
        let song = presentation.songs.first(where: { $0.id == presentation.nowPlayingSongID })
            ?? presentation.songs.first

        return ZStack {
            CurrentShowStageBackground()
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: BSSpacing.lg) {
                    HStack(spacing: BSSpacing.sm) {
                        WarmupIconButton(icon: "chevron.left", label: "返回预热首页") {
                            route(to: .home)
                        }
                        VStack(alignment: .leading, spacing: BSSpacing.xs) {
                            Text(presentation.showTitle)
                                .font(BSFont.headline)
                                .foregroundColor(BSColor.Stage.foreground)
                                .lineLimit(1)
                            Text(presentation.artists.count > 1 ? "多艺人预热" : (presentation.artists.first?.resolvedName ?? "预热队列"))
                                .font(BSFont.caption)
                                .foregroundColor(BSColor.Stage.muted)
                                .lineLimit(1)
                        }
                        Spacer()
                    }

                    WarmupArtwork(name: song?.artistName ?? "BeforeShow", size: 286)
                        .accessibilityLabel("当前歌曲封面")

                    if let song {
                        VStack(spacing: BSSpacing.sm) {
                            Text(song.title)
                                .font(BSFont.V3.title1)
                                .foregroundColor(BSColor.Stage.foreground)
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                                .minimumScaleFactor(0.85)

                            Text("\(song.artistName) · \(song.albumTitle ?? "Apple Music")")
                                .font(BSFont.body)
                                .foregroundColor(BSColor.Stage.muted)
                                .multilineTextAlignment(.center)
                        }
                        .accessibilityElement(children: .combine)

                        playerProgress(song: song)

                        HStack(spacing: BSSpacing.lg) {
                            WarmupIconButton(icon: "backward.fill", label: "上一首") {
                                Task { try? await musicService.skipToPreviousSong() }
                            }
                            Button {
                                Task {
                                    do {
                                        if playbackStatus == .playing {
                                            await musicService.pause()
                                        } else {
                                            try await musicService.play()
                                        }
                                        warmupErrorMessage = nil
                                    } catch {
                                        warmupErrorMessage = "暂时无法播放，请稍后再试。"
                                    }
                                }
                            } label: {
                                Image(systemName: playbackStatus == .playing ? "pause.fill" : "play.fill")
                                    .font(.system(size: 28, weight: .bold))
                                    .foregroundColor(.black)
                                    .frame(width: 72, height: 72)
                                    .background(BSColor.Stage.accent)
                                    .clipShape(Circle())
                            }
                            .accessibilityLabel("播放")
                            WarmupIconButton(icon: "forward.fill", label: "下一首") {
                                Task { try? await musicService.skipToNextSong() }
                            }
                        }

                        HStack(spacing: BSSpacing.sm) {
                            WarmupSecondaryButton(
                                title: song.wantsLive ? "已想现场听" : "想现场听",
                                icon: song.wantsLive ? "heart.fill" : "heart"
                            ) {
                                updateSong(song.id) { $0.wantsLive.toggle() }
                            }
                            WarmupSecondaryButton(title: song.hasImpression ? "已留印象" : "有感觉", icon: "sparkles") {
                                openImpression(song)
                            }
                            WarmupSecondaryButton(title: "先跳过", icon: "forward.end") {
                                Task { try? await musicService.skipToNextSong() }
                            }
                        }
                    }

                    queuePreview(presentation)
                }
                .padding(.horizontal, BSSpacing.md)
                .padding(.top, BSSpacing.lg)
                .padding(.bottom, BSSpacing.xl)
            }
        }
    }

    private func recall(_ presentation: ArtistWarmupPresentationState) -> some View {
        BSStageScaffold(title: "散场回记", subtitle: presentation.showTitle, bottomPadding: BSLayout.tabBarContentInset) {
            VStack(alignment: .leading, spacing: BSSpacing.sm) {
                Text("现场歌单回记")
                    .font(BSFont.V3.title1)
                    .foregroundColor(BSColor.Stage.foreground)
                Text("记下真正留在耳边的歌；开场前熟悉度会按艺人保留。")
                    .font(BSFont.body)
                    .foregroundColor(BSColor.Stage.muted)
            }

            section("开场前熟悉度") {
                artistStack(presentation.artists, showsIntentControls: false)
            }

            section("演前想现场听") {
                ForEach(presentation.songs.filter(\.wantsLive)) { song in
                    recallSongRow(song, isMarked: presentation.recallSongIDs.contains(song.id))
                }
            }

            section("补充现场唱到的歌") {
                HStack(spacing: BSSpacing.sm) {
                    TextField("歌曲名", text: $recallManualTitle)
                        .textFieldStyle(.plain)
                        .modifier(BSInputFieldStyle())
                        .accessibilityLabel("补充现场唱到的歌")

                    WarmupIconButton(icon: "plus", label: "加入现场回记") {
                        addManualRecall()
                    }
                }
            }

            WarmupPrimaryButton(title: "保存这次回记", icon: "checkmark") {
                saveRecall(presentation)
            }
            WarmupSecondaryButton(title: "继续散场后听歌", icon: "play.fill") {
                route(to: .player)
            }
        }
    }

    private func artistHero(
        _ artist: ArtistWarmupPresentedArtist,
        presentation: ArtistWarmupPresentationState
    ) -> some View {
        VStack(spacing: BSSpacing.md) {
            ZStack(alignment: .bottomLeading) {
                Group {
                    if let artworkURL = artist.artworkURL, let url = URL(string: artworkURL) {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .scaledToFill()
                            default:
                                WarmupArtwork(name: artist.resolvedName, size: 320)
                            }
                        }
                    } else {
                        WarmupArtwork(name: artist.resolvedName, size: 320)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 265)
                .clipped()
                LinearGradient(
                    colors: [.clear, Color.black.opacity(0.18), Color.black.opacity(0.82)],
                    startPoint: .center,
                    endPoint: .bottom
                )
                .clipShape(RoundedRectangle(cornerRadius: BSRadius.sheet))

                VStack(alignment: .leading, spacing: BSSpacing.xs) {
                    Text("APPLE MUSIC")
                        .font(BSFont.tag)
                        .foregroundColor(Color.white.opacity(0.62))
                    Text(artist.resolvedName)
                        .font(BSFont.V3.title1)
                        .foregroundColor(.white)
                        .lineLimit(2)
                    Text(heroCaption(for: artist, presentation: presentation))
                        .font(BSFont.body)
                        .foregroundColor(Color.white.opacity(0.72))
                        .lineLimit(2)
                }
                .padding(BSSpacing.md)
            }
            .clipShape(RoundedRectangle(cornerRadius: BSRadius.sheet))
            .overlay(
                RoundedRectangle(cornerRadius: BSRadius.sheet)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.38), radius: 28, x: 0, y: 18)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(artist.resolvedName)，即将见到的艺人")

            familiarityCard(artist)
        }
    }

    private func eventContext(_ presentation: ArtistWarmupPresentationState) -> some View {
        BSGlassPanel {
            VStack(alignment: .leading, spacing: BSSpacing.xs) {
                Text(presentation.showTitle)
                    .font(BSFont.headline)
                    .foregroundColor(BSColor.Stage.foreground)
                    .lineLimit(2)
                if let subtitle = presentation.showSubtitle {
                    Text(subtitle)
                        .font(BSFont.body)
                        .foregroundColor(BSColor.Stage.muted)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func compactEventContext(_ presentation: ArtistWarmupPresentationState) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: BSSpacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text(presentation.showTitle)
                    .font(BSFont.caption)
                    .foregroundColor(BSColor.Stage.muted)
                    .lineLimit(1)
                if let subtitle = presentation.showSubtitle {
                    Text(subtitle)
                        .font(BSFont.tag)
                        .foregroundColor(BSColor.Stage.muted.opacity(0.8))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private func heroCaption(
        for artist: ArtistWarmupPresentedArtist,
        presentation: ArtistWarmupPresentationState
    ) -> String {
        if let providerName = artist.providerName, providerName != artist.displayName {
            return providerName
        }
        return "即将见到的艺人"
    }

    private func artistStack(
        _ artists: [ArtistWarmupPresentedArtist],
        showsIntentControls: Bool
    ) -> some View {
        LazyVStack(spacing: BSSpacing.sm) {
            ForEach(artists) { artist in
                artistRow(artist, showsIntentControls: showsIntentControls)
            }
        }
    }

    private func artistRow(
        _ artist: ArtistWarmupPresentedArtist,
        showsIntentControls: Bool
    ) -> some View {
        BSGlassPanel {
            VStack(alignment: .leading, spacing: BSSpacing.sm) {
                HStack(spacing: BSSpacing.md) {
                    WarmupArtistAvatar(name: artist.resolvedName, artworkURL: artist.artworkURL, size: 48)
                    VStack(alignment: .leading, spacing: BSSpacing.xs) {
                        Text(artist.resolvedName)
                            .font(BSFont.headline)
                            .foregroundColor(BSColor.Stage.foreground)
                            .lineLimit(2)
                        Text(familiaritySummary(for: artist))
                            .font(BSFont.body)
                            .foregroundColor(BSColor.Stage.muted)
                    }
                    Spacer(minLength: 0)
                    if showsIntentControls {
                        WarmupSecondaryButton(title: "只听这位", icon: "music.note") {
                            let scope = ArtistWarmupQueueScope.artistOnly(artist.id)
                            Task { await startWarmup(currentPresentation, scope: scope) }
                        }
                        .frame(width: 112)
                    }
                }

                FamiliarityBar(familiarity: artist.familiarity)

                if showsIntentControls {
                    HStack(spacing: BSSpacing.sm) {
                        interestButton(.wanted, artist: artist)
                        interestButton(.maybe, artist: artist)
                        interestButton(.notInterested, artist: artist)
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(artist.resolvedName)，\(familiaritySummary(for: artist))")
    }

    private func familiarityCard(_ artist: ArtistWarmupPresentedArtist) -> some View {
        BSGlassPanel {
            VStack(alignment: .leading, spacing: BSSpacing.sm) {
                HStack {
                    Text(artist.familiarity.hasCompleteCatalog ? artist.familiarity.tierLabel : "正在整理曲库")
                        .font(BSFont.headline)
                        .foregroundColor(BSColor.Stage.foreground)
                    Spacer()
                    Text(artist.familiarity.hasCompleteCatalog
                         ? "\(artist.familiarity.heardSongCount) / \(artist.familiarity.catalogSongCount) 首"
                         : "正在整理曲库")
                        .font(BSFont.caption)
                        .foregroundColor(BSColor.Stage.accent)
                }
                FamiliarityBar(familiarity: artist.familiarity)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(familiaritySummary(for: artist))
    }

    private func catalogTeaser(_ presentation: ArtistWarmupPresentationState) -> some View {
        BSGlassPanel {
            VStack(alignment: .leading, spacing: BSSpacing.sm) {
                Text("曲库仍可浏览")
                    .font(BSFont.headline)
                    .foregroundColor(BSColor.Stage.foreground)
                Text("试听、印象和手动补记会独立保存。")
                    .font(BSFont.body)
                    .foregroundColor(BSColor.Stage.muted)
                WarmupSecondaryButton(title: "查看曲库", icon: "rectangle.stack") {
                    route(to: presentation.songs.isEmpty ? .catalogLoading : .catalog)
                }
            }
        }
    }

    private func catalogSongRow(_ song: ArtistWarmupPresentedSong) -> some View {
        BSGlassPanel(padding: BSSpacing.sm) {
            HStack(spacing: BSSpacing.sm) {
                Button {
                    toggleManualHeard(song)
                } label: {
                    Image(systemName: song.isHeard ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(song.isHeard ? BSColor.Stage.accent : BSColor.Stage.muted)
                        .frame(width: BSLayout.minTouchTarget, height: BSLayout.minTouchTarget)
                }
                .accessibilityLabel(song.isHeard ? "已听，点击撤销" : "未听，点击标记")

                VStack(alignment: .leading, spacing: BSSpacing.xs) {
                    Text(song.title)
                        .font(BSFont.body)
                        .foregroundColor(BSColor.Stage.foreground)
                        .lineLimit(2)
                    Text("\(song.artistName) · \(song.albumTitle ?? "Apple Music")")
                        .font(BSFont.caption)
                        .foregroundColor(BSColor.Stage.muted)
                        .lineLimit(2)
                }

                Spacer(minLength: 0)

                WarmupIconButton(icon: "play.fill", label: "播放 \(song.title)") {
                    route(to: .player, nowPlayingSongID: song.id)
                }
            }
        }
    }

    private func playerProgress(song: ArtistWarmupPresentedSong) -> some View {
        let duration = catalogSongs.first { $0.appleMusicSongID == song.id }?.duration
            ?? musicService.playbackSnapshot().duration
        let progress = duration.map { $0 > 0 ? min(1, max(0, playbackTime / $0)) : 0 } ?? 0
        let percent = Int((progress * 100).rounded(.down))
        return VStack(spacing: BSSpacing.xs) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.10))
                    Capsule()
                        .fill(BSColor.Stage.accent)
                        .frame(width: geometry.size.width * progress)
                        .animation(reduceMotion ? nil : .easeInOut(duration: BSMotion.interface), value: progress)
                }
            }
            .frame(height: 5)

            HStack {
                Text(song.isHeard ? "已达到 50%，可记为听过" : "达到 50% 后自动记为听过")
                Spacer()
                Text("\(percent)%")
            }
            .font(BSFont.caption)
            .foregroundColor(BSColor.Stage.muted)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(song.isHeard
                            ? "播放进度百分之\(percent)，已记为听过"
                            : "播放进度百分之\(percent)，尚未记为听过")
    }

    private func queuePreview(_ presentation: ArtistWarmupPresentationState) -> some View {
        section("接下来") {
            ForEach(Array(presentation.songs.prefix(2))) { song in
                HStack(spacing: BSSpacing.sm) {
                    WarmupArtwork(name: song.title, size: 48)
                    VStack(alignment: .leading, spacing: BSSpacing.xs) {
                        Text(song.title)
                            .font(BSFont.body)
                            .foregroundColor(BSColor.Stage.foreground)
                            .lineLimit(1)
                        Text(song.albumTitle ?? song.artistName)
                            .font(BSFont.caption)
                            .foregroundColor(BSColor.Stage.muted)
                            .lineLimit(1)
                    }
                    Spacer()
                }
                .frame(minHeight: BSLayout.minTouchTarget)
            }
        }
    }

    private func recallSongRow(_ song: ArtistWarmupPresentedSong, isMarked: Bool) -> some View {
        Button {
            toggleRecall(song.id)
        } label: {
            HStack(spacing: BSSpacing.sm) {
                Image(systemName: isMarked ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(isMarked ? BSColor.Stage.accent : BSColor.Stage.muted)
                    .frame(width: BSLayout.minTouchTarget, height: BSLayout.minTouchTarget)

                VStack(alignment: .leading, spacing: BSSpacing.xs) {
                    Text(song.title)
                        .font(BSFont.body)
                        .foregroundColor(BSColor.Stage.foreground)
                    Text(isMarked ? "现场听到了" : "还没标记")
                        .font(BSFont.caption)
                        .foregroundColor(BSColor.Stage.muted)
                }
                Spacer()
                Text("演前期待")
                    .font(BSFont.caption)
                    .foregroundColor(BSColor.Stage.accent)
            }
            .padding(BSSpacing.sm)
            .background(Color.white.opacity(0.045))
            .clipShape(RoundedRectangle(cornerRadius: BSRadius.md))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(song.title)，\(isMarked ? "现场听到了" : "还没标记")")
    }

    private func interestButton(
        _ interest: ArtistInterest,
        artist: ArtistWarmupPresentedArtist
    ) -> some View {
        Button {
            setInterest(interest, for: artist)
        } label: {
            Text(interest.label)
                .font(BSFont.body)
                .foregroundColor(artist.interest == interest ? .black : BSColor.Stage.muted)
                .frame(maxWidth: .infinity)
                .frame(minHeight: BSLayout.minTouchTarget)
                .background(artist.interest == interest ? BSColor.Stage.accent : Color.white.opacity(0.045))
                .clipShape(RoundedRectangle(cornerRadius: BSRadius.md))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(artist.interest == interest ? .isSelected : [])
        .accessibilityLabel("\(artist.resolvedName)，\(interest.label)")
    }

    private func section<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: BSSpacing.sm) {
            BSSectionHeader(title: title)
            content()
        }
    }

    private func artistSearchSheet(_ presentation: ArtistWarmupPresentationState) -> some View {
        NavigationStack {
            ZStack {
                CurrentShowStageBackground().ignoresSafeArea()
                VStack(spacing: BSSpacing.md) {
                TextField("搜索艺人", text: $searchQuery)
                        .textFieldStyle(.plain)
                        .modifier(BSInputFieldStyle())
                        .accessibilityLabel("搜索 Apple Music 艺人")
                        .onSubmit {
                            Task { await searchArtistCandidates() }
                        }

                    ForEach(Array(searchResults.prefix(10).enumerated()), id: \.element.id) { _, candidate in
                        Button {
                            confirmCandidate(candidate, in: presentation)
                            isSearchPresented = false
                        } label: {
                            HStack(spacing: BSSpacing.md) {
                                WarmupArtistAvatar(name: candidate.name, artworkURL: candidate.artworkURL?.absoluteString, size: 50)
                                VStack(alignment: .leading, spacing: BSSpacing.xs) {
                                    Text(candidate.name)
                                        .font(BSFont.headline)
                                        .foregroundColor(BSColor.Stage.foreground)
                                    if let detail = candidate.distinguishingDetail {
                                        Text(detail)
                                            .font(BSFont.caption)
                                            .foregroundColor(BSColor.Stage.muted)
                                    }
                                }
                                Spacer()
                                Text("选择")
                                    .font(BSFont.body)
                                    .foregroundColor(BSColor.Stage.accent)
                            }
                            .frame(minHeight: 60)
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer()
                }
                .overlay {
                    if isSearchLoading {
                        ProgressView()
                    }
                }
                .padding(BSSpacing.md)
            }
            .navigationTitle("搜索 Apple Music 艺人")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { isSearchPresented = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func permissionSheet(_ presentation: ArtistWarmupPresentationState) -> some View {
        ZStack {
            CurrentShowStageBackground().ignoresSafeArea()
            VStack(spacing: BSSpacing.md) {
                BSStageSheetHeader(
                    icon: "music.note",
                    title: "连接 Apple Music",
                    subtitle: "用于浏览和播放 \(presentation.artists.first?.resolvedName ?? "艺人") 的 Apple Music 内容。"
                )

                BSGlassPanel {
                    Label("预热与歌曲印象默认私密", systemImage: "lock")
                        .font(BSFont.body)
                        .foregroundColor(BSColor.Stage.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                WarmupPrimaryButton(title: "允许访问", icon: "checkmark") {
                    Task {
                        await requestMusicAuthorization()
                        if authorizationStatus == .authorized {
                            confirmFirstArtist(in: presentation)
                        }
                    }
                    isPermissionPresented = false
                }

                WarmupSecondaryButton(title: "稍后", icon: "clock") {
                    isPermissionPresented = false
                }
            }
            .padding(BSSpacing.md)
        }
        .presentationDetents([.medium])
    }

    private func impressionSheet(_ presentation: ArtistWarmupPresentationState) -> some View {
        let song = selectedSongID.flatMap { id in presentation.songs.first(where: { $0.id == id }) }
            ?? presentation.songs.first

        return ZStack {
            CurrentShowStageBackground().ignoresSafeArea()
            VStack(alignment: .leading, spacing: BSSpacing.md) {
                BSStageSheetHeader(
                    icon: "sparkles",
                    title: "留一点印象",
                    subtitle: "印象只写入这场现场，不改变熟悉度。"
                )

                if let song {
                    BSGlassPanel {
                        HStack(spacing: BSSpacing.md) {
                            WarmupArtwork(name: song.title, size: 52)
                            VStack(alignment: .leading, spacing: BSSpacing.xs) {
                                Text(song.title)
                                    .font(BSFont.headline)
                                    .foregroundColor(BSColor.Stage.foreground)
                                    .lineLimit(2)
                                Text(song.artistName)
                                    .font(BSFont.caption)
                                    .foregroundColor(BSColor.Stage.muted)
                            }
                            Spacer()
                            Label("私密", systemImage: "lock")
                                .font(BSFont.caption)
                                .foregroundColor(BSColor.Stage.accent)
                        }
                    }
                }

                Toggle("想现场听", isOn: $impressionWantsLive)
                    .font(BSFont.body)
                    .foregroundColor(BSColor.Stage.foreground)
                    .tint(BSColor.Stage.accent)
                    .frame(minHeight: BSLayout.minTouchTarget)

                Toggle("有感觉", isOn: $impressionHasFeeling)
                    .font(BSFont.body)
                    .foregroundColor(BSColor.Stage.foreground)
                    .tint(BSColor.Stage.accent)
                    .frame(minHeight: BSLayout.minTouchTarget)

                TextField("写一句（可选）", text: $impressionNote)
                    .textFieldStyle(.plain)
                    .modifier(BSInputFieldStyle())
                    .accessibilityLabel("写一句印象")

                WarmupPrimaryButton(title: "保存", icon: "checkmark") {
                    if let song {
                        saveImpression(songID: song.id)
                    }
                    isImpressionPresented = false
                }
            }
            .padding(BSSpacing.md)
        }
        .presentationDetents([.medium, .large])
    }

    private func deferConnecting() {
        mutatePresentation { presentation in
            presentation.artists = presentation.artists.map { artist in
                var copy = artist
                copy.isConnected = false
                copy.providerName = nil
                copy.artworkURL = nil
                return copy
            }
            presentation.screen = .candidateConnection
        }

        for artist in showArtists where artist.showID == currentShowID {
            artist.clearAppleMusicConfirmation()
        }
        try? modelContext.save()
        isArtistConfirmed = false
        isSearchPresented = true
    }

    private func albumGroups(from songs: [ArtistWarmupPresentedSong]) -> [(title: String, songs: [ArtistWarmupPresentedSong])] {
        let grouped = Dictionary(grouping: songs) { $0.albumTitle ?? "未命名专辑" }
        return grouped.keys.sorted().map { title in
            (title: title, songs: grouped[title] ?? [])
        }
    }

    private func albumMarkHeardButton(_ album: (title: String, songs: [ArtistWarmupPresentedSong])) -> some View {
        WarmupSecondaryButton(title: "整张补记听过", icon: "checkmark.circle") {
            markAlbumHeard(album.songs)
        }
        .accessibilityLabel("把\(album.title)整张补记为听过")
    }

    private func markAlbumHeard(_ songs: [ArtistWarmupPresentedSong]) {
        for song in songs where !song.isHeard {
            toggleManualHeard(song)
        }
    }

    private func searchArtistCandidates() async {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            searchResults = []
            return
        }

        isSearchLoading = true
        defer { isSearchLoading = false }
        do {
            searchResults = try await musicService.searchArtistCandidates(query: query, limit: 10)
            warmupErrorMessage = nil
        } catch {
            searchResults = []
            warmupErrorMessage = "暂时搜不到 Apple Music 艺人，请稍后再试。"
        }
    }

    private func confirmCandidate(
        _ candidate: ArtistWarmupArtistCandidate,
        in presentation: ArtistWarmupPresentationState
    ) {
        guard let show = currentShow else { return }
        let originalLabel = presentation.artists.first?.displayName ?? candidate.name
        let stored: ShowArtist
        if let existing = showArtists.first(where: {
            $0.showID == show.id && $0.originalArtistLabel == originalLabel
        }) {
            stored = existing
        } else {
            stored = ShowArtist(
                showID: show.id,
                originalArtistLabel: originalLabel,
                originalOrder: showArtists.filter { $0.showID == show.id }.count,
                interest: .maybe
            )
            modelContext.insert(stored)
        }

        stored.confirmAppleMusicArtist(
            id: candidate.id,
            name: candidate.name,
            artworkURL: candidate.artworkURL?.absoluteString
        )
        try? modelContext.save()

        mutatePresentation { changed in
            if let index = changed.artists.firstIndex(where: { $0.displayName == originalLabel }) {
                changed.artists[index].id = candidate.id
                changed.artists[index].providerName = candidate.name
                changed.artists[index].artworkURL = candidate.artworkURL?.absoluteString
                changed.artists[index].isConnected = true
            }
        }
    }

    private func route(to screen: ArtistWarmupPresentationScreen, nowPlayingSongID: String? = nil) {
        var presentation = currentPresentation
        presentation.screen = screen
        if let nowPlayingSongID {
            presentation.nowPlayingSongID = nowPlayingSongID
        } else if presentation.nowPlayingSongID == nil {
            presentation.nowPlayingSongID = presentation.songs.first?.id
        }
        localPresentation = presentation
    }

    private func setInterest(
        _ interest: ArtistInterest,
        for artist: ArtistWarmupPresentedArtist
    ) {
        mutatePresentation { presentation in
            guard let index = presentation.artists.firstIndex(where: { $0.id == artist.id }) else { return }
            presentation.artists[index].interest = interest
        }

        guard let storedArtist = showArtists.first(where: {
            $0.id.uuidString == artist.id || $0.appleMusicArtistID == artist.id
        }) else {
            return
        }
        storedArtist.interest = interest
        try? modelContext.save()
    }

    private func toggleManualHeard(_ song: ArtistWarmupPresentedSong) {
        let isNowHeard = !song.isHeard
        mutatePresentation { presentation in
            guard let songIndex = presentation.songs.firstIndex(where: { $0.id == song.id }) else { return }
            presentation.songs[songIndex].isHeard = isNowHeard
            guard let artistIndex = presentation.artists.firstIndex(where: { $0.id == song.artistID }) else { return }
            let delta = isNowHeard ? 1 : -1
            let current = presentation.artists[artistIndex].familiarity.heardSongCount
            presentation.artists[artistIndex].familiarity.heardSongCount = max(0, current + delta)
        }

        if isNowHeard {
            if let existing = familiarityRecords.first(where: { $0.songID == song.id }) {
                existing.update(heardAt: Date(), source: .manual)
            } else {
                modelContext.insert(SongFamiliarityRecord(songID: song.id, heardAt: Date(), source: .manual))
            }
        } else if let existing = familiarityRecords.first(where: { $0.songID == song.id }) {
            modelContext.delete(existing)
        }
        try? modelContext.save()
    }

    private func updateSong(_ songID: String, update: (inout ArtistWarmupPresentedSong) -> Void) {
        mutatePresentation { presentation in
            guard let index = presentation.songs.firstIndex(where: { $0.id == songID }) else { return }
            update(&presentation.songs[index])
        }
    }

    private func openImpression(_ song: ArtistWarmupPresentedSong) {
        selectedSongID = song.id
        impressionWantsLive = song.wantsLive
        impressionHasFeeling = song.hasImpression
        impressionNote = currentPresentation.impressions[song.id]?.note ?? ""
        isImpressionPresented = true
    }

    private func saveImpression(songID: String) {
        let note = impressionNote.trimmingCharacters(in: .whitespacesAndNewlines)
        localPresentation = currentPresentation.savingImpression(
            songID: songID,
            wantsLive: impressionWantsLive,
            hasFeeling: impressionHasFeeling,
            note: note.isEmpty ? nil : note
        )

        guard let showID = currentShowID else { return }
        let repository = ArtistWarmupRepository(context: modelContext)
        _ = try? repository.upsertImpression(
            showID: showID,
            songID: songID,
            wantsLive: impressionWantsLive,
            hasFeeling: impressionHasFeeling,
            note: note
        )
        try? modelContext.save()
    }

    private func confirmFirstArtist(in presentation: ArtistWarmupPresentationState) {
        guard let show = currentShow,
              let artist = presentation.artists.first else {
            return
        }
        guard !artist.id.hasPrefix("candidate-") else {
            return
        }

        let stored: ShowArtist
        if let existing = showArtists.first(where: {
            $0.showID == show.id && $0.originalArtistLabel == artist.displayName
        }) {
            stored = existing
        } else {
            stored = ShowArtist(
                showID: show.id,
                originalArtistLabel: artist.displayName,
                originalOrder: 0,
                interest: artist.interest
            )
            modelContext.insert(stored)
        }

        stored.confirmAppleMusicArtist(
            id: artist.id,
            name: artist.providerName ?? artist.displayName,
            artworkURL: artist.artworkURL
        )
        try? modelContext.save()
        mutatePresentation { changed in
            guard !changed.artists.isEmpty else { return }
            changed.artists[0].isConnected = true
            changed.artists[0].providerName = artist.providerName ?? artist.displayName
        }
    }

    private func toggleRecall(_ songID: String) {
        mutatePresentation { presentation in
            if presentation.recallSongIDs.contains(songID) {
                presentation.recallSongIDs.removeAll { $0 == songID }
            } else {
                presentation.recallSongIDs.append(songID)
            }
        }
    }

    private func addManualRecall() {
        let title = recallManualTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }

        mutatePresentation { presentation in
            let id = "manual-\(UUID().uuidString)"
            presentation.songs.append(ArtistWarmupPresentedSong(
                id: id,
                artistID: presentation.artists.first?.id ?? "manual",
                title: title,
                albumTitle: "现场补记",
                artistName: presentation.artists.first?.resolvedName ?? "现场",
                isHeard: true,
                wantsLive: false,
                hasImpression: false
            ))
            presentation.recallSongIDs.append(id)
        }
        recallManualTitle = ""
    }

    private func saveRecall(_ presentation: ArtistWarmupPresentationState) {
        guard ArtistWarmupDebugFixture.requestedState == nil,
              let showID = currentShowID else {
            return
        }

        let service = ArtistWarmupSnapshotService(context: modelContext)
        let now = Date()
        do {
            for songID in presentation.recallSongIDs where !songID.hasPrefix("manual-") {
                _ = try service.confirmCatalogSongHeardAtShow(
                    showID: showID,
                    songID: songID,
                    heardAtShow: now
                )
            }

            for song in presentation.songs where song.id.hasPrefix("manual-") && presentation.recallSongIDs.contains(song.id) {
                _ = try service.rememberManualSongAtShow(
                    showID: showID,
                    title: song.title,
                    artistName: song.artistName,
                    heardAtShow: now
                )
            }

            try modelContext.save()
            warmupErrorMessage = nil
        } catch {
            warmupErrorMessage = "这次回记没有保存，请稍后再试。"
        }
    }

    private func mutatePresentation(_ update: (inout ArtistWarmupPresentationState) -> Void) {
        var presentation = currentPresentation
        update(&presentation)
        localPresentation = presentation
    }

    private var currentShow: Show? {
        CurrentShowSession().resolve(shows: shows, manualSelection: selections.first)?.show
    }

    private var currentShowID: UUID? {
        currentShow?.id
    }
}

private struct WarmupMessagePanel: View {
    let icon: String
    let title: String
    let message: String
    let tint: Color

    var body: some View {
        BSGlassPanel(padding: BSSpacing.lg) {
            VStack(spacing: BSSpacing.md) {
                Image(systemName: icon)
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundColor(tint)
                    .frame(width: 58, height: 58)
                    .background(tint.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: BSRadius.v3Medium))
                    .accessibilityHidden(true)

                Text(title)
                    .font(BSFont.V3.title2)
                    .foregroundColor(BSColor.Stage.foreground)
                    .multilineTextAlignment(.center)

                Text(message)
                    .font(BSFont.body)
                    .foregroundColor(BSColor.Stage.muted)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, minHeight: 220)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct WarmupArtistAvatar: View {
    let name: String
    let artworkURL: String?
    let size: CGFloat

    var body: some View {
        ZStack {
            if let url = resolvedArtworkURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    default:
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }

    private var initials: String {
        String(name.prefix(2))
    }

    private var resolvedArtworkURL: URL? {
        guard let artworkURL, let url = URL(string: artworkURL) else {
            return nil
        }
        return url
    }

    private var placeholder: some View {
        ZStack {
            WarmupArtwork(name: name, size: size)
            Text(initials)
                .font(.system(size: max(14, size * 0.28), weight: .semibold))
                .foregroundColor(BSColor.Stage.foreground)
        }
    }
}

private struct WarmupArtwork: View {
    let name: String
    let size: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: max(BSRadius.md, size * 0.08))
            .fill(
                LinearGradient(
                    colors: colors,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay {
                RoundedRectangle(cornerRadius: max(BSRadius.md, size * 0.08))
                    .stroke(BSColor.borderProminent, lineWidth: 1)
            }
            .frame(width: size, height: size)
            .shadow(color: colors.first?.opacity(0.18) ?? .clear, radius: 18, x: 0, y: 10)
            .accessibilityHidden(true)
    }

    private var colors: [Color] {
        let palettes: [[Color]] = [
            [BSColor.Stage.accent, BSColor.Stage.glowBlue, BSColor.Stage.surfaceRaised],
            [BSColor.Accent.info, BSColor.Accent.prepare, BSColor.Stage.surface],
            [BSColor.Accent.violet, BSColor.Accent.warm, BSColor.Stage.surfaceRaised]
        ]
        let index = abs(name.unicodeScalars.map { Int($0.value) }.reduce(0, +)) % palettes.count
        return palettes[index]
    }
}

private struct FamiliarityBar: View {
    let familiarity: ArtistWarmupPresentedFamiliarity

    var body: some View {
        VStack(alignment: .leading, spacing: BSSpacing.xs) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.08))
                    Capsule()
                        .fill(BSColor.Stage.accent)
                        .frame(width: geometry.size.width * CGFloat(familiarity.percent) / 100)
                }
            }
            .frame(height: 4)

            Text("\(familiarity.percent)%")
                .font(BSFont.caption)
                .foregroundColor(BSColor.Stage.muted)
        }
        .accessibilityHidden(true)
    }
}

private struct WarmupPrimaryButton: View {
    let title: String
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(BSFont.headline)
                .foregroundColor(.black)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 52)
                .background(BSColor.Stage.accent)
                .clipShape(RoundedRectangle(cornerRadius: BSRadius.md))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

private struct WarmupSecondaryButton: View {
    let title: String
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(BSFont.body)
                .foregroundColor(BSColor.Stage.foreground)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .frame(maxWidth: .infinity)
                .frame(minHeight: BSLayout.minTouchTarget)
                .background(Color.white.opacity(0.055))
                .clipShape(RoundedRectangle(cornerRadius: BSRadius.md))
                .overlay(
                    RoundedRectangle(cornerRadius: BSRadius.md)
                        .stroke(BSColor.Stage.border, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

private struct WarmupIconButton: View {
    let icon: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(BSColor.Stage.foreground)
                .frame(width: BSLayout.minTouchTarget, height: BSLayout.minTouchTarget)
                .background(Color.white.opacity(0.055))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

private struct WarmupSegmentedHeader: View {
    let items: [String]

    var body: some View {
        HStack(spacing: BSSpacing.xs) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                Text(item)
                    .font(BSFont.body)
                    .foregroundColor(index == 0 ? BSColor.Stage.foreground : BSColor.Stage.muted)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: BSLayout.minTouchTarget)
                    .background(index == 0 ? BSColor.Stage.surfaceRaised : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: BSRadius.sm))
                    .accessibilityAddTraits(index == 0 ? .isSelected : [])
            }
        }
        .padding(3)
        .background(Color.white.opacity(0.035))
        .clipShape(RoundedRectangle(cornerRadius: BSRadius.md))
        .overlay(
            RoundedRectangle(cornerRadius: BSRadius.md)
                .stroke(BSColor.Stage.border, lineWidth: 1)
        )
    }
}


private extension CatalogSongPresentationGroup {
    var catalogCategory: CatalogSongCategory {
        switch self {
        case .albums:
            .album
        case .singles:
            .single
        case .collaborations:
            .collaboration
        }
    }
}
