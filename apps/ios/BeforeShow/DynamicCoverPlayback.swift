import AVFoundation
import AVKit
import SwiftUI
import UIKit

/// App-wide audio session policy.
///
/// iOS defaults to `soloAmbient`, which interrupts other audio as soon as an
/// `AVPlayer` with an audio track starts — `isMuted` only zeroes the output, it
/// does not stop the session from activating. Dynamic covers are decorative and
/// muted, so the app stays on `ambient` + `mixWithOthers` and never stops the
/// user's music. Views that intentionally play sound switch to `playback` while
/// they are on screen.
enum AppAudioSession {
    static func configureAmbient() {
        try? AVAudioSession.sharedInstance().setCategory(
            .ambient,
            mode: .default,
            options: [.mixWithOthers]
        )
    }

    static func configureSoundPlayback() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
    }
}

/// A borderless, muted AVPlayer surface used by dynamic covers.
struct DynamicCoverPlaybackView: UIViewRepresentable {
    let url: URL
    let isPlaying: Bool
    var muted = true

    func makeUIView(context: Context) -> DynamicCoverPlayerView {
        DynamicCoverPlayerView()
    }

    func updateUIView(_ view: DynamicCoverPlayerView, context: Context) {
        view.configure(url: url, isPlaying: isPlaying, muted: muted)
    }

    static func dismantleUIView(_ view: DynamicCoverPlayerView, coordinator: ()) {
        view.stop()
    }
}

/// Full-screen memory video page. Only the selected page owns an AVPlayer;
/// adjacent TabView pages stay inert and release decoder resources immediately.
struct MemoryViewerVideoPage: View {
    let url: URL
    let isActive: Bool

    @State private var player: AVPlayer?

    var body: some View {
        Group {
            // Drive AVKit teardown from the page-selection state first. Clearing
            // the player while VideoPlayer is still mounted can race the backing
            // AVPlayerViewController teardown and crash when a memory video opens
            // or a paged viewer changes selection.
            if isActive, let player {
                VideoPlayer(player: player)
            } else {
                Color.black
            }
        }
        .onAppear { updatePlayer() }
        .onChange(of: isActive) { _, _ in updatePlayer() }
        .onChange(of: url) { _, _ in
            releasePlayer()
            updatePlayer()
        }
        // When the whole viewer disappears, let SwiftUI/AVKit dismantle its
        // controller before ARC releases the player state. Pausing is enough.
        .onDisappear { player?.pause() }
    }

    private func updatePlayer() {
        if isActive {
            if player == nil {
                player = AVPlayer(url: url)
            }
        } else {
            releasePlayer()
        }
    }

    private func releasePlayer() {
        player?.pause()
        // Do not mutate currentItem while an AVPlayerViewController may still be
        // dismantling. Dropping our reference is sufficient once the page is no
        // longer rendering VideoPlayer.
        player = nil
    }
}

@MainActor
final class DynamicCoverPlayerView: UIView {
    private let player = AVPlayer()
    private var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    private var endObserver: NSObjectProtocol?
    private var loadedURL: URL?

    override class var layerClass: AnyClass { AVPlayerLayer.self }

    override init(frame: CGRect) {
        super.init(frame: frame)
        playerLayer.player = player
        playerLayer.videoGravity = .resizeAspectFill
        backgroundColor = .black
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(url: URL, isPlaying: Bool, muted: Bool) {
        player.isMuted = muted
        if loadedURL != url {
            loadedURL = url
            removeEndObserver()
            player.replaceCurrentItem(with: AVPlayerItem(url: url))
            endObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: player.currentItem,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.player.seek(to: .zero)
                    if self?.isPlayingRequested == true {
                        self?.player.play()
                    }
                }
            }
        }
        isPlayingRequested = isPlaying
        if isPlaying {
            player.play()
        } else {
            player.pause()
        }
    }

    func stop() {
        isPlayingRequested = false
        player.pause()
        removeEndObserver()
        player.replaceCurrentItem(with: nil)
        loadedURL = nil
    }

    private var isPlayingRequested = false

    private func removeEndObserver() {
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
    }

}
