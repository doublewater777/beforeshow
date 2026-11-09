import SwiftUI
import AVKit

/// The expanded video. Dragging it down docks the video into the mini player;
/// turning the phone sideways fills the screen with the video.
struct ListeningVideoPlayerView: View {
    let dock: ListeningVideoDock
    @Environment(\.openURL) private var openURL
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    private var isLandscape: Bool { verticalSizeClass == .compact }

    var body: some View {
        Group {
            if let selection = dock.selection {
                if isLandscape {
                    screen
                        .ignoresSafeArea()
                        .statusBarHidden()
                } else {
                    portrait(selection)
                }
            }
        }
        .foregroundStyle(BSColor.Stage.foreground)
        .background((isLandscape ? Color.black : BSColor.Stage.background).ignoresSafeArea())
        .presentationDragIndicator(isLandscape ? .hidden : .visible)
        .onAppear { AppInterfaceOrientation.allowLandscape(true) }
        .onDisappear { AppInterfaceOrientation.allowLandscape(false) }
    }

    private var screen: some View {
        ZStack {
            Color.black
            if let player = dock.player {
                ListeningVideoSurface(player: player) { dock.isExpanded = true }
            } else if dock.loadFailed {
                Button { dock.retry() } label: {
                    Text(ListeningCopy.text("暂时无法载入视频，点按重试"))
                        .font(BSListeningTokens.caption)
                        .foregroundStyle(BSColor.Stage.muted)
                }
                .buttonStyle(.plain)
            } else {
                ProgressView().tint(BSColor.Stage.muted)
            }
        }
    }

    private func portrait(_ selection: ListeningVideoSelection) -> some View {
        let more = selection.related.filter { $0.id != selection.video.id }
        return VStack(spacing: 0) {
            screen.aspectRatio(16 / 9, contentMode: .fit)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: BSSpacing.md) {
                    VStack(alignment: .leading, spacing: BSSpacing.xs) {
                        Text(selection.video.title)
                            .font(.title3.weight(.bold))
                        Text(ListeningVideoFormat.byline(selection.video))
                            .font(.subheadline)
                            .foregroundStyle(BSColor.Stage.muted)
                    }

                    Button {
                        let video = selection.video
                        openURL(video.appURL) { accepted in
                            if !accepted { openURL(video.webURL) }
                        }
                    } label: {
                        Label(ListeningCopy.text("在哔哩哔哩打开"), systemImage: "arrow.up.right.square")
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, BSSpacing.md)
                            .frame(height: 40)
                            .overlay(Capsule().stroke(BSColor.Stage.border, lineWidth: 1))
                    }
                    .buttonStyle(BSListeningPressStyle())

                    if !more.isEmpty {
                        Text(ListeningCopy.format("更多 %@", selection.artist))
                            .font(BSListeningTokens.sectionTitle)
                            .foregroundStyle(BSColor.Stage.muted)
                            .padding(.top, BSSpacing.sm)
                        ForEach(more) { video in
                            Button { dock.play(video) } label: { row(video) }
                                .buttonStyle(BSListeningPressStyle(scale: 0.98))
                        }
                    }
                }
                .padding(BSSpacing.roomy)
            }
        }
    }

    private func row(_ video: ArtistVideo) -> some View {
        HStack(spacing: BSSpacing.compact) {
            ListeningVideoThumbnail(video: video)
                .frame(width: 112, height: 63)
            VStack(alignment: .leading, spacing: 2) {
                Text(video.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(ListeningVideoFormat.byline(video))
                    .font(BSListeningTokens.caption)
                    .foregroundStyle(BSColor.Stage.muted)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }
}

/// The system player, so the video carries on in Picture in Picture when the app leaves the screen.
private struct ListeningVideoSurface: UIViewControllerRepresentable {
    let player: AVPlayer
    let onRestore: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onRestore: onRestore) }

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.allowsPictureInPicturePlayback = true
        controller.canStartPictureInPictureAutomaticallyFromInline = true
        // The dock's Now Playing session publishes the video, docked or not.
        controller.updatesNowPlayingInfoCenter = false
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        if controller.player !== player { controller.player = player }
        context.coordinator.onRestore = onRestore
    }

    final class Coordinator: NSObject, AVPlayerViewControllerDelegate {
        var onRestore: () -> Void

        init(onRestore: @escaping () -> Void) { self.onRestore = onRestore }

        func playerViewController(
            _ playerViewController: AVPlayerViewController,
            restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void
        ) {
            onRestore()
            completionHandler(true)
        }
    }
}

/// The docked video in the root bar: tap to open, or play/pause.
struct ListeningVideoMiniPlayer: View {
    let dock: ListeningVideoDock
    var isSelected: Bool = false
    let onOpen: () -> Void

    var body: some View {
        if let video = dock.selection?.video {
            HStack(spacing: 4) {
                HStack(spacing: 9) {
                    ListeningVideoThumbnail(video: video, showsDuration: false)
                        .frame(width: 48, height: 32)
                    Text(video.title)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(isSelected ? BSColor.Stage.accent : BSColor.textPrimary)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.leading, 10)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .onTapGesture(perform: onOpen)

                button(dock.isPlaying ? "pause.fill" : "play.fill") { dock.togglePlayback() }
                    .contentTransition(.symbolEffect(.replace))
                    .padding(.trailing, 4)
            }
        }
    }

    private func button(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(isSelected ? BSColor.Stage.accent : BSColor.textPrimary)
                .frame(width: 34, height: BSLayout.minTouchTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(BSListeningPressStyle(scale: 0.96))
    }
}
