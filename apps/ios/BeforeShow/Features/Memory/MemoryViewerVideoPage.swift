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
    @State private var holdsListening = false

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
        .onDisappear {
            player?.pause()
            letGoOfListening()
        }
        .onReceive(NotificationCenter.default.publisher(for: AppAudioSession.focusDidChange)) { notification in
            if AppAudioSession.takesFocus(notification, from: .memoryVideo) { player?.pause() }
        }
    }

    private func updatePlayer() {
        if isActive {
            if player == nil {
                player = AVPlayer(url: url)
            }
            if !holdsListening {
                holdsListening = true
                MemoryVideoListeningHandoff.begin()
            }
            AppAudioSession.claimFocus(.memoryVideo)
            player?.play()
        } else {
            letGoOfListening()
            releasePlayer()
        }
    }

    private func letGoOfListening() {
        guard holdsListening else { return }
        holdsListening = false
        MemoryVideoListeningHandoff.end()
    }

    private func releasePlayer() {
        player?.pause()
        // Do not mutate currentItem while an AVPlayerViewController may still be
        // dismantling. Dropping our reference is sufficient once the page is no
        // longer rendering VideoPlayer.
        player = nil
    }
}

/// Music paused by a memory video comes back once no video page is showing. Paging from one
/// video straight to the next keeps it paused instead of letting it blip in between.
@MainActor
enum MemoryVideoListeningHandoff {
    private static var interrupted: InterruptedListening?
    private static var activePages = 0

    static func begin() {
        activePages += 1
        AppAudioSession.lease(.memoryVideo)
        if interrupted == nil { interrupted = InterruptedListening.capture() }
    }

    static func end() {
        activePages = max(0, activePages - 1)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            guard activePages == 0 else { return }
            AppAudioSession.release(.memoryVideo)
            interrupted?.resume()
            interrupted = nil
        }
    }
}
