import SwiftUI

private struct IndexedTrack: Identifiable {
    let index: Int
    let track: ListeningDiscTrack
    var id: String { track.id }
}

struct ListeningDiscDetailView: View {
    @Bindable var room: ListeningRoomCoordinator
    let disc: ListeningDisc
    var onLoad: () -> Void = {}
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dismiss) private var dismiss
    @State private var requestedTrackID: String?

    private let isMultiArtist: Bool
    private let metadataSummary: String
    private let artistsSummary: String
    private let indexedTracks: [IndexedTrack]

    init(room: ListeningRoomCoordinator, disc: ListeningDisc, onLoad: @escaping () -> Void = {}) {
        self.room = room
        self.disc = disc
        self.onLoad = onLoad
        self.indexedTracks = disc.tracks.enumerated().map { IndexedTrack(index: $0.offset, track: $0.element) }

        let multi: Bool
        if case .compilation = disc.origin {
            multi = true
        } else {
            multi = Set(disc.tracks.map(\.artistName)).count > 1
        }
        self.isMultiArtist = multi

        let total = disc.tracks.compactMap(\.duration).reduce(0, +)
        var items: [String] = []
        if !disc.genreNames.isEmpty {
            items.append(disc.genreNames.joined(separator: " · "))
        }
        if let releaseDate = disc.releaseDate {
            items.append(releaseDate.formatted(.dateTime.year()))
        }
        items.append(BSLocalization.format("%d 首歌曲", disc.tracks.count))
        if total > 0 {
            items.append("\(Int(total) / 60) \(BSLocalization.text("分钟"))")
        }
        self.metadataSummary = items.joined(separator: " · ")

        let artists = disc.artistNames.isEmpty
            ? Array(Set(disc.tracks.map(\.artistName))).sorted() : disc.artistNames
        self.artistsSummary = artists.count > 3
            ? ListeningCopy.format("%@ 等 %d 位艺人", artists.prefix(2).joined(separator: " / "), artists.count)
            : artists.joined(separator: " / ")
    }

    private var isLoaded: Bool {
        room.mechanism.disc?.id == disc.id && room.mechanism.position != .stored
    }

    private var presentation: ListeningDiscPresentation {
        room.discPresentation(for: disc)
    }

    private var albumBadges: [String] {
        var badges: [String] = []
        if disc.isAppleDigitalMaster == true {
            badges.append(BSLocalization.text("Apple Digital Master"))
        }
        for variant in disc.audioVariantRawValues {
            if let title = audioVariantTitle(variant), !badges.contains(title) {
                badges.append(title)
            }
        }
        return badges
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: BSSpacing.lg) {
                    ListeningDiscDetailHero(
                        disc: disc, show: room.show, artists: artistsSummary,
                        metadata: metadataSummary, isLoaded: isLoaded,
                        isPlaying: isLoaded && room.isPlaying,
                        containsHeardSongs: room.containsHeardSongs(disc)
                    )

                    if !albumBadges.isEmpty {
                        badgeSection
                    }

                    trackListSection

                    if let editorial = disc.editorialText, !editorial.isEmpty {
                        editorialSection(editorial)
                    }

                    footerSection
                }
                .padding(.horizontal, BSSpacing.roomy)
                .padding(.top, BSSpacing.sm)
                .padding(.bottom, BSSpacing.xl)
            }
            .background(ListeningSheetBackground(tint: ListeningSleeveIdentity(disc: disc).color))
            .safeAreaInset(edge: .bottom) {
                actionSection
                    .padding(.horizontal, BSSpacing.roomy)
                    .padding(.vertical, BSSpacing.md)
                    .background(BSColor.Stage.background)
                    .overlay(alignment: .top) {
                        Rectangle().fill(BSColor.Stage.border).frame(height: BSListeningTokens.hairline)
                    }
            }
            .foregroundStyle(BSColor.Stage.foreground)
            .navigationTitle(BSLocalization.text("专辑详情"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                BSChromeToolbarCloseButton { dismiss() }
            }
        }
        // Navigation chrome stays neutral; playback/selection accents inside
        // the sheet are styled explicitly at their point of use.
        .tint(BSColor.Stage.foreground)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .onChange(of: room.sleevePlaybackSongID) { _, songID in
            if songID == requestedTrackID {
                requestedTrackID = nil
            }
        }
        .onChange(of: room.playbackError) { _, error in
            if error != nil {
                requestedTrackID = nil
            }
        }
    }

    @ViewBuilder
    private var actionSection: some View {
        if isLoaded {
            loadedFallbackActions
        } else {
            switch presentation.primaryAction {
            case .load:
                Button(action: load) {
                    Label(presentation.capability == .previewOnly
                          ? ListeningCopy.text("装入并试听") : BSLocalization.text("装入播放机"),
                          systemImage: "opticaldisc")
                }
                .buttonStyle(BSListeningActionStyle())
                .disabled(room.busy)
                .accessibilityValue(presentation.statusText)
                .accessibilityIdentifier("listening.loadDisc")

            case let .openAppleMusic(url):
                appleMusicPrimaryAction(url)

            case .informationOnly:
                capabilityNotice(ListeningCopy.text("仅提供歌曲信息"))

            case .unavailable:
                capabilityNotice(presentation.statusText)
            }
        }
    }

    @ViewBuilder
    private var loadedFallbackActions: some View {
        let player = room.display.player
        if let recovery = player.recoveryAction {
            Button(recovery.title) { room.performListeningRecovery(recovery) }
                .buttonStyle(BSListeningActionStyle())
                .disabled(room.busy)
        } else if player.canPlayPause {
            Button { room.perform(.playPause) } label: {
                Label(BSLocalization.text(room.isPlaying ? "暂停" : "播放"),
                      systemImage: room.isPlaying ? "pause.fill" : "play.fill")
            }
            .buttonStyle(BSListeningActionStyle())
            .disabled(room.busy || room.mechanism.isAutomatic)
            .accessibilityIdentifier("listening.detail.playPause")
        } else if case .metadataOnly = presentation.capability, let url = disc.appleMusicURL {
            appleMusicPrimaryAction(url)
        } else {
            capabilityNotice(player.blockingReason ?? player.statusText)
        }
    }

    private func capabilityNotice(_ text: String) -> some View {
        ListeningCatalogStatusView(title: text, icon: "info.circle")
    }

    private func appleMusicPrimaryAction(_ url: URL) -> some View {
        Link(destination: url) {
            Label(BSLocalization.text("在 Apple Music 中打开"), systemImage: "arrow.up.right")
        }
        .buttonStyle(BSListeningActionStyle())
        .accessibilityIdentifier("listening.openAppleMusic")
    }

    private var badgeSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: BSSpacing.xs) {
                ForEach(albumBadges, id: \.self) { badge in
                    Text(badge)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(BSColor.Stage.muted)
                        .padding(.horizontal, BSSpacing.compact)
                        .padding(.vertical, BSSpacing.xs)
                        .background(BSColor.Stage.surfaceRaised.opacity(0.7), in: Capsule())
                        .overlay(Capsule().stroke(BSColor.Stage.border, lineWidth: 0.75))
                }
            }
        }
    }

    private var trackListSection: some View {
        let player = room.display.player
        let currentTrackID = room.track?.id
        let isLoadedDisc = isLoaded
        let isBusy = room.busy
        let isAuto = room.mechanism.isAutomatic

        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(BSLocalization.text("TRACKLIST"))
                    .font(BSListeningTokens.sectionTitle)
                    .foregroundStyle(BSColor.Stage.muted)
                Spacer()
                Text(trackListStatusText)
                    .font(BSListeningTokens.caption)
                    .foregroundStyle(BSColor.Stage.muted)
            }
            .padding(.horizontal, BSSpacing.md)
            .padding(.vertical, BSSpacing.compact)

            VStack(spacing: 0) {
                ForEach(indexedTracks) { item in
                    trackRow(
                        index: item.index,
                        track: item.track,
                        player: player,
                        currentTrackID: currentTrackID,
                        isLoadedDisc: isLoadedDisc,
                        isBusy: isBusy,
                        isAuto: isAuto
                    )

                    if item.index < indexedTracks.count - 1 {
                        Rectangle()
                            .fill(BSColor.Stage.border)
                            .frame(height: BSListeningTokens.hairline)
                            .padding(.leading, BSListeningTokens.rowDividerInset)
                            .accessibilityHidden(true)
                    }
                }
            }
        }

    }

    private var trackListStatusText: String {
        if case .previewOnly = presentation.capability {
            return presentation.statusText
        }
        return BSLocalization.format("%d 首歌曲", disc.tracks.count)
    }

    @ViewBuilder
    private func trackRow(
        index: Int,
        track: ListeningDiscTrack,
        player: ListeningPlayerPresentation,
        currentTrackID: String?,
        isLoadedDisc: Bool,
        isBusy: Bool,
        isAuto: Bool
    ) -> some View {
        let trackPresentation = room.trackPresentation(for: track)
        let isCurrent = isLoadedDisc && currentTrackID == track.id
        let state = trackRowState(
            for: track,
            isPlayable: trackPresentation.isPlayable,
            isCurrent: isCurrent,
            playerPhase: player.phase
        )
        let action = ListeningDiscDetailTrackAction.resolve(
            isLoaded: isLoadedDisc,
            isCurrentTrack: isCurrent,
            player: player
        )
        let row = ListeningDiscTrackRow(
            index: index,
            track: track,
            state: state,
            isMultiArtist: isMultiArtist,
            showsPlaybackToggle: action == .togglePlayback
        )

        if trackPresentation.isPlayable {
            Button {
                switch action {
                case .selectTrack:
                    selectTrack(track)
                case .togglePlayback:
                    room.perform(.playPause)
                }
            } label: {
                row
            }
            .buttonStyle(BSListeningPressStyle(scale: 0.985))
            .disabled(isBusy || isAuto)
            .accessibilityValue(accessibilityValue(for: state, presentation: trackPresentation))
            .accessibilityIdentifier("listening.track.\(track.id)")
        } else {
            row
                .accessibilityValue(trackPresentation.statusText)
                .accessibilityIdentifier("listening.track.\(track.id)")
        }
    }

    private func trackRowState(
        for track: ListeningDiscTrack,
        isPlayable: Bool,
        isCurrent: Bool,
        playerPhase: ListeningPlayerPhase
    ) -> ListeningDiscTrackRowState {
        guard isPlayable else { return .unavailable }
        if requestedTrackID == track.id { return .preparing }
        guard isCurrent else { return .normal }

        switch playerPhase {
        case .preparing:
            return .preparing
        case .playing:
            return .playing
        case .paused:
            return .paused
        case .noDisc, .stopped, .finished, .failed:
            return .paused
        }
    }

    private func accessibilityValue(
        for state: ListeningDiscTrackRowState,
        presentation: ListeningTrackPresentation
    ) -> String {
        switch state {
        case .preparing:
            return ListeningCopy.text("载入中…")
        case .playing:
            return ListeningCopy.text("播放中")
        case .paused:
            return ListeningCopy.text("暂停")
        case .unavailable:
            return presentation.statusText
        case .normal:
            return presentation.capability == .previewOnly
                ? ListeningCopy.text("30 秒试听")
                : presentation.statusText
        }
    }

    private func selectTrack(_ track: ListeningDiscTrack) {
        let trackPresentation = room.trackPresentation(for: track)
        guard trackPresentation.isPlayable,
              !room.busy,
              !room.mechanism.isAutomatic else { return }

        let sameDisc = isLoaded
        if sameDisc, room.track?.id == track.id, room.isPlaying {
            return
        }

        requestedTrackID = track.id
        room.playFromSleeve(disc, songID: track.id)

        if !sameDisc {
            dismiss()
            onLoad()
        }
    }

    private func editorialSection(_ editorial: String) -> some View {
        VStack(alignment: .leading, spacing: BSSpacing.xs) {
            Text(BSLocalization.text("专辑简介"))
                .font(BSListeningTokens.caption.weight(.semibold))
                .foregroundStyle(BSColor.Stage.dim)
            Text(editorial)
                .font(BSListeningTokens.body)
                .lineSpacing(5)
                .foregroundStyle(BSColor.Stage.muted)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(BSSpacing.md)
        .background(BSColor.Stage.surface.opacity(0.6), in: RoundedRectangle(cornerRadius: BSRadius.md, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: BSRadius.md, style: .continuous).stroke(BSColor.Stage.border, lineWidth: 1))
    }

    private var footerSection: some View {
        VStack(spacing: BSSpacing.sm) {
            if let releaseDate = disc.releaseDate {
                Text("\(BSLocalization.text("发行日期")): \(releaseDate.formatted(date: .long, time: .omitted))")
                    .font(BSListeningTokens.caption)
                    .foregroundStyle(BSColor.Stage.dim)
            }
            if let label = disc.recordLabelName, !label.isEmpty {
                Text("\(BSLocalization.text("唱片公司")): \(label)")
                    .font(BSListeningTokens.caption)
                    .foregroundStyle(BSColor.Stage.dim)
            }
            if let copyright = disc.copyright, !copyright.isEmpty {
                Text(copyright)
                    .font(BSListeningTokens.caption)
                    .foregroundStyle(BSColor.Stage.dim)
                    .multilineTextAlignment(.center)
            }
            if let url = disc.appleMusicURL {
                Link(destination: url) {
                    HStack(spacing: BSSpacing.xs) {
                        Text(BSLocalization.text("在 Apple Music 中打开"))
                        Image(systemName: "arrow.up.right.square")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .font(BSListeningTokens.caption.weight(.semibold))
                    .foregroundStyle(BSColor.Stage.accent)
                    .padding(.top, 4)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, BSSpacing.sm)
    }

    private func audioVariantTitle(_ raw: String) -> String? {
        switch raw {
        case "dolbyAtmos": BSLocalization.text("杜比全景声")
        case "dolbyAudio": BSLocalization.text("杜比音效")
        case "lossless": BSLocalization.text("无损")
        case "highResolutionLossless": BSLocalization.text("高解析无损")
        default: nil
        }
    }

    private func load() {
        room.loadPlayableDisc(disc)
        dismiss()
        onLoad()
    }
}
