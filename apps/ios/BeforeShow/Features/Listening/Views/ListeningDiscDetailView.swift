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
    @State private var tone: Color?
    @State private var isEditorialExpanded = false

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
        room.display.hardware.discID == disc.id && room.display.hardware.position != .stored
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
                        isPlaying: isLoaded && room.display.player.isPlaybackActive,
                        containsHeardSongs: room.containsHeardSongs(disc)
                    )

                    if !albumBadges.isEmpty {
                        badgeSection
                    }

                    if let editorial = editorialContent {
                        editorialSection(editorial.attributed, isLong: editorial.isLong)
                    }

                    trackListSection

                    footerSection
                }
                .padding(.horizontal, BSSpacing.roomy)
                .padding(.top, BSSpacing.sm)
                .padding(.bottom, BSSpacing.xl)
            }
            .background(
                ListeningSheetBackground(
                    tint: tone ?? ListeningSleeveIdentity(disc: disc).color,
                    intensity: BSListeningTokens.detailGlowOpacity
                )
                .animation(.easeInOut(duration: 0.5), value: tone)
            )
            .task(id: disc.artworkURL) {
                guard let url = disc.artworkURL else { return }
                tone = await ListeningArtworkTone.tone(for: url).map(Color.init(uiColor:))
            }
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
        .listeningPlaybackFailureAlert(room)
        .presentationDragIndicator(.visible)
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
        if player.phase == .preparing {
            Button(action: {}) {
                HStack(spacing: BSSpacing.sm) {
                    ProgressView()
                        .controlSize(.small)
                        .tint(BSListeningTokens.ink)
                    Text(ListeningCopy.text("载入中…"))
                }
            }
            .buttonStyle(BSListeningActionStyle())
            .allowsHitTesting(false)
            .accessibilityLabel(ListeningCopy.text("载入中…"))
            .accessibilityIdentifier("listening.detail.preparing")
        } else if let recovery = player.recoveryAction {
            Button(recovery.title) { room.performListeningRecovery(recovery) }
                .buttonStyle(BSListeningActionStyle())
                .disabled(room.busy)
        } else if player.canPlayPause {
            Button { room.perform(.playPause) } label: {
                Label(
                    BSLocalization.text(player.showsPauseControl ? "暂停" : "播放"),
                    systemImage: player.showsPauseControl ? "pause.fill" : "play.fill"
                )
            }
            .buttonStyle(BSListeningActionStyle())
            .disabled(room.busy || room.display.hardware.isAutomatic)
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
            Label(BSLocalization.text("在 Apple Music 上收听"), systemImage: "arrow.up.right")
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
        let isAuto = room.display.hardware.isAutomatic

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
            .padding(.horizontal, BSSpacing.xs)
            .padding(.bottom, BSSpacing.sm)

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
            .padding(.vertical, BSSpacing.xs)
            .background(
                BSColor.Stage.surface.opacity(0.62),
                in: RoundedRectangle(cornerRadius: BSRadius.md, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: BSRadius.md, style: .continuous)
                    .stroke(BSColor.Stage.border, lineWidth: BSListeningTokens.hairline)
            )
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
            playPauseAction: action == .togglePlayback ? player.playPauseAction : nil
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
        guard isCurrent else { return .normal }

        switch playerPhase {
        case .preparing, .waiting:
            return .preparing
        case .playing, .seeking:
            return .playing
        case .paused, .interrupted:
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
              !room.display.hardware.isAutomatic else { return }

        let sameDisc = isLoaded
        if sameDisc, room.track?.id == track.id, room.wantsPlayback {
            return
        }

        room.playFromSleeve(disc, songID: track.id)

        if !sameDisc {
            dismiss()
            onLoad()
        }
    }

    private var editorialContent: (attributed: AttributedString, isLong: Bool)? {
        guard let raw = disc.editorialText?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        let (attributed, plain) = Self.renderHTMLToAttributedString(raw)
        guard !plain.isEmpty else { return nil }
        let isLong = plain.count > 140 || plain.contains("\n")
        return (attributed, isLong)
    }

    private static func renderHTMLToAttributedString(_ html: String) -> (attributed: AttributedString, plain: String) {
        var md = html
        // Line breaks & paragraphs
        md = md.replacingOccurrences(of: "<br\\s*/?>", with: "\n", options: .regularExpression)
        md = md.replacingOccurrences(of: "<p>", with: "\n\n", options: .caseInsensitive)
        md = md.replacingOccurrences(of: "</p>", with: "", options: .caseInsensitive)

        // Bold / strong
        md = md.replacingOccurrences(of: "<(b|strong)>", with: "**", options: .regularExpression)
        md = md.replacingOccurrences(of: "</(b|strong)>", with: "**", options: .regularExpression)

        // Italic / emphasis
        md = md.replacingOccurrences(of: "<(i|em)>", with: "*", options: .regularExpression)
        md = md.replacingOccurrences(of: "</(i|em)>", with: "*", options: .regularExpression)

        // Links: <a href="url">text</a> -> [text](url)
        let linkRegex = "<a\\s+[^>]*href=[\"']([^\"']*)[\"'][^>]*>(.*?)</a>"
        md = md.replacingOccurrences(of: linkRegex, with: "[$2]($1)", options: .regularExpression)

        // Strip remaining unsupported HTML tags
        md = md.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)

        // Decode HTML entities
        md = md.replacingOccurrences(of: "&amp;", with: "&")
        md = md.replacingOccurrences(of: "&quot;", with: "\"")
        md = md.replacingOccurrences(of: "&#39;", with: "'")
        md = md.replacingOccurrences(of: "&apos;", with: "'")
        md = md.replacingOccurrences(of: "&lt;", with: "<")
        md = md.replacingOccurrences(of: "&gt;", with: ">")
        md = md.replacingOccurrences(of: "&nbsp;", with: " ")

        // Normalize multiple blank lines
        md = md.replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
        let plain = md.trimmingCharacters(in: .whitespacesAndNewlines)

        if let attr = try? AttributedString(markdown: plain, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
            return (attr, plain)
        }
        return (AttributedString(plain), plain)
    }

    private func editorialSection(_ attributed: AttributedString, isLong: Bool) -> some View {
        VStack(alignment: .leading, spacing: BSSpacing.xs) {
            HStack {
                Text(BSLocalization.text("编辑评语"))
                    .font(BSListeningTokens.sectionTitle)
                    .foregroundStyle(BSColor.Stage.muted)
                Spacer()
            }
            .padding(.horizontal, BSSpacing.xs)
            .padding(.bottom, BSSpacing.xs)

            VStack(alignment: .leading, spacing: BSSpacing.sm) {
                Text(attributed)
                    .font(BSListeningTokens.body)
                    .lineSpacing(5)
                    .foregroundStyle(BSColor.Stage.foreground.opacity(0.92))
                    .lineLimit(isEditorialExpanded || !isLong ? nil : 4)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if isLong {
                    Button {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            isEditorialExpanded.toggle()
                        }
                    } label: {
                        Text(BSLocalization.text(isEditorialExpanded ? "收起" : "更多"))
                            .font(BSListeningTokens.caption.weight(.semibold))
                            .foregroundStyle(BSColor.Stage.accent)
                    }
                    .padding(.top, 2)
                }
            }
            .padding(BSSpacing.md)
            .background(
                BSColor.Stage.surface.opacity(0.62),
                in: RoundedRectangle(cornerRadius: BSRadius.md, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: BSRadius.md, style: .continuous)
                    .stroke(BSColor.Stage.border, lineWidth: BSListeningTokens.hairline)
            )
        }
    }

    private var footerSection: some View {
        let total = disc.tracks.compactMap(\.duration).reduce(0, +)
        return VStack(spacing: BSSpacing.xs) {
            if let releaseDate = disc.releaseDate {
                Text(releaseDate.formatted(date: .long, time: .omitted))
                    .font(BSListeningTokens.caption)
                    .foregroundStyle(BSColor.Stage.dim)
            }

            if !disc.tracks.isEmpty {
                let durationText = total > 0 ? "\(Int(total) / 60) \(BSLocalization.text("分钟"))" : nil
                let songsText = BSLocalization.format("%d 首歌曲", disc.tracks.count)
                let summary = [songsText, durationText].compactMap { $0 }.joined(separator: " · ")
                Text(summary)
                    .font(BSListeningTokens.caption)
                    .foregroundStyle(BSColor.Stage.dim)
            }

            if let copyright = disc.copyright, !copyright.isEmpty {
                Text(copyright)
                    .font(BSListeningTokens.caption)
                    .foregroundStyle(BSColor.Stage.dim)
                    .multilineTextAlignment(.center)
            } else if let label = disc.recordLabelName, !label.isEmpty {
                Text(label)
                    .font(BSListeningTokens.caption)
                    .foregroundStyle(BSColor.Stage.dim)
            }

            if let url = disc.appleMusicURL {
                Link(destination: url) {
                    HStack(spacing: BSSpacing.xs) {
                        Image(systemName: "applelogo")
                            .font(.system(size: 11, weight: .semibold))
                        Text(BSLocalization.text("在 Apple Music 上收听"))
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .font(BSListeningTokens.caption.weight(.semibold))
                    .foregroundStyle(BSColor.Stage.accent)
                    .padding(.top, BSSpacing.xs)
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
