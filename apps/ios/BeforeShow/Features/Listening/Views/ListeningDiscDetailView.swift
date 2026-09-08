import SwiftUI

struct ListeningDiscDetailView: View {
    @Bindable var room: ListeningRoomCoordinator
    let disc: ListeningDisc
    var onLoad: () -> Void = {}
    @Environment(\.dismiss) private var dismiss

    private var isLoaded: Bool {
        room.mechanism.disc?.id == disc.id && room.mechanism.position != .stored
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: BSSpacing.lg) {
                    discHeroSection
                    albumInfoSection
                    if isLoaded {
                        loadedPlaybackBar
                    } else {
                        loadButton
                    }
                    trackSection
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
                ToolbarItem(placement: .confirmationAction) {
                    Button(BSLocalization.text("完成")) { dismiss() }
                        .font(BSFont.caption)
                        .foregroundStyle(BSColor.Stage.foreground)
                }
            }
        }
        .tint(BSColor.Stage.accent)
        .presentationDragIndicator(.visible)
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }

    // MARK: - Disc Hero

    private var totalAlbumDurationText: String? {
        let total = disc.tracks.compactMap(\.duration).reduce(0, +)
        guard total > 0 else { return nil }
        let mins = Int(total) / 60
        return "\(mins) \(BSLocalization.text("分钟"))"
    }

    private var discHeroSection: some View {
        HStack(spacing: BSSpacing.md) {
            ListeningSleeve(disc: disc, isLoaded: isLoaded)
                .frame(width: 92, height: 98)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                Text(disc.title)
                    .font(BSFont.headline)
                    .lineLimit(2)
                    .foregroundStyle(BSColor.Stage.foreground)

                let artists = (disc.artistNames.isEmpty
                    ? Array(Set(disc.tracks.map(\.artistName))).sorted()
                    : disc.artistNames
                ).joined(separator: " / ")
                if !artists.isEmpty {
                    Text(artists)
                        .font(BSFont.caption)
                        .foregroundStyle(BSColor.Stage.muted)
                        .lineLimit(1)
                }

                HStack(spacing: 8) {
                    Text("\(disc.tracks.count) \(BSLocalization.text("首歌曲"))")
                        .font(BSFont.V3.caption)
                        .foregroundStyle(BSColor.Stage.dim)

                    if let totalText = totalAlbumDurationText {
                        Text("·")
                            .font(BSFont.V3.caption)
                            .foregroundStyle(BSColor.Stage.dim)
                        Text(totalText)
                            .font(BSFont.V3.caption)
                            .foregroundStyle(BSColor.Stage.dim)
                    }

                    if isLoaded {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(BSColor.Stage.accent)
                                .frame(width: 6, height: 6)
                            Text(BSLocalization.text("当前装载"))
                                .font(BSFont.V3.caption)
                                .foregroundStyle(BSColor.Stage.accent)
                        }
                    }
                }
                .padding(.top, 2)
            }
            Spacer(minLength: 0)
        }
        .padding(BSSpacing.md)
        .background(BSColor.Stage.surfaceRaised.opacity(0.85), in: RoundedRectangle(cornerRadius: BSRadius.md))
        .overlay(RoundedRectangle(cornerRadius: BSRadius.md).stroke(BSColor.Stage.border, lineWidth: 1))
    }

    private var albumInfoSection: some View {
        VStack(alignment: .leading, spacing: BSSpacing.md) {
            if let editorialText = disc.editorialText, !editorialText.isEmpty {
                VStack(alignment: .leading, spacing: BSSpacing.xs) {
                    metadataHeading(BSLocalization.text("专辑简介"))
                    Text(editorialText)
                        .font(BSFont.body)
                        .foregroundStyle(BSColor.Stage.muted)
                        .lineSpacing(4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            let details = metadataRows
            if !details.isEmpty {
                VStack(spacing: 10) {
                    ForEach(details, id: \.title) { detail in
                        HStack(alignment: .firstTextBaseline, spacing: BSSpacing.md) {
                            Text(detail.title)
                                .font(BSFont.caption)
                                .foregroundStyle(BSColor.Stage.dim)
                                .frame(width: 68, alignment: .leading)
                            Text(detail.value)
                                .font(BSFont.body)
                                .foregroundStyle(BSColor.Stage.foreground)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }

            if !albumBadges.isEmpty {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 88), spacing: 6)], alignment: .leading, spacing: 6) {
                    ForEach(albumBadges, id: \.self) { badge in
                        Text(badge)
                            .font(BSFont.caption.weight(.medium))
                            .foregroundStyle(BSColor.Stage.muted)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(BSColor.Stage.surface, in: Capsule())
                    }
                }
            }

            if let url = disc.appleMusicURL {
                Link(destination: url) {
                    Label(BSLocalization.text("在 Apple Music 中打开"), systemImage: "arrow.up.right.square")
                        .font(BSFont.caption.weight(.semibold))
                }
                .tint(BSColor.Stage.accent)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(BSSpacing.md)
        .background(BSColor.Stage.surface.opacity(0.58), in: RoundedRectangle(cornerRadius: BSRadius.md))
        .overlay(RoundedRectangle(cornerRadius: BSRadius.md).stroke(BSColor.Stage.border, lineWidth: 1))
    }

    private var metadataRows: [(title: String, value: String)] {
        var rows: [(String, String)] = []
        if let releaseDate = disc.releaseDate {
            rows.append((BSLocalization.text("发行日期"), releaseDate.formatted(date: .long, time: .omitted)))
        }
        if !disc.genreNames.isEmpty {
            rows.append((BSLocalization.text("流派"), disc.genreNames.joined(separator: " · ")))
        }
        if let recordLabelName = disc.recordLabelName, !recordLabelName.isEmpty {
            rows.append((BSLocalization.text("唱片公司"), recordLabelName))
        }
        if let contentRating = contentRatingText {
            rows.append((BSLocalization.text("内容分级"), contentRating))
        }
        if let copyright = disc.copyright, !copyright.isEmpty {
            rows.append((BSLocalization.text("版权"), copyright))
        }
        return rows
    }

    private var albumBadges: [String] {
        var badges = disc.audioVariantRawValues.compactMap(audioVariantText)
        if disc.isAppleDigitalMaster == true { badges.append(BSLocalization.text("Apple Digital Master")) }
        if disc.isCompilation == true { badges.append(BSLocalization.text("合辑")) }
        if disc.isSingle == true { badges.append(BSLocalization.text("单曲")) }
        return badges
    }

    private var contentRatingText: String? {
        switch disc.contentRatingRawValue {
        case "explicit": BSLocalization.text("Explicit")
        case "clean": BSLocalization.text("Clean")
        default: nil
        }
    }

    private func audioVariantText(_ rawValue: String) -> String? {
        switch rawValue {
        case "dolbyAtmos": BSLocalization.text("杜比全景声")
        case "dolbyAudio": BSLocalization.text("杜比音效")
        case "lossless": BSLocalization.text("无损")
        case "highResolutionLossless": BSLocalization.text("高解析无损")
        case "lossyStereo": BSLocalization.text("立体声")
        case "spatialAudio": BSLocalization.text("空间音频")
        default: nil
        }
    }

    private func metadataHeading(_ title: String) -> some View {
        Text(title)
            .font(BSFont.caption.weight(.semibold))
            .foregroundStyle(BSColor.Stage.dim)
    }

    // MARK: - Loaded Playback Bar

    private var loadedPlaybackBar: some View {
        HStack(spacing: BSSpacing.compact) {
            Image(systemName: room.isPlaying ? "waveform" : "opticaldisc")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(BSColor.Stage.accent)
            Text(BSLocalization.text(room.isPlaying ? "正在播放中" : "已在播放机中"))
                .font(BSFont.headline)
                .foregroundStyle(BSColor.Stage.foreground)

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
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(BSColor.Stage.accent, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, BSSpacing.md)
        .padding(.vertical, 10)
        .background(BSColor.Stage.surfaceRaised.opacity(0.85), in: RoundedRectangle(cornerRadius: BSRadius.md))
        .overlay(RoundedRectangle(cornerRadius: BSRadius.md).stroke(BSColor.Stage.border, lineWidth: 1))
    }

    // MARK: - Load Button

    private var loadButton: some View {
        Button {
            room.loadDisc(disc, autoplay: true)
            dismiss()
            onLoad()
        } label: {
            HStack(spacing: BSSpacing.compact) {
                Image(systemName: "opticaldisc")
                    .font(.system(size: 15, weight: .semibold))
                Text(BSLocalization.text("装入 CD 播放"))
                    .font(BSFont.headline)
            }
            .foregroundStyle(Color.black)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(BSColor.Stage.accent, in: RoundedRectangle(cornerRadius: BSRadius.md))
        }
        .buttonStyle(.plain)
        .disabled(room.busy)
    }

    // MARK: - Tracks (Physical CD Rear Tray Card Style)

    private var trackSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Rear tray header bar
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

            // Realistic CD inlay tracklist lines
            VStack(spacing: 0) {
                ForEach(Array(disc.tracks.enumerated()), id: \.element.id) { index, track in
                    trackRow(index: index, track: track)
                }
            }
        }
        .background(BSColor.Stage.surfaceRaised.opacity(0.55), in: RoundedRectangle(cornerRadius: BSRadius.md))
        .overlay(RoundedRectangle(cornerRadius: BSRadius.md).stroke(Color.white.opacity(0.07), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: BSRadius.md))
    }

    private func trackRow(index: Int, track: ListeningDiscTrack) -> some View {
        let isCurrent = room.track?.id == track.id
        return Button {
            room.loadDisc(disc, songID: track.id, autoplay: true)
            dismiss()
            onLoad()
        } label: {
            HStack(alignment: .center, spacing: BSSpacing.compact) {
                // Track Index (Classic monospaced 01, 02)
                ZStack {
                    if isCurrent {
                        Image(systemName: "speaker.wave.2.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(BSColor.Stage.accent)
                    } else {
                        Text(String(format: "%02d", index + 1))
                            .font(.system(size: 13, weight: .medium, design: .monospaced))
                            .foregroundStyle(BSColor.Stage.dim)
                    }
                }
                .frame(width: 24, alignment: .leading)

                // Track Title Only
                Text(track.title)
                    .font(BSFont.body)
                    .foregroundStyle(isCurrent ? BSColor.Stage.accent : BSColor.Stage.foreground)
                    .lineLimit(1)

                Spacer(minLength: 8)

                // Duration (e.g. 3:45)
                if let duration = track.duration, duration > 0 {
                    Text(formatDuration(duration))
                        .font(.system(size: 12, weight: .regular, design: .monospaced))
                        .foregroundStyle(BSColor.Stage.dim)
                }
            }
            .padding(.horizontal, BSSpacing.md)
            .padding(.vertical, 11)
            .background(isCurrent ? BSColor.Stage.accent.opacity(0.12) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
