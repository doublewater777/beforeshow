import SwiftUI

/// Plays one number song at a time. With 听 available the song goes on the shared deck like any
/// record: the mini player shows it, it keeps going after you leave footprints, and subscribers hear
/// the whole song. Without a current show it falls back to a 30-second preview here.
@MainActor
@Observable
final class FootprintNumberSongPlayer {
    static let shared = FootprintNumberSongPlayer()

    private let player: any ListeningPlaybackServicing
    @ObservationIgnored private let lookup: @Sendable ([Int]) async -> [Int: SongPreview]
    @ObservationIgnored private let roomProvider: @MainActor () async -> ListeningRoomCoordinator?
    private(set) var currentNumber: Int?
    private(set) var loadingNumber: Int?
    private(set) var failedNumber: Int?
    /// Keyed by record number.
    private(set) var previews: [Int: SongPreview] = [:]
    /// The deck the songs went to, once one did.
    private(set) var room: ListeningRoomCoordinator?
    /// The deck itself, even before this session sent a song to it (a record restored after relaunch).
    private var deckRoom: ListeningRoomCoordinator? { room ?? ListeningRoomSessionStore.shared.room }
    /// Bumped by every tap and stop; a request that is no longer the latest never plays.
    private var request = 0

    init(
        player: any ListeningPlaybackServicing = PreviewListeningPlaybackService(owner: .footprintSong),
        lookup: @escaping @Sendable ([Int]) async -> [Int: SongPreview] = { await SongPreviewLookup.shared.previews(for: $0) },
        roomProvider: @escaping @MainActor () async -> ListeningRoomCoordinator? = { await ListeningIntentHandler.shared.roomForPlayback() }
    ) {
        self.player = player
        self.lookup = lookup
        self.roomProvider = roomProvider
    }

    static func discID(_ number: Int) -> String { "footprint-number-\(number)" }

    /// The song as a one-track record for the deck.
    static func disc(for song: FootprintNumberSong, preview: SongPreview) -> ListeningDisc {
        let track = ListeningDiscTrack(CatalogSong(
            appleMusicSongID: String(preview.trackID),
            title: preview.title,
            artistName: preview.artist,
            albumTitle: preview.album,
            artworkURL: preview.artworkURL?.absoluteString,
            duration: preview.duration,
            previewURL: preview.previewURL.absoluteString
        ))
        return ListeningDisc(
            id: discID(song.number),
            title: preview.title,
            artworkURL: preview.artworkURL,
            tracks: [track],
            artistNames: [preview.artist],
            appleMusicURL: preview.storeURL
        )
    }

    private func isOnDeck(_ number: Int) -> Bool {
        deckRoom?.loadedDisc?.id == Self.discID(number)
    }

    func isPlaying(_ number: Int) -> Bool {
        if isOnDeck(number) { return deckRoom?.isPlaying == true }
        return currentNumber == number && player.phase.isActive
    }

    /// Paused partway through: tapping again picks up from here.
    func isPaused(_ number: Int) -> Bool {
        if isOnDeck(number) { return deckRoom?.wantsPlayback == false }
        return currentNumber == number && !player.phase.isActive && !player.hasEnded
    }

    /// Fetching the song, or the deck has it but sound hasn't started yet.
    func isPreparing(_ number: Int) -> Bool {
        if loadingNumber == number { return true }
        return isOnDeck(number) && deckRoom?.wantsPlayback == true && deckRoom?.isPlaying == false
    }

    /// The preview played through; its owner lets the audio go.
    var hasFinished: Bool { currentNumber != nil && player.hasEnded }

    var elapsed: TimeInterval { player.currentTime }

    /// Whether the song is on the full player (no 30-second cap to show).
    func isOnSharedDeck(_ number: Int) -> Bool { isOnDeck(number) }

    /// Fetches covers and details for many records in one request.
    func load(_ songs: [FootprintNumberSong]) async {
        let missing = songs.filter { previews[$0.number] == nil }
        guard !missing.isEmpty else { return }
        let found = await lookup(missing.map(\.trackID))
        for song in missing {
            if let preview = found[song.trackID] { previews[song.number] = preview }
        }
    }

    /// Plays this record; one already playing just keeps going (opening its card never pauses it).
    func start(_ song: FootprintNumberSong) async {
        if isOnDeck(song.number), let room = deckRoom {
            if !room.wantsPlayback { room.playPause() }
            return
        }
        guard !isPlaying(song.number), loadingNumber != song.number else { return }
        await toggle(song)
    }

    func toggle(_ song: FootprintNumberSong) async {
        if loadingNumber == song.number {
            stop(song.number)
            return
        }
        if isOnDeck(song.number), let room = deckRoom {
            room.playPause()
            return
        }
        if isPlaying(song.number) {
            player.pause()
            return
        }
        request += 1
        let mine = request
        failedNumber = nil
        if isPaused(song.number) {
            do { try await player.play() } catch { if mine == request { failedNumber = song.number } }
            return
        }
        loadingNumber = song.number
        defer { if mine == request { loadingNumber = nil } }
        await load([song])
        guard mine == request else { return }
        guard let preview = previews[song.number] else {
            failedNumber = song.number
            return
        }
        if let room = await roomProvider() {
            guard mine == request else { return }
            self.room = room
            player.stop()
            currentNumber = nil
            if room.loadedDisc?.id == Self.discID(song.number) {
                if !room.wantsPlayback { room.playPause() }
            } else {
                ListeningCutIn.play(Self.disc(for: song, preview: preview), over: room)
            }
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

    /// Stops this record's preview or pending fetch. A song on the shared deck keeps playing:
    /// leaving footprints doesn't end it, the mini player does.
    func stop(_ number: Int) {
        guard currentNumber == number || loadingNumber == number else { return }
        request += 1
        loadingNumber = nil
        player.stop()
        currentNumber = nil
    }

    /// Stops whatever preview is playing or being fetched.
    func stopAll() {
        if let number = currentNumber ?? loadingNumber { stop(number) }
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
                Task { await controller.toggle(song) }
            } label: {
                FootprintNumberDisc(number: song.number, diameter: diameter, isPlaying: isPlaying, artworkURL: controller.previews[song.number]?.artworkURL)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isPlaying
                ? BSLocalization.format("暂停 %@", song.title)
                : BSLocalization.format("播放 %@", song.title))
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
        .onChange(of: controller.hasFinished) { _, finished in
            if finished { controller.stop(song.number) }
        }
        .onDisappear { controller.stop(song.number) }
    }
}

/// Preparing, playing time, or what tapping will do.
struct FootprintNumberSongStatus: View {
    let number: Int
    @State private var controller = FootprintNumberSongPlayer.shared

    var body: some View {
        Group {
            if controller.isPreparing(number) {
                Text(BSLocalization.text("正在准备…"))
            } else if controller.failedNumber == number {
                Text(BSLocalization.text("暂时无法播放"))
            } else if controller.isOnSharedDeck(number) {
                Text(BSLocalization.text(controller.isPlaying(number) ? "正在播放" : "已暂停"))
                    .foregroundStyle(controller.isPlaying(number) ? BSColor.Stage.accent : BSColor.Stage.dim)
            } else if controller.isPaused(number) {
                Text(String(format: "0:%02d / 0:30", min(30, Int(controller.elapsed))))
            } else if controller.isPlaying(number) {
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    Text(String(format: "0:%02d / 0:30", min(30, Int(controller.elapsed))))
                        .foregroundStyle(BSColor.Stage.accent)
                }
            } else {
                Text(BSLocalization.text("点唱片播放"))
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
    /// Where the record came to rest, and when it last started turning from there.
    @State private var restingAngle: Double = 0
    @State private var spinningSince: Date?

    /// 33⅓ rpm.
    private static let degreesPerSecond: Double = 200

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: spinningSince == nil)) { context in
            // Kept small and continuous: picks up where it stopped, holds still when paused.
            let angle = spinningSince.map {
                (restingAngle + context.date.timeIntervalSince($0) * Self.degreesPerSecond).truncatingRemainder(dividingBy: 360)
            } ?? restingAngle
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
        .onAppear { setSpinning(isPlaying) }
        .onChange(of: isPlaying) { _, playing in setSpinning(playing) }
    }

    private func setSpinning(_ playing: Bool) {
        let spin = playing && !reduceMotion
        if spin, spinningSince == nil {
            spinningSince = Date()
        } else if !spin, let since = spinningSince {
            restingAngle = (restingAngle + Date().timeIntervalSince(since) * Self.degreesPerSecond).truncatingRemainder(dividingBy: 360)
            spinningSince = nil
        }
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
