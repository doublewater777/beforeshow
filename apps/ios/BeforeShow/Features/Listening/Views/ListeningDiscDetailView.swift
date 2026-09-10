import SwiftUI

struct ListeningDiscDetailView: View {
    @Bindable var room: ListeningRoomCoordinator
    let disc: ListeningDisc
    var onLoad: () -> Void = {}
    @Environment(\.dismiss) private var dismiss
    @State private var requestedSongID: String?

    private let isMultiArtist: Bool
    private let totalDurationText: String?
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
        if total > 0 {
            let mins = Int(total) / 60
            self.totalDurationText = "\(mins) \(BSLocalization.text("分钟"))"
        } else {
            self.totalDurationText = nil
        }

        var items: [String] = []
        if !disc.genreNames.isEmpty {
            items.append(disc.genreNames.joined(separator: " · "))
        }
        if let releaseDate = disc.releaseDate {
            items.append(releaseDate.formatted(.dateTime.year()))
        }
        items.append(BSLocalization.format("%d 首歌曲", disc.tracks.count))
        if total > 0 {
            let mins = Int(total) / 60
            items.append("\(mins) \(BSLocalization.text("分钟"))")
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

   private var albumBadges: [String] {
       var badges: [String] = []
        if room.access.authorizationStatus == .authorized {
            if room.access.canPlayCatalogContent {
                badges.append(BSLocalization.text("Apple Music 会员"))
            } else {
                badges.append(BSLocalization.text("30 秒试听"))
            }
        }
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
                    // 1. Hero Showcase: 144pt Artwork Jacket with Peeking Holographic Disc
                    heroSection

                    // 2. Action Area (Primary Load CTA or Loaded Playback Bar)
                    actionSection

                    // 3. Audio Quality Badges (Apple Music style)
                    if !albumBadges.isEmpty {
                        badgeSection
                    }

                    if let error = room.playbackError {
                        Text(error).font(BSListeningTokens.caption).foregroundStyle(BSColor.Stage.danger)
                    }

                    // 4. Tracklist Section
                    trackListSection

                    // 5. Editorial Notes (关于此专辑)
                    if let editorial = disc.editorialText, !editorial.isEmpty {
                        editorialSection(editorial)
                    }

                    // 6. Metadata Footer (Release, Label, Copyright, Link)
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
            if let songID, songID == requestedSongID { finishSelection() }
        }
    }

    // MARK: - Hero Section

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
            .frame(width: 144 + 46, height: 144, alignment: .leading)
            .padding(.top, BSSpacing.xs)

            VStack(spacing: 6) {
                Text(disc.title)
                    .font(.system(size: 24, weight: .bold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(BSColor.Stage.foreground)

                // Only display artist names if multi-artist compilation
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

    // MARK: - Action Section

    @ViewBuilder
    private var actionSection: some View {
        if isLoaded {
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
                                .lineLimit(1)
                        }
                    }
                }
                Spacer()
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
            .padding(.horizontal, BSSpacing.md)
            .padding(.vertical, 12)
            .background(BSColor.Stage.surfaceRaised.opacity(0.85), in: RoundedRectangle(cornerRadius: BSRadius.md, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: BSRadius.md, style: .continuous).stroke(BSColor.Stage.border, lineWidth: 1))
        } else {
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
            .disabled(room.busy || disc.tracks.isEmpty)
            .accessibilityIdentifier("listening.loadDisc")
        }
    }

    // MARK: - Badges Section

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

    // MARK: - Tracklist Section

    private var trackListSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(BSLocalization.text("TRACKLIST"))
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .tracking(2)
                    .foregroundStyle(BSColor.Stage.dim)
                Spacer()
                Text(BSLocalization.text("COMPACT DISC"))
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .tracking(1.5)
                    .foregroundStyle(BSColor.Stage.dim.opacity(0.7))
            }
            .padding(.horizontal, BSSpacing.md)
            .padding(.vertical, 10)
            .background(Color.white.opacity(0.03))

           LazyVStack(spacing: 0) {
               ForEach(Array(disc.tracks.enumerated()), id: \.element.id) { index, track in
                   let isCurrentPlaying = isLoaded && room.track?.id == track.id
                   ListeningDiscTrackRow(
                       index: index,
                       track: track,
                       isCurrentPlaying: isCurrentPlaying,
                       isPlaying: room.isPlaying,
                       isMultiArtist: isMultiArtist,
                       isPlayable: !room.busy && ListeningPlaybackSourceResolver.resolve(capability: room.capability(for: track)) != nil,
                       onSelect: {
                           requestedSongID = track.id
                           room.playFromSleeve(disc, songID: track.id)
                           if room.sleevePlaybackSongID == track.id { finishSelection() }
                       }
                   )

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

    // MARK: - Editorial Section

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

    // MARK: - Footer Section

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

    // MARK: - Helpers

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
        room.loadDisc(disc)
        dismiss()
        onLoad()
    }
    private func finishSelection() {
        requestedSongID = nil
        dismiss()
        onLoad()
    }
}

private struct ListeningDiscTrackRow: View {
    let index: Int
    let track: ListeningDiscTrack
    let isCurrentPlaying: Bool
    let isPlaying: Bool
    let isMultiArtist: Bool
    let isPlayable: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .center, spacing: BSSpacing.compact) {
                Group {
                    if isCurrentPlaying {
                        Image(systemName: isPlaying ? "speaker.wave.2.fill" : "speaker.fill")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(BSColor.Stage.accent)
                    } else {
                        Text(String(format: "%02d", index + 1))
                            .font(.system(size: 13, weight: .medium, design: .monospaced))
                            .foregroundStyle(BSColor.Stage.dim)
                    }
                }
                .frame(width: 24, alignment: .leading)

                VStack(alignment: .leading, spacing: 2) {
                    Text(track.title)
                        .font(BSFont.body)
                        .foregroundStyle(isCurrentPlaying ? BSColor.Stage.accent : BSColor.Stage.foreground)
                        .lineLimit(1)
                    if isMultiArtist {
                        Text(track.artistName)
                            .font(BSFont.caption)
                            .foregroundStyle(BSColor.Stage.muted)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: BSSpacing.sm)

                if let duration = track.duration, duration.isFinite, duration > 0 {
                    Text(Duration.seconds(duration).formatted(.time(pattern: .minuteSecond)))
                        .font(.system(size: 12, weight: .regular, design: .monospaced))
                        .foregroundStyle(BSColor.Stage.dim)
                }
            }
            .padding(.horizontal, BSSpacing.md)
            .padding(.vertical, 12)
            .background(isCurrentPlaying ? BSColor.Stage.accent.opacity(0.12) : Color.clear)
            .contentShape(Rectangle())
            .accessibilityElement(children: .combine)
        }
        .buttonStyle(.plain)
        .disabled(!isPlayable)
        .accessibilityIdentifier("listening.track.\(track.id)")
    }
}

