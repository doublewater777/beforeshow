import SwiftUI

struct ListeningCabinetView: View {
    @Bindable var room: ListeningRoomCoordinator
    let scale: CGFloat
    let showAll: () -> Void
    let showDetails: (ListeningDisc) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("listening.didHintManualDiscDrag") private var didHintManualDiscDrag = false
    @State private var hintedDiscID: String?

    private var shelfTitle: String {
        room.browsingArtist?.name ?? BSLocalization.text("BeforeShow 热门合辑")
    }

    private var shelfCountText: String {
        if room.catalogState == .loading && room.libraryDiscs.isEmpty {
            return BSLocalization.text("加载中…")
        }
        return BSLocalization.format("%d 张唱片", room.libraryDiscs.count)
    }

    private var shelfDiscs: [ListeningDisc] { room.display.shelfDiscs }

    private var hintDisc: ListeningDisc? {
        shelfDiscs.first { room.discPresentation(for: $0).canLoad }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: BSSpacing.sm) {
            HStack(alignment: .firstTextBaseline) {
                HStack(spacing: BSSpacing.xs) {
                    Text(shelfTitle)
                        .font(BSFont.headline)
                        .foregroundStyle(BSColor.Stage.foreground)
                    Text(shelfCountText)
                        .font(BSListeningTokens.badge)
                        .foregroundStyle(BSColor.Stage.muted)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(BSColor.Stage.surfaceRaised, in: Capsule())
                }
                Spacer()
                if room.display.showsAllDiscs {
                    Button(action: showAll) {
                        HStack(spacing: 3) {
                            Text(BSLocalization.text("查看全部"))
                            Image(systemName: "chevron.right")
                                .font(.system(size: 10, weight: .bold))
                        }
                        .font(BSFont.caption)
                        .foregroundStyle(BSColor.Stage.accent)
                        .frame(minHeight: BSLayout.minTouchTarget)
                    }
                    .buttonStyle(BSListeningPressStyle(scale: 0.95))
                    .accessibilityIdentifier("listening.allDiscs")
                }
            }
            .padding(.top, 2)

            if room.catalogState == .loading && shelfDiscs.isEmpty {
                HStack(spacing: BSSpacing.compact) {
                    ForEach(0..<3, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: BSRadius.md, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [BSColor.Stage.surfaceRaised, BSColor.Stage.surface],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 96, height: 96)
                            .overlay(
                                RoundedRectangle(cornerRadius: BSRadius.md, style: .continuous)
                                    .stroke(BSColor.Stage.border, lineWidth: 1)
                            )
                            .overlay {
                                ProgressView()
                                    .tint(BSColor.Stage.accent)
                                    .scaleEffect(0.8)
                            }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 2)
                .padding(.vertical, 4)
            } else if shelfDiscs.isEmpty {
                Text(BSLocalization.text("暂时没有找到可翻的唱片"))
                    .font(BSListeningTokens.caption)
                    .foregroundStyle(BSColor.Stage.muted)
                    .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
            } else {
                VStack(spacing: 0) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .bottom, spacing: BSSpacing.compact) {
                            ForEach(shelfDiscs) { disc in
                                ListeningCabinetDiscButton(
                                    room: room,
                                    disc: disc,
                                    scale: scale,
                                    showsPullHint: hintedDiscID == disc.id,
                                    showDetails: showDetails
                                )
                            }
                        }
                        .padding(.horizontal, 2)
                        .padding(.vertical, 4)
                    }

                    VStack(spacing: 0) {
                        Rectangle()
                            .fill(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.12), BSColor.Stage.accent.opacity(0.35), Color.white.opacity(0.08)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(height: 1)
                        LinearGradient(
                            colors: [
                                Color(red: 0.22, green: 0.22, blue: 0.24),
                                Color(red: 0.11, green: 0.11, blue: 0.12),
                                Color(red: 0.05, green: 0.05, blue: 0.06)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: 4)
                        .clipShape(RoundedRectangle(cornerRadius: 1.5, style: .continuous))
                        .shadow(color: Color.black.opacity(0.6), radius: 4, y: 2)
                    }
                    .accessibilityHidden(true)
                }
            }
        }
        .foregroundStyle(BSColor.Stage.muted)
        .listeningFrame("cabinet")
        .task(id: hintEligibilityKey) {
            guard !didHintManualDiscDrag, !reduceMotion,
                  room.mechanism.position == .stored,
                  let disc = hintDisc else { return }
            try? await Task.sleep(for: .milliseconds(550))
            guard !Task.isCancelled else { return }
            hintedDiscID = disc.id
            try? await Task.sleep(for: .milliseconds(350))
            hintedDiscID = nil
            didHintManualDiscDrag = true
        }
    }

    private var hintEligibilityKey: String {
        "\(hintDisc?.id ?? "none")-\(room.mechanism.position)"
    }
}

#if canImport(UIKit)
import UIKit

private struct CabinetDiscGestureBridge: UIViewRepresentable {
    let canDrag: Bool
    let onBegin: () -> Void
    let onChanged: (CGSize) -> Void
    let onEnded: () -> Void
    let onTap: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> GestureCaptureView {
        let view = GestureCaptureView()
        context.coordinator.attach(to: view)
        return view
    }

    func updateUIView(_ uiView: GestureCaptureView, context: Context) {
        context.coordinator.canDrag = canDrag
        context.coordinator.onBegin = onBegin
        context.coordinator.onChanged = onChanged
        context.coordinator.onEnded = onEnded
        context.coordinator.onTap = onTap
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var canDrag = true
        var onBegin: (() -> Void)?
        var onChanged: ((CGSize) -> Void)?
        var onEnded: (() -> Void)?
        var onTap: (() -> Void)?
        private var isDragging = false

        func attach(to view: UIView) {
            let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
            pan.delegate = self
            pan.cancelsTouchesInView = true
            view.addGestureRecognizer(pan)

            let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
            tap.delegate = self
            view.addGestureRecognizer(tap)
        }

        @objc private func handlePan(_ recognizer: UIPanGestureRecognizer) {
            guard let view = recognizer.view else {
                return
            }
            switch recognizer.state {
            case .began:
                isDragging = true
                onBegin?()
                let translation = recognizer.translation(in: view)
                onChanged?(CGSize(width: translation.x, height: translation.y))
            case .changed:
                let translation = recognizer.translation(in: view)
                onChanged?(CGSize(width: translation.x, height: translation.y))
            case .ended, .cancelled, .failed:
                if isDragging {
                    isDragging = false
                    onEnded?()
                }
            default:
                break
            }
        }

        @objc private func handleTap(_ recognizer: UITapGestureRecognizer) {
            guard recognizer.state == .ended, !isDragging else { return }
            onTap?()
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            if let pan = gestureRecognizer as? UIPanGestureRecognizer {
                guard canDrag, let view = pan.view else { return false }
                let velocity = pan.velocity(in: view)
                // Only recognize downward pull toward the player;
                // reject horizontal swipes so the cabinet ScrollView scrolls seamlessly.
                return velocity.y > 20 && velocity.y > abs(velocity.x) * 0.6
            }
            return true
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            false
        }
    }

    final class GestureCaptureView: UIView {
        override init(frame: CGRect) {
            super.init(frame: frame)
            backgroundColor = .clear
            isUserInteractionEnabled = true
        }
        required init?(coder: NSCoder) {
            super.init(coder: coder)
            backgroundColor = .clear
            isUserInteractionEnabled = true
        }
    }
}
#endif

private struct ListeningCabinetDiscButton: View {
    @Bindable var room: ListeningRoomCoordinator
    let disc: ListeningDisc
    let scale: CGFloat
    let showsPullHint: Bool
    let showDetails: (ListeningDisc) -> Void
    @State private var suppressTap = false

    private var isLoaded: Bool {
        room.mechanism.disc?.id == disc.id && room.mechanism.position != .stored
    }

    private var presentation: ListeningDiscPresentation {
        room.discPresentation(for: disc)
    }

    private var accessibilityArtistName: String {
        disc.artistNames.isEmpty
            ? room.browsingArtist?.name ?? "BeforeShow"
            : disc.artistNames.joined(separator: ", ")
    }

    private var accessibilityValue: String {
        let marks = ListeningSleeveMarks.accessibilityText(room: room, disc: disc)
        return marks.isEmpty ? presentation.statusText : "\(marks), \(presentation.statusText)"
    }

    var body: some View {
        Button {
            showDetails(disc)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                ZStack(alignment: .topTrailing) {
                    ListeningSleeveCard(disc: disc, isLoaded: isLoaded, showsPullHint: showsPullHint, show: room.show)
                        .offset(y: room.isRecentDisc(disc) ? -BSListeningTokens.recentLift : 0)
                        .listeningFrame("slot:\(disc.id)")

                    #if canImport(UIKit)
                    if !isLoaded {
                        CabinetDiscGestureBridge(
                            canDrag: presentation.canLoad,
                            onBegin: {
                                beginDragIfNeeded()
                            },
                            onChanged: { translation in
                                updateDrag(translation)
                            },
                            onEnded: {
                                finishDragIfNeeded()
                            },
                            onTap: {
                                showDetails(disc)
                            }
                        )
                        .frame(width: 44, height: 76)
                        .accessibilityHidden(true)
                    }
                    #endif
                }

                HStack(spacing: 3) {
                    if room.isPlayingDisc(disc) {
                        Image(systemName: "waveform")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(BSColor.Stage.accent)
                    }
                    ListeningSleeveMarks(room: room, disc: disc)
                    Text(disc.title)
                        .font(BSListeningTokens.captionMedium)
                        .lineLimit(1)
                        .foregroundStyle(room.isPlayingDisc(disc) ? BSColor.Stage.accent : BSColor.Stage.foreground)
                }
                .frame(width: 94, alignment: .leading)
                .frame(height: 18, alignment: .leading)
            }
            .frame(width: 96, alignment: .leading)
        }
        .buttonStyle(BSListeningPressStyle(scale: 0.95))
        .accessibilityLabel("\(disc.title), \(accessibilityArtistName)")
        .accessibilityValue(accessibilityValue)
        .accessibilityActions {
            if presentation.canLoad {
                Button(BSLocalization.text("取出并放入播放机")) {
                    room.takePlayableDiscFromCabinet(disc)
                }
            }
        }
        .accessibilityIdentifier("listening.disc.\(disc.id)")
    }

    private func beginDragIfNeeded() {
        guard !room.mechanism.isCabinetDragging else {
            return
        }
        suppressTap = true
        _ = room.beginPlayableDiscDrag(disc)
    }

    private func updateDrag(_ translation: CGSize) {
        guard room.mechanism.isCabinetDragging, room.mechanism.disc?.id == disc.id else { return }
        let tilt = room.mechanism.configuration.geometry.tiltDegrees * .pi / 180
        room.mechanism.dragDisc(CGSize(
            width: translation.width / scale,
            height: translation.height / scale / cos(tilt)
        ))
    }

    private func finishDragIfNeeded() {
        guard room.mechanism.isCabinetDragging, room.mechanism.disc?.id == disc.id else {
            suppressTap = false
            return
        }
        room.mechanism.endDiscDrag()
        Task { @MainActor in
            await Task.yield()
            suppressTap = false
        }
    }
}
