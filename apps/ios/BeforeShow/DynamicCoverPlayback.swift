import AVFoundation
import AVKit
import SwiftUI
import UIKit

/// App-wide audio session policy.
///
/// iOS defaults to `soloAmbient`, which interrupts other audio as soon as an
/// `AVPlayer` with an audio track starts — `isMuted` only zeroes the output, it
/// does not stop the session from activating. Dynamic covers are decorative and
/// muted, so the app stays on `ambient` + `mixWithOthers` until the user explicitly
/// asks to hear one. Views that intentionally play sound switch to `playback` while
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

enum DynamicCoverSoundPolicy {
    static func shouldExposeControl(hasAudioTrack: Bool, isPlaying: Bool) -> Bool {
        hasAudioTrack && isPlaying
    }

    static func iconName(isMuted: Bool) -> String {
        isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill"
    }
}

enum DynamicCoverAudioTrackProbe {
    static func hasAudioTrack(at url: URL) async -> Bool {
        let asset = AVURLAsset(url: url)
        do {
            let audioTracks = try await asset.loadTracks(withMediaType: .audio)
            return !audioTracks.isEmpty
        } catch {
            return false
        }
    }
}

/// A borderless AVPlayer surface used by dynamic covers.
///
/// Every viewing session starts muted. The sound control only appears while a
/// cover with an audio track is actively playing. Losing active playback (flip,
/// tab/page change, overlay, or backgrounding) revokes the user's temporary
/// unmute choice and restores the app-wide ambient audio policy.
struct DynamicCoverPlaybackView: View {
    let url: URL
    let isPlaying: Bool

    @Environment(\.scenePhase) private var scenePhase
    @State private var isMuted = true
    @State private var hasAudioTrack = false

    private var effectiveIsPlaying: Bool {
        isPlaying && scenePhase == .active
    }

    var body: some View {
        DynamicCoverPlayerSurface(
            url: url,
            isPlaying: effectiveIsPlaying,
            muted: isMuted
        )
        .overlay(alignment: .topTrailing) {
            if DynamicCoverSoundPolicy.shouldExposeControl(
                hasAudioTrack: hasAudioTrack,
                isPlaying: effectiveIsPlaying
            ) {
                soundButton
                    .padding(BSSpacing.sm)
            }
        }
        .task(id: url) {
            resetSoundIfNeeded()
            hasAudioTrack = await DynamicCoverAudioTrackProbe.hasAudioTrack(at: url)
        }
        .onChange(of: effectiveIsPlaying) { _, isActive in
            if !isActive {
                resetSoundIfNeeded()
            }
        }
        .onDisappear {
            resetSoundIfNeeded()
        }
    }

    private var soundButton: some View {
        Button {
            if isMuted {
                AppAudioSession.configureSoundPlayback()
                isMuted = false
            } else {
                isMuted = true
                AppAudioSession.configureAmbient()
            }
        } label: {
            Image(systemName: DynamicCoverSoundPolicy.iconName(isMuted: isMuted))
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: BSLayout.minTouchTarget, height: BSLayout.minTouchTarget)
                .background(Color.black.opacity(0.42), in: Circle())
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("dynamic-cover-sound-toggle")
    }

    private func resetSoundIfNeeded() {
        guard !isMuted else { return }
        isMuted = true
        AppAudioSession.configureAmbient()
    }
}

private struct DynamicCoverPlayerSurface: UIViewRepresentable {
    let url: URL
    let isPlaying: Bool
    let muted: Bool

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
            if let player {
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
        .onDisappear { releasePlayer() }
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
        player?.replaceCurrentItem(with: nil)
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
