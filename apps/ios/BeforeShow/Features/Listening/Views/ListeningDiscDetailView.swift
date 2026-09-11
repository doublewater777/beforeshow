import SwiftUI

struct ListeningDiscDetailView: View {
    @Bindable var room: ListeningRoomCoordinator
    let disc: ListeningDisc
    var onLoad: () -> Void = {}
    @Environment(\.dismiss) private var dismiss
    @State private var requestedTrackID: String?

    private let isMultiArtist: Bool
    private let metadataSummary: String
    private let artistsSummary: String

    init(room: ListeningRoomCoordinator, disc: ListeningDisc, onLoad: @escaping () -> Void = {}) {
        self.room = room
        self.disc = disc
        self.onLoad = onLoad

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

        if multi {
            self.artistsSummary = disc.artistNames.isEmpty
                ? Array(Set(disc.tracks.map(\.artistName))).sorted().joined(separator: " / ")
                : disc.artistNames.joined(separator: " / ")
        } else {
            self.artistsSummary = ""
        }
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
                    heroSection
                    actionSection

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
            .background(BSColor.Stage.background)
            .foregroundStyle(BSColor.Stage.foreground)
            .navigationTitle(BSLocalization.text("专辑详情"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                BSChromeToolbarCloseButton { dismiss() }
            }
        }
        .tint(BSColor.Stage.accent)
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

    private var heroSection: some View {
        VStack(spacing: BSSpacing.md) {
            ZStack(alignment: .leading) {
                ListeningPeekingDisc(disc: disc, size: 132)
                    .offset(x: 144 - 132 + 46)
                    .opacity(isLoaded ? 0 : 1)
                    .scaleEffect(isLoaded ? 0.75 : 1.0)
                    .animation(.spring(response: 0.38, dampingFraction: 0.72), value: isLoaded)

                ListeningDiscCover(disc: disc, show: room.show)
                    .frame(width: 144, height: 144)
                    .shadow(color: Color.black.opacity(0.75), radius: 18, x: 2, y: 10)
                    .overlay {
                        LinearGradient(
                            stops: [
                                .init(color: Color.white.opacity(0.18), location: 0.0),
                                .init(color: Color.white.opacity(0.0), location: 0.35),
                                .init(color: Color.black.opacity(0.40), location: 1.0)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        .clipShape(RoundedRectangle(cornerRadius: BSRadius.md, style: .continuous))
                        .allowsHitTesting(false)
                    }
            }
            .frame(width: 190, height: 144, alignment: .leading)
            .padding(.top, BSSpacing.xs)

            VStack(spacing: 6) {
                Text(disc.title)
                    .font(.system(size: 24, weight: .bold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(BSColor.Stage.foreground)
                    .fixedSize(horizontal: false, vertical: true)

                if isMultiArtist && !artistsSummary.isEmpty {
                    Text(artistsSummary)
                        .font(BSFont.body)
                        .foregroundStyle(BSColor.Stage.accent)
                        .multilineTextAlignment(.center)
                }

                Text(metadataSummary)
                    .font(BSFont.caption)
                    .foregroundStyle(BSColor.Stage.muted)
                    .multilineTextAlignment(.center)
                    .padding(.top, 2)
                ListeningSleeveMarks(room: room, disc: disc)
            }
        }
    }

    @ViewBuilder
    private var actionSection: some View {
        if isLoaded {
            loadedActionSection
        } else {
            switch presentation.primaryAction {
            case .load:
                Button(action: load) {
                    HStack(spacing: BSSpacing.sm) {
                        Image(systemName: "opticaldisc")
                            .font(.system(size: 17, weight: .semibold))
                        Text(BSLocalization.text("装入播放机"))
                            .font(BSFont.headline)
                    }
                    .foregroundStyle(Color.black)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(BSColor.Stage.accent, in: RoundedRectangle(cornerRadius: BSRadius.md, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: BSRadius.md, style: .continuous)
                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                    )
                }
                .buttonStyle(BSListeningPressStyle(scale: 0.97))
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

    private var loadedActionSection: some View {
        let player = room.display.player
        return VStack(spacing: BSSpacing.sm) {
            HStack(spacing: BSSpacing.md) {
                HStack(spacing: BSSpacing.sm) {
                    Image(systemName: room.isPlaying ? "waveform" : "opticaldisc")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(BSColor.Stage.accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(BSLocalization.text(room.isPlaying ? "正在播放中" : "已在播放机中"))
                            .font(BSFont.headline)
                            .foregroundStyle(BSColor.Stage.foreground)
                        if let track = room.track {
                            Text(track.title)
                                .font(BSFont.caption)
                                .foregroundStyle(BSColor.Stage.muted)
                                .lineLimit(2)
                        }
                        Text(player.statusText)
                            .font(BSFont.caption)
                            .foregroundStyle(player.phase == .failed ? BSColor.Stage.danger : BSColor.Stage.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: BSSpacing.sm)
                if player.canPlayPause {
                    Button {
                        room.perform(.playPause)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: room.isPlaying ? "pause.fill" : "play.fill")
                            Text(BSLocalization.text(room.isPlaying ? "暂停" : "播放"))
                        }
                        .font(BSFont.caption.weight(.semibold))
                        .foregroundStyle(Color.black)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(BSColor.Stage.accent, in: Capsule())
                    }
                    .buttonStyle(BSListeningPressStyle(scale: 0.95))
                }
            }

            if let recovery = player.recoveryAction {
                Button(recovery.title) {
                    room.performListeningRecovery(recovery)
                }
                .font(BSFont.caption.weight(.semibold))
                .foregroundStyle(BSColor.Stage.accent)
                .frame(minHeight: BSLayout.minTouchTarget)
            }

            if !player.canPlayPause,
               case .metadataOnly = presentation.capability,
               let url = disc.appleMusicURL {
                appleMusicPrimaryAction(url)
            }
        }
        .padding(.horizontal, BSSpacing.md)
        .padding(.vertical, 12)
        .background(BSColor.Stage.surfaceRaised.opacity(0.85), in: RoundedRectangle(cornerRadius: BSRadius.md, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: BSRadius.md, style: .continuous).stroke(BSColor.Stage.border, lineWidth: 1))
    }

    private func capabilityNotice(_ text: String) -> some View {
        HStack(spacing: BSSpacing.sm) {
            Image(systemName: "info.circle")
                .foregroundStyle(BSColor.Stage.muted)
            Text(text)
                .font(BSFont.body)
                .foregroundStyle(BSColor.Stage.muted)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 50)
        .padding(.horizontal, BSSpacing.md)
        .background(BSColor.Stage.surfaceRaised.opacity(0.75), in: RoundedRectangle(cornerRadius: BSRadius.md, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func appleMusicPrimaryAction(_ url: URL) -> some View {
        Link(destination: url) {
            HStack(spacing: BSSpacing.sm) {
                Image(systemName: "music.note")
                Text(BSLocalization.text("在 Apple Music 中打开"))
                    .font(BSFont.headline)
                Image(systemName: "arrow.up.right.square")
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(Color.black)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(BSColor.Stage.accent, in: RoundedRectangle(cornerRadius: BSRadius.md, style: .continuous))
        }
        .buttonStyle(BSListeningPressStyle(scale: 0.97))
        .accessibilityIdentifier("listening.openAppleMusic")
    }

    private var badgeSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: BSSpacing.xs) {
                ForEach(albumBadges, id: \.self) { badge in
                    Text(badge)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(BSColor.Stage.muted)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(BSColor.Stage.surfaceRaised.opacity(0.7), in: Capsule())
                        .overlay(Capsule().stroke(BSColor.Stage.border, lineWidth: 0.75))
                }
            }
        }
    }

    private var trackListSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(BSLocalization.text("TRACKLIST"))
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .tracking(2)
                    .foregroundStyle(BSColor.Stage.dim)
                Spacer()
                Text(trackListStatusText)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .tracking(1.2)
                    .foregroundStyle(BSColor.Stage.dim.opacity(0.7))
            }
            .padding(.horizontal, BSSpacing.md)
            .padding(.vertical, 10)
            .background(Color.white.opacity(0.03))

            LazyVStack(spacing: 0) {
                ForEach(Array(disc.tracks.enumerated()), id: \.element.id) { index, track in
                    trackRow(index: index, track: track)

                    Divider()
                        .overlay(BSColor.Stage.border)
                        .accessibilityHidden(true)
                }
            }
        }
        .background(BSColor.Stage.surfaceRaised.opacity(0.55), in: RoundedRectangle(cornerRadius: BSRadius.md, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: BSRadius.md, style: .continuous).stroke(Color.white.opacity(0.07), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: BSRadius.md, style: .continuous))
    }

    private var trackListStatusText: String {
        if case .previewOnly = presentation.capability {
            return presentation.statusText
        }
        return BSLocalization.text("COMPACT DISC")
    }

    @ViewBuilder
    private func trackRow(index: Int, track: ListeningDiscTrack) -> some View {
        let trackPresentation = room.display.trackPresentation(for: track)
        let state = trackRowState(for: track, isPlayable: trackPresentation.isPlayable)
        let row = ListeningDiscTrackRow(
            index: index,
            track: track,
            state: state,
            isMultiArtist: isMultiArtist
        )

        if trackPresentation.isPlayable {
            Button {
                selectTrack(track)
            } label: {
                row
            }
            .buttonStyle(BSListeningPressStyle(scale: 0.985))
            .disabled(room.busy || room.mechanism.isAutomatic)
            .accessibilityValue(accessibilityValue(for: state, presentation: trackPresentation))
            .accessibilityIdentifier("listening.track.\(track.id)")
        } else {
            row
                .accessibilityValue(trackPresentation.statusText)
                .accessibilityIdentifier("listening.track.\(track.id)")
        }
    }

    private func trackRowState(for track: ListeningDiscTrack, isPlayable: Bool) -> ListeningDiscTrackRowState {
        guard isPlayable else { return .unavailable }
        if requestedTrackID == track.id { return .preparing }
        guard isLoaded, room.track?.id == track.id else { return .normal }

        switch room.display.player.phase {
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
        let trackPresentation = room.display.trackPresentation(for: track)
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
                .font(BSFont.caption.weight(.semibold))
                .foregroundStyle(BSColor.Stage.dim)
            Text(editorial)
                .font(BSFont.body)
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
                    .font(BSFont.caption)
                    .foregroundStyle(BSColor.Stage.dim)
            }
            if let label = disc.recordLabelName, !label.isEmpty {
                Text("\(BSLocalization.text("唱片公司")): \(label)")
                    .font(BSFont.caption)
                    .foregroundStyle(BSColor.Stage.dim)
            }
            if let copyright = disc.copyright, !copyright.isEmpty {
                Text(copyright)
                    .font(BSFont.caption)
                    .foregroundStyle(BSColor.Stage.dim)
                    .multilineTextAlignment(.center)
            }
            if let url = disc.appleMusicURL {
                Link(destination: url) {
                    HStack(spacing: 4) {
                        Text(BSLocalization.text("在 Apple Music 中打开"))
                        Image(systemName: "arrow.up.right.square")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .font(BSFont.caption.weight(.semibold))
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

private enum ListeningDiscTrackRowState: Equatable {
    case normal
    case preparing
    case playing
    case paused
    case unavailable

    var isActive: Bool {
        switch self {
        case .preparing, .playing, .paused:
            true
        case .normal, .unavailable:
            false
        }
    }
}

private struct ListeningDiscTrackRow: View {
    let index: Int
    let track: ListeningDiscTrack
    let state: ListeningDiscTrackRowState
    let isMultiArtist: Bool

    var body: some View {
        HStack(alignment: .center, spacing: BSSpacing.compact) {
            leadingIndicator
                .frame(width: 24, alignment: .leading)

            VStack(alignment: .leading, spacing: 3) {
                Text(track.title)
                    .font(BSFont.body)
                    .foregroundStyle(titleColor)
                    .lineLimit(2)
                if isMultiArtist {
                    Text(track.artistName)
                        .font(BSFont.caption)
                        .foregroundStyle(state == .unavailable ? BSColor.Stage.dim.opacity(0.55) : BSColor.Stage.muted)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: BSSpacing.sm)

            if let duration = track.duration, duration.isFinite, duration > 0 {
                Text(Duration.seconds(duration).formatted(.time(pattern: .minuteSecond)))
                    .font(.system(size: 12, weight: .regular, design: .monospaced))
                    .foregroundStyle(state == .unavailable ? BSColor.Stage.dim.opacity(0.45) : BSColor.Stage.dim)
            }
        }
        .frame(maxWidth: .infinity, minHeight: BSLayout.minTouchTarget, alignment: .leading)
        .padding(.horizontal, BSSpacing.md)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var leadingIndicator: some View {
        switch state {
        case .preparing, .playing:
            Image(systemName: "waveform")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(BSColor.Stage.accent)
        case .paused:
            Image(systemName: "play.fill")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(BSColor.Stage.accent)
        case .normal:
            trackNumber(color: BSColor.Stage.dim)
        case .unavailable:
            trackNumber(color: BSColor.Stage.dim.opacity(0.45))
        }
    }

    private var titleColor: Color {
        switch state {
        case .preparing, .playing, .paused:
            BSColor.Stage.accent
        case .normal:
            BSColor.Stage.foreground
        case .unavailable:
            BSColor.Stage.dim.opacity(0.55)
        }
    }

    private func trackNumber(color: Color) -> some View {
        Text(String(format: "%02d", index + 1))
            .font(.system(size: 13, weight: .medium, design: .monospaced))
            .foregroundStyle(color)
    }
}