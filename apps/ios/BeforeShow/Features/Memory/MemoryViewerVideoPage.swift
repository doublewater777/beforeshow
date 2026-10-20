import AVFoundation
import AVKit
import PostHog
import SwiftUI

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
        // 用户录制的视频同样要遮回来（replay 已关掉全图遮罩）。
        .bsMaskUserContent()
        .onAppear { updatePlayer() }
        .onChange(of: isActive) { _, _ in updatePlayer() }
        .onChange(of: url) { _, _ in
            releasePlayer()
            updatePlayer()
        }
        // When the whole viewer disappears, let SwiftUI/AVKit dismantle its
        // controller before ARC releases the player state. Pausing is enough.
        .onDisappear { player?.pause() }
        .onReceive(NotificationCenter.default.publisher(for: AppAudioSession.focusDidChange)) { notification in
            if AppAudioSession.takesFocus(notification, from: .memoryVideo) { player?.pause() }
        }
    }

    private func updatePlayer() {
        if isActive {
            if player == nil {
                player = AVPlayer(url: url)
            }
            AppAudioSession.claimFocus(.memoryVideo)
            player?.play()
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
