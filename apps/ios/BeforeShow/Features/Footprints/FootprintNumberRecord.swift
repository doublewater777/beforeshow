import SwiftUI

/// Plays one number song at a time, on the same preview player as 听.
@MainActor
@Observable
final class FootprintNumberSongPlayer {
    static let shared = FootprintNumberSongPlayer()

    private let player = PreviewListeningPlaybackService(owner: .footprintSong)
    private(set) var currentNumber: Int?
    private(set) var loadingNumber: Int?
    private(set) var failedNumber: Int?
    private(set) var previews: [Int: SongPreview] = [:]

    func isPlaying(_ number: Int) -> Bool {
        currentNumber == number && player.phase.isActive
    }

    var elapsed: TimeInterval { player.currentTime }

    func toggle(_ song: FootprintNumberSong) async {
        if isPlaying(song.number) {
            player.pause()
            return
        }
        failedNumber = nil
        loadingNumber = song.number
        defer { loadingNumber = nil }
        let found: SongPreview?
        if let cached = previews[song.number] {
            found = cached
        } else {
            found = await SongPreviewLookup.shared.preview(title: song.title, artist: song.artist)
        }
        guard let preview = found else {
            failedNumber = song.number
            return
        }
        previews[song.number] = preview
        do {
            try await player.load([ListeningPlaybackItem(
                songID: String(preview.trackID),
                duration: 30,
                previewURL: preview.previewURL,
                title: preview.title,
                artistName: preview.artist,
                artworkURL: preview.artworkURL
            )], startingAt: nil, at: 0)
            currentNumber = song.number
            try await player.play()
        } catch {
            failedNumber = song.number
        }
    }

    func stop(_ number: Int) {
        guard currentNumber == number else { return }
        player.stop()
        currentNumber = nil
    }
}

/// A small record whose label is the number; tap to drop the needle on its song.
struct FootprintNumberRecord: View {
    let song: FootprintNumberSong
    var diameter: CGFloat = 64

    @State private var controller = FootprintNumberSongPlayer.shared
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isPlaying: Bool { controller.isPlaying(song.number) }

    var body: some View {
        HStack(spacing: 14) {
            Button {
                if !isPlaying { FootprintSoundPlayer.shared.play(.needle) }
                Task { await controller.toggle(song) }
            } label: { disc }
                .buttonStyle(.plain)
                .accessibilityLabel(isPlaying
                    ? BSLocalization.format("暂停 %@", song.title)
                    : BSLocalization.format("试听 %@", song.title))
            VStack(alignment: .leading, spacing: 3) {
                Text(song.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(BSColor.Stage.foreground)
                    .lineLimit(1)
                Text(song.artist)
                    .font(.system(size: 12))
                    .foregroundStyle(BSColor.Stage.muted)
                    .lineLimit(1)
                status
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
        .onDisappear { controller.stop(song.number) }
    }

    private var disc: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !isPlaying || reduceMotion)) { context in
            let angle = isPlaying && !reduceMotion ? context.date.timeIntervalSinceReferenceDate * 200 : 0
            ZStack {
                Circle().fill(FootprintRoomPalette.vinyl)
                ForEach(1..<4, id: \.self) { ring in
                    Circle()
                        .stroke(FootprintRoomPalette.groove, lineWidth: 0.8)
                        .padding(diameter * (0.08 + CGFloat(ring) * 0.07))
                }
                Circle()
                    .fill(BSColor.Stage.accent)
                    .frame(width: diameter * 0.4, height: diameter * 0.4)
                    .overlay {
                        Text(String(song.number))
                            .font(.system(size: diameter * 0.16, weight: .black).width(.compressed))
                            .foregroundStyle(FootprintRoomPalette.marqueeInk)
                    }
                // Sheen stays put while the record turns underneath it.
                Circle()
                    .fill(AngularGradient(colors: [.clear, .white.opacity(0.12), .clear, .white.opacity(0.08), .clear], center: .center))
                    .rotationEffect(.degrees(-angle))
            }
            .frame(width: diameter, height: diameter)
            .rotationEffect(.degrees(angle))
            .shadow(color: .black.opacity(0.6), radius: 8, y: 6)
        }
    }

    @ViewBuilder
    private var status: some View {
        Group {
            if controller.loadingNumber == song.number {
                Text(BSLocalization.text("正在准备…"))
            } else if controller.failedNumber == song.number {
                Text(BSLocalization.text("暂时无法播放"))
            } else if isPlaying {
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
