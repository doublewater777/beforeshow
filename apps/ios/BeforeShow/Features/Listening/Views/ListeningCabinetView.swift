import SwiftUI

struct ListeningCabinetView<Placeholder: View>: View {
    @Bindable var room: ListeningRoomCoordinator
    let scale: CGFloat
    let showAll: () -> Void
    let showDetails: (ListeningDisc) -> Void
    @ViewBuilder let placeholder: Placeholder
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("listening.didHintManualDiscDrag") private var didHintManualDiscDrag = false
    @State private var hintedDiscID: String?

    private var shelfTitle: String {
        room.browsingArtist?.name ?? BSLocalization.text("BeforeShow 热门合辑")
    }

    private var isLoading: Bool {
        room.libraryDiscs.isEmpty && (room.isAuthorizing || !room.accessResolved
            || room.presentation == .loadingCatalog)
    }

    private var shelfDiscs: [ListeningDisc] { room.display.shelfDiscs }

    private var hintDisc: ListeningDisc? {
        shelfDiscs.first { room.discPresentation(for: $0).canLoad }
    }

    var body: some View {
        ListeningShelfView(title: room.browseArtists.isEmpty ? shelfTitle : nil, count: BSLocalization.format("%d 张唱片", room.libraryDiscs.count), isLoading: isLoading, showsAllDiscs: room.display.showsAllDiscs, showAll: showAll) {
            if shelfDiscs.isEmpty {
                placeholder
                    .frame(maxHeight: .infinity)
            } else {
                HStack(alignment: .bottom, spacing: BSSpacing.compact) {
                    ForEach(shelfDiscs) { disc in
                        ListeningCabinetDiscButton(
                            room: room,
                            disc: disc,
                            scale: scale,
                            showsPullHint: hintedDiscID == disc.id,
                            showDetails: showDetails
                        )
                        .frame(maxWidth: shelfDiscs.count >= ListeningDisplayProjector.Shelf.visibleCount ? .infinity : nil)
                    }
                    if shelfDiscs.count < ListeningDisplayProjector.Shelf.visibleCount {
                        Spacer(minLength: 0)
                    }
                }
                .frame(maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, BSSpacing.sm)
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
        private var dragOrigin: CGPoint?

        func attach(to view: UIView) {
            let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
            longPress.minimumPressDuration = 0.30
            longPress.allowableMovement = 24
            longPress.delegate = self
            longPress.cancelsTouchesInView = true
            view.addGestureRecognizer(longPress)

            let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
            tap.delegate = self
            view.addGestureRecognizer(tap)
        }

        @objc private func handleLongPress(_ recognizer: UILongPressGestureRecognizer) {
            guard let view = recognizer.view else { return }
            let location = recognizer.location(in: view)
            switch recognizer.state {
            case .began:
                isDragging = true
                dragOrigin = location
                onBegin?()
                onChanged?(.zero)
            case .changed:
                guard isDragging, let origin = dragOrigin else { return }
                onChanged?(CGSize(width: location.x - origin.x, height: location.y - origin.y))
            case .ended, .cancelled, .failed:
                if isDragging {
                    isDragging = false
                    dragOrigin = nil
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
            if gestureRecognizer is UILongPressGestureRecognizer {
                return canDrag
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
    @ScaledMetric(relativeTo: .caption) private var labelHeight = BSListeningTokens.shelfLabelHeight
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

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
            guard !suppressTap else { return }
            showDetails(disc)
        } label: {
            VStack(spacing: BSListeningTokens.shelfItemSpacing) {
                ZStack(alignment: .topTrailing) {
                    ListeningSleeveCard(
                        disc: disc, isLoaded: isLoaded,
                        showsPullHint: showsPullHint, show: room.show
                    )
                    .background(alignment: .bottom) {
                        Ellipse()
                            .fill(.black.opacity(BSListeningTokens.selectionRestingOpacity))
                            .frame(height: BSListeningTokens.shelfShadowHeight)
                            .blur(radius: BSListeningTokens.shelfShadowBlur)
                            .offset(y: BSSpacing.xs)
                    }
                    .listeningFrame("slot:\(disc.id)")

                    #if canImport(UIKit)
                    // Keep the active touch receiver mounted until the finger lifts.
                    if !isLoaded || room.mechanism.isCabinetDragging {
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
                        .frame(width: BSLayout.minTouchTarget, height: BSListeningTokens.shelfArtwork)
                        .accessibilityHidden(true)
                    }
                    #endif
                }

                Text(disc.title)
                    .font(BSListeningTokens.sleeveLabel)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 1)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.85)
                    .foregroundStyle(room.isPlayingDisc(disc) ? BSColor.Stage.accent : BSColor.Stage.foreground)
                    .frame(maxWidth: .infinity)
                    .frame(height: labelHeight * (dynamicTypeSize.isAccessibilitySize ? 3 : 1))
            }
            .frame(width: BSListeningTokens.shelfItemWidth)
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
        _ = room.mechanism.beginCabinetDrag(disc)
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
        if room.mechanism.isCabinetDragging, room.mechanism.disc?.id == disc.id {
            room.mechanism.endDiscDrag()
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(120))
            suppressTap = false
        }
    }
}
