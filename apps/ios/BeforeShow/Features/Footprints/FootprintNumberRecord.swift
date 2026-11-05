import SwiftUI

/// Plays one number song at a time, on the same preview player as 听,
/// and keeps what the store says about each record (cover, album, year).
@MainActor
@Observable
final class FootprintNumberSongPlayer {
    static let shared = FootprintNumberSongPlayer()

    private let player = PreviewListeningPlaybackService(owner: .footprintSong)
    private(set) var currentNumber: Int?
    private(set) var loadingNumber: Int?
    private(set) var failedNumber: Int?
    /// Keyed by record number.
    private(set) var previews: [Int: SongPreview] = [:]
    /// Bumped by every tap and stop; a request that is no longer the latest never plays.
    private var request = 0

    func isPlaying(_ number: Int) -> Bool {
        currentNumber == number && player.phase.isActive
    }

    var elapsed: TimeInterval { player.currentTime }

    /// Fetches covers and details for many records in one request.
    func load(_ songs: [FootprintNumberSong]) async {
        let missing = songs.filter { previews[$0.number] == nil }
        guard !missing.isEmpty else { return }
        let found = await SongPreviewLookup.shared.previews(for: missing.map(\.trackID))
        for song in missing {
            if let preview = found[song.trackID] { previews[song.number] = preview }
        }
    }

    func toggle(_ song: FootprintNumberSong) async {
        if isPlaying(song.number) {
            player.pause()
            return
        }
        request += 1
        let mine = request
        failedNumber = nil
        loadingNumber = song.number
        defer { if mine == request { loadingNumber = nil } }
        await load([song])
        guard mine == request else { return }
        guard let preview = previews[song.number] else {
            failedNumber = song.number
            return
        }
        do {
            try await player.load([ListeningPlaybackItem(
                songID: String(preview.trackID),
                duration: 30,
                previewURL: preview.previewURL,
                title: preview.title,
                artistName: preview.artist,
                albumTitle: preview.album,
                artworkURL: preview.artworkURL
            )], startingAt: nil, at: 0)
            guard mine == request else { return }
            currentNumber = song.number
            try await player.play()
        } catch {
            if mine == request { failedNumber = song.number }
        }
    }

    func stop(_ number: Int) {
        guard currentNumber == number else { return }
        request += 1
        player.stop()
        currentNumber = nil
    }
}

/// A record and its song, side by side; tap the record to drop the needle.
struct FootprintNumberRecord: View {
    let song: FootprintNumberSong
    var diameter: CGFloat = 64

    @State private var controller = FootprintNumberSongPlayer.shared
    @Environment(\.openURL) private var openURL

    private var isPlaying: Bool { controller.isPlaying(song.number) }

    var body: some View {
        HStack(spacing: 14) {
            Button {
                if !isPlaying { FootprintSoundPlayer.shared.play(.needle) }
                Task { await controller.toggle(song) }
            } label: {
                FootprintNumberDisc(number: song.number, diameter: diameter, isPlaying: isPlaying, artworkURL: controller.previews[song.number]?.artworkURL)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isPlaying
                ? BSLocalization.format("暂停 %@", song.title)
                : BSLocalization.format("试听 %@", song.title))
            VStack(alignment: .leading, spacing: 3) {
                Text(song.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(BSColor.Stage.foreground)
                    .lineLimit(1)
                Text(controller.previews[song.number]?.artist ?? song.artist)
                    .font(.system(size: 12))
                    .foregroundStyle(BSColor.Stage.muted)
                    .lineLimit(1)
                FootprintNumberSongStatus(number: song.number)
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .contextMenu {
            if let link = controller.previews[song.number]?.storeURL {
                Button(BSLocalization.text("在 Apple Music 中打开"), systemImage: "arrow.up.right") { openURL(link) }
            }
        }
        .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.6), trigger: isPlaying) { _, playing in playing }
        .task(id: song.number) { await controller.load([song]) }
        .onDisappear { controller.stop(song.number) }
    }
}

/// Preparing, playing time, or what tapping will do.
struct FootprintNumberSongStatus: View {
    let number: Int
    @State private var controller = FootprintNumberSongPlayer.shared

    var body: some View {
        Group {
            if controller.loadingNumber == number {
                Text(BSLocalization.text("正在准备…"))
            } else if controller.failedNumber == number {
                Text(BSLocalization.text("暂时无法播放"))
            } else if controller.isPlaying(number) {
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    Text(String(format: "0:%02d / 0:30", min(30, Int(controller.elapsed))))
                        .foregroundStyle(BSColor.Stage.accent)
                }
            } else {
                Text(BSLocalization.text("30 秒试听"))
            }
        }
        .font(.system(size: 11, design: .monospaced))
        .foregroundStyle(BSColor.Stage.dim)
        .padding(.top, 2)
    }
}

/// A record with the song's album cover on its label (its number until the cover arrives); it turns while playing.
struct FootprintNumberDisc: View {
    let number: Int
    let diameter: CGFloat
    let isPlaying: Bool
    var artworkURL: URL?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !isPlaying || reduceMotion)) { context in
            let angle = isPlaying && !reduceMotion ? context.date.timeIntervalSinceReferenceDate * 200 : 0
            ZStack {
                Circle().fill(FootprintRoomPalette.vinyl)
                ForEach(1..<4, id: \.self) { ring in
                    Circle()
                        .stroke(FootprintRoomPalette.groove, lineWidth: 0.8)
                        .padding(diameter * (0.06 + CGFloat(ring) * 0.05))
                }
                label
                    .frame(width: diameter * 0.56, height: diameter * 0.56)
                    .clipShape(Circle())
                    .overlay { Circle().fill(FootprintRoomPalette.vinyl).frame(width: diameter * 0.06, height: diameter * 0.06) }
                // Sheen stays put while the record turns underneath it.
                Circle()
                    .fill(AngularGradient(colors: [.clear, .white.opacity(0.12), .clear, .white.opacity(0.08), .clear], center: .center))
                    .rotationEffect(.degrees(-angle))
            }
            .frame(width: diameter, height: diameter)
            .rotationEffect(.degrees(angle))
            .shadow(color: .black.opacity(0.6), radius: 8, y: 6)
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var label: some View {
        if let artworkURL {
            ShowCoverImageView(urlString: artworkURL.absoluteString, aspectRatio: 1, contentMode: .fill, enforcesAspectRatio: false, cornerRadius: 0)
        } else {
            BSColor.Stage.accent
                .overlay {
                    Text(String(number))
                        .font(.system(size: diameter * 0.18, weight: .black).width(.compressed))
                        .foregroundStyle(FootprintRoomPalette.marqueeInk)
                }
        }
    }
}
