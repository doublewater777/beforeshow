import SwiftUI
import UIKit
import QuartzCore

/// Orthographic camera: one fixed model-space pivot. Opening rotates a rigid
/// plane about X; its projected Y length is cos(cameraTilt + hingeAngle).
/// Both UV faces live in exactly the same rectangle and share this transform.
private struct HingedPlane: GeometryEffect {
    var angle: Double
    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(scaleX: 1, y: cos(angle * .pi / 180)))
    }
}

enum ListeningLoadedLidAppearance {
    static let fadeBeginsAtOpenFraction = 0.45
    static let fullyClearAtOpenFraction = 0.12

    static func transparencyProgress(
        lidOpenFraction: Double,
        hasDisc: Bool,
        isShowingBackFace: Bool
    ) -> Double {
        guard hasDisc, !isShowingBackFace else { return 0 }

        let span = fadeBeginsAtOpenFraction - fullyClearAtOpenFraction
        guard span > 0 else { return lidOpenFraction <= fullyClearAtOpenFraction ? 1 : 0 }

        let linear = (fadeBeginsAtOpenFraction - lidOpenFraction) / span
        let clamped = min(max(linear, 0), 1)
        return clamped * clamped * (3 - 2 * clamped)
    }
}


enum ListeningDiscDetailTapPolicy {
    static let maximumMovement: CGFloat = 8
    static let hitSlop: CGFloat = 8

    static func canOpen(
        position: CDMechanism.Position,
        isAutomatic: Bool,
        isReturning: Bool,
        isCabinetDragging: Bool,
        lidIsStable: Bool,
        partsAreMoving: Bool
    ) -> Bool {
        position == .seated
            && !isAutomatic
            && !isReturning
            && !isCabinetDragging
            && lidIsStable
            && !partsAreMoving
    }

    static func isIntentionalTap(_ translation: CGSize) -> Bool {
        translation.width * translation.width + translation.height * translation.height
            <= maximumMovement * maximumMovement
    }

    static func contains(_ location: CGPoint, center: CGPoint, size: CGSize) -> Bool {
        let radiusX = size.width / 2 + hitSlop
        let radiusY = size.height / 2 + hitSlop
        guard radiusX > 0, radiusY > 0 else { return false }

        let dx = (location.x - center.x) / radiusX
        let dy = (location.y - center.y) / radiusY
        return dx * dx + dy * dy <= 1
    }
}

struct ListeningMachineView: View {
    @Bindable var room: ListeningRoomCoordinator
    let scale: CGFloat
    let showDetails: (ListeningDisc) -> Void
    private var hardware: ListeningHardwareSnapshot { room.display.hardware }
    private var configuration: CDPlayerConfiguration { room.playerConfiguration }
    private var geometry: CDPlayerConfiguration.Geometry { configuration.geometry }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Ellipse()
                .fill(.black.opacity(0.45)).blur(radius: 22)
                .frame(width: 370, height: 130).position(x: 232, y: 679)
            CDPlayerDiscWellView(configuration: configuration)
            CDPlayerBodyShellView(configuration: configuration)
            CDPlayerDiscView(
                room: room,
                hardware: hardware,
                configuration: configuration,
                scale: scale,
                isRotating: room.display.player.shouldRotateDisc
                    && hardware.position == .seated
                    && hardware.isClosed
            )
                .zIndex(hardware.position == .seated ? 1 : 4)
            CDPlayerLidView(room: room, hardware: hardware, configuration: configuration, scale: scale)
                .zIndex(3)
            CDPlayerLCDView(room: room)
                .zIndex(5)
            CDPlayerControlsView(room: room, scale: scale)
                .zIndex(6)
        }
        .frame(width: geometry.canvas.width, height: geometry.canvas.height)
        .allowsHitTesting(!hardware.isAutomatic)
        .disabled(hardware.isAutomatic)
        .scaleEffect(scale, anchor: .topLeading)
        .frame(width: geometry.canvas.width * scale, height: geometry.canvas.height * scale, alignment: .topLeading)
        .simultaneousGesture(discDetailGesture)
    }

    private var discDetailGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onEnded { value in
                guard let discID = hardware.discID,
                      let disc = room.disc(id: discID),
                      ListeningDiscDetailTapPolicy.canOpen(
                        position: hardware.position,
                        isAutomatic: hardware.isAutomatic,
                        isReturning: hardware.isReturning,
                        isCabinetDragging: hardware.isCabinetDragging,
                        lidIsStable: hardware.isOpen || hardware.isClosed,
                        partsAreMoving: hardware.partsAreMoving
                      ),
                      ListeningDiscDetailTapPolicy.isIntentionalTap(value.translation) else {
                    return
                }

                let projectedHeight = geometry.discDiameter * cos(geometry.tiltDegrees * .pi / 180)
                let center = CGPoint(
                    x: geometry.discCenter.x * scale,
                    y: geometry.projectedY(geometry.discCenter.y) * scale
                )
                let size = CGSize(
                    width: geometry.discDiameter * scale,
                    height: projectedHeight * scale
                )
                guard ListeningDiscDetailTapPolicy.contains(value.location, center: center, size: size) else {
                    return
                }

                showDetails(disc)
            }
    }

}

private struct CDPlayerDiscWellView: View {
    let configuration: CDPlayerConfiguration
    private var geometry: CDPlayerConfiguration.Geometry { configuration.geometry }

    var body: some View {
        Image(configuration.assets.discWell)
            .resizable()
            .frame(width: geometry.discWellDiameter, height: geometry.discWellDiameter)
            .scaleEffect(x: 1, y: cos(geometry.tiltDegrees * .pi / 180))
            .position(x: geometry.discCenter.x, y: geometry.projectedY(geometry.discCenter.y))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

private struct CDPlayerBodyShellView: View {
    let configuration: CDPlayerConfiguration
    private var geometry: CDPlayerConfiguration.Geometry { configuration.geometry }

    var body: some View {
        Image(configuration.assets.body)
            .resizable()
            .frame(width: geometry.body.width, height: geometry.body.height)
            // The photographed body texture still supplies the metal shell, controls,
            // hinges and LCD surround. Its old baked tray is removed in model space;
            // CDPlayerDiscWellView is now the sole renderer for the disc well.
            .mask {
                ZStack(alignment: .topLeading) {
                    Rectangle().fill(.white)
                    Circle()
                        .fill(.black)
                        .frame(width: geometry.discWellDiameter, height: geometry.discWellDiameter)
                        .position(
                            x: geometry.discCenter.x - geometry.body.minX,
                            y: geometry.discCenter.y - geometry.body.minY
                        )
                }
                .luminanceToAlpha()
            }
            .scaleEffect(
                x: 1,
                y: cos(geometry.tiltDegrees * .pi / 180),
                anchor: UnitPoint(
                    x: 0.5,
                    y: (geometry.hingeY - geometry.body.minY) / geometry.body.height
                )
            )
            .position(x: geometry.body.midX, y: geometry.body.midY)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

private struct CDPlayerDiscView: View {
    let room: ListeningRoomCoordinator
    let hardware: ListeningHardwareSnapshot
    let configuration: CDPlayerConfiguration
    let scale: CGFloat
    let isRotating: Bool
    private var geometry: CDPlayerConfiguration.Geometry { configuration.geometry }
    private var rotationIdentity: String {
        "\(hardware.discID ?? "empty"):\(hardware.position == .stored ? "stored" : "active")"
    }

    var body: some View {
        CDContinuousRotationLayer(
            identity: rotationIdentity,
            isRotating: isRotating && !hardware.reducedMotion,
            revolutionsPerMinute: BSListeningTokens.discRotationRPM
        ) {
            ListeningDiscArtwork(disc: room.disc(id: hardware.discID ?? ""), image: configuration.assets.disc)
        }
            .frame(width: geometry.discDiameter, height: geometry.discDiameter)
            .scaleEffect(hardware.discScale)
            .opacity(hardware.position == .stored ? 0 : 1)
            .scaleEffect(x: 1, y: cos(geometry.tiltDegrees * .pi / 180))
            .shadow(color: .black.opacity(0.3), radius: 3 + hardware.lift * 9, y: 4 + hardware.lift * 13)
            .contentShape(Circle())
            .gesture(DragGesture(minimumDistance: 5, coordinateSpace: .named("playerStage"))
                .onChanged { value in
                    room.dragLoadedDisc(translation: value.translation, scale: scale)
                }.onEnded { _ in room.endLoadedDiscDrag() })
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(hardware.discTitle ?? "CD") CD")
            .accessibilityAction(named: BSLocalization.text("取出")) { room.removeLoadedDisc() }
            .accessibilityAction(named: BSLocalization.text("放回唱片柜")) { room.returnLoadedDisc() }
            .accessibilityAction(named: BSLocalization.text("放入")) { room.insertLoadedDisc() }
            .position(
                x: hardware.discX,
                y: geometry.projectedY(hardware.discY) - (hardware.reducedMotion ? 0 : hardware.lift * 20)
            )
            .allowsHitTesting(hardware.position != .stored && !hardware.isReturning)
            .phaseAnimator([false, true, false], trigger: hardware.occupiedAttemptCount) { content, emphasized in
                content.scaleEffect(emphasized && !hardware.reducedMotion ? 1.035 : 1)
            } animation: { _ in
                .easeInOut(duration: 0.09)
            }
    }
}


/// The disc motor is rendered by Core Animation rather than the mechanism's
/// display link. This keeps continuous playback rotation on the compositor
/// while the app is foreground-inactive under Notification Center or Control Center.
private struct CDContinuousRotationLayer<Content: View>: UIViewControllerRepresentable {
    let identity: String
    let isRotating: Bool
    let revolutionsPerMinute: Double
    let content: Content

    init(
        identity: String,
        isRotating: Bool,
        revolutionsPerMinute: Double,
        @ViewBuilder content: () -> Content
    ) {
        self.identity = identity
        self.isRotating = isRotating
        self.revolutionsPerMinute = revolutionsPerMinute
        self.content = content()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIViewController(context: Context) -> UIHostingController<Content> {
        let controller = UIHostingController(rootView: content)
        controller.view.backgroundColor = .clear
        controller.view.layer.allowsEdgeAntialiasing = true
        return controller
    }

    func updateUIViewController(_ controller: UIHostingController<Content>, context: Context) {
        controller.rootView = content
        context.coordinator.update(
            layer: controller.view.layer,
            identity: identity,
            isRotating: isRotating,
            revolutionsPerMinute: revolutionsPerMinute
        )
    }

    static func dismantleUIViewController(_ controller: UIHostingController<Content>, coordinator: Coordinator) {
        coordinator.reset(layer: controller.view.layer)
    }

    @MainActor final class Coordinator {
        private let animationKey = "listening.disc.continuousRotation"
        private var identity: String?
        private var revolutionsPerMinute: Double?
        private var isRotating = false

        func update(
            layer: CALayer,
            identity: String,
            isRotating: Bool,
            revolutionsPerMinute: Double
        ) {
            let rpm = max(revolutionsPerMinute, 0.01)
            if self.identity != identity || self.revolutionsPerMinute != rpm {
                reset(layer: layer)
                self.identity = identity
                self.revolutionsPerMinute = rpm
            }

            guard isRotating != self.isRotating else { return }
            if isRotating {
                if layer.animation(forKey: animationKey) == nil {
                    installRotation(on: layer, rpm: rpm)
                } else {
                    resume(layer: layer)
                }
            } else {
                pause(layer: layer)
            }
            self.isRotating = isRotating
        }

        func reset(layer: CALayer) {
            layer.speed = 1
            layer.timeOffset = 0
            layer.beginTime = 0
            layer.removeAnimation(forKey: animationKey)
            isRotating = false
        }

        private func installRotation(on layer: CALayer, rpm: Double) {
            let animation = CABasicAnimation(keyPath: "transform.rotation.z")
            animation.fromValue = 0.0
            animation.toValue = Double.pi * 2
            animation.duration = 60 / rpm
            animation.repeatCount = .infinity
            animation.timingFunction = CAMediaTimingFunction(name: .linear)
            animation.isRemovedOnCompletion = false
            layer.add(animation, forKey: animationKey)
        }

        private func pause(layer: CALayer) {
            guard layer.animation(forKey: animationKey) != nil, layer.speed != 0 else { return }
            let pausedTime = layer.convertTime(CACurrentMediaTime(), from: nil)
            layer.speed = 0
            layer.timeOffset = pausedTime
        }

        private func resume(layer: CALayer) {
            guard layer.speed == 0 else { return }
            let pausedTime = layer.timeOffset
            layer.speed = 1
            layer.timeOffset = 0
            layer.beginTime = 0
            let timeSincePause = layer.convertTime(CACurrentMediaTime(), from: nil) - pausedTime
            layer.beginTime = timeSincePause
        }
    }
}

private struct CDPlayerLidView: View {
    let room: ListeningRoomCoordinator
    let hardware: ListeningHardwareSnapshot
    let configuration: CDPlayerConfiguration
    let scale: CGFloat
    private var geometry: CDPlayerConfiguration.Geometry { configuration.geometry }
    private var lidAngle: Double {
        geometry.tiltDegrees + hardware.lid * geometry.maximumOpening
    }
    private var isShowingBackFace: Bool {
        cos(lidAngle * .pi / 180) < 0
    }
    private var transparencyProgress: Double {
        ListeningLoadedLidAppearance.transparencyProgress(
            lidOpenFraction: hardware.lid,
            hasDisc: hardware.hasDisc,
            isShowingBackFace: isShowingBackFace
        )
    }
    private var outerLidOpacity: Double {
        1 - transparencyProgress * (1 - BSListeningTokens.loadedLidOpacity)
    }

    var body: some View {
        ZStack {
            // Keep the photographed lid solid while it is open. Once a seated
            // disc is being covered, fade into the clear-acrylic treatment only
            // during the final portion of the closing travel.
            Image(configuration.assets.lidOuter).resizable()
                .opacity(isShowingBackFace ? 0 : outerLidOpacity)

            // The inside face is not part of the transparent treatment.
            Image(configuration.assets.lidInner).resizable()
                .opacity(isShowingBackFace ? 1 : 0)

            LinearGradient(
                colors: [
                    .white.opacity(0.10),
                    .white.opacity(0.025),
                    .clear,
                    .black.opacity(0.035)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .mask(Image(configuration.assets.lidOuter).resizable())
            .opacity(transparencyProgress)

            // Keep the acrylic rim readable as the cover clears over the disc,
            // clipped to the lid silhouette so it never rings outside the body.
            ZStack {
                Ellipse()
                    .strokeBorder(.white.opacity(0.28), lineWidth: 2.2)
                    .padding(2)
                Ellipse()
                    .strokeBorder(.black.opacity(0.16), lineWidth: 1)
                    .padding(5)
            }
            .mask(Image(configuration.assets.lidOuter).resizable())
            .opacity(transparencyProgress)

            LinearGradient(
                colors: [
                    .white.opacity((0.07 - 0.045 * transparencyProgress) * hardware.lid),
                    .clear,
                    .black.opacity((0.10 - 0.065 * transparencyProgress) * hardware.lid)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .mask(
                Image(isShowingBackFace ? configuration.assets.lidInner : configuration.assets.lidOuter)
                    .resizable()
            )
        }
        .frame(width: geometry.lid.width, height: geometry.lid.height)
        .contentShape(Ellipse())
        .modifier(HingedPlane(angle: lidAngle))
        .offset(x: geometry.lid.minX, y: geometry.hingeY)
        .gesture(DragGesture(minimumDistance: 3, coordinateSpace: .named("playerStage"))
            .onChanged { value in room.dragLid(translation: value.translation.height, scale: scale) }
            .onEnded { value in
                room.endLidDrag(
                    translation: value.translation.height,
                    predicted: value.predictedEndTranslation.height,
                    scale: scale
                )
            })
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(BSLocalization.text("播放器上盖"))
        .accessibilityValue(BSLocalization.text(hardware.isOpen ? "已打开" : "已合上"))
        .accessibilityAction(named: BSLocalization.text("打开")) { room.setLid(open: true) }
        .accessibilityAction(named: BSLocalization.text("合上")) { room.setLid(open: false) }
    }
}

private struct CDPlayerLCDView: View {
    let room: ListeningRoomCoordinator
    private var hardware: ListeningHardwareSnapshot { room.display.hardware }
    private var geometry: CDPlayerConfiguration.Geometry { room.playerConfiguration.geometry }

    var body: some View {
        let displayTrack = room.playerDisplayTrack
        VStack(alignment: .leading, spacing: 1) {
            Text(!hardware.hasDisc ? "NO DISC" : displayTrack?.title ?? "")
                .font(.system(size: 9, weight: .semibold, design: .monospaced)).lineLimit(1)
            Text(hardware.hasDisc ? displayTrack?.artistName ?? "—" : "—")
                .font(.system(size: 7, weight: .medium, design: .monospaced)).lineLimit(1)
            HStack(spacing: 3) {
                if let displayTrackIndex = room.playerDisplayTrackIndex {
                    Text(String(format: "TR %02d", displayTrackIndex + 1))
                } else {
                    Text("TR --")
                }
                Spacer(minLength: 0)
                if hardware.hasDisc {
                    let phase = room.display.player.phase
                    // Playback time is continuous player state: sample it while playing.
                    TimelineView(.animation(minimumInterval: 1, paused: !phase.isPlaybackActive)) { _ in
                        switch phase {
                        case .preparing, .waiting:
                            Text(room.playerDisplayTimeText)
                        case .playing, .seeking:
                            Text("▶ \(room.playerDisplayTimeText)")
                        case .noDisc, .paused, .interrupted, .stopped, .finished, .failed:
                            Text("⏸ \(room.playerDisplayTimeText)")
                        }
                    }
                }
            }
            .font(.system(size: 7, weight: .medium, design: .monospaced))
            .lineLimit(1)
        }
        .foregroundStyle(ListeningStyle.lcdInk).padding(.horizontal, 5)
        .frame(width: geometry.lcd.width, height: geometry.lcd.height)
        .background(LinearGradient(colors: [ListeningStyle.lcdTop, ListeningStyle.lcdBottom], startPoint: .top, endPoint: .bottom))
        .clipShape(RoundedRectangle(cornerRadius: 2))
        .overlay(RoundedRectangle(cornerRadius: 2).stroke(.black.opacity(0.35), lineWidth: 1))
        .position(x: geometry.lcd.midX, y: geometry.projectedY(geometry.lcd.midY))
        .accessibilityElement(children: .combine)
    }
}

private struct CDPlayerControlsView: View {
    let room: ListeningRoomCoordinator
    let scale: CGFloat
    private var geometry: CDPlayerConfiguration.Geometry { room.playerConfiguration.geometry }
    private var playerPresentation: ListeningPlayerPresentation { room.display.player }

    var body: some View {
        ForEach(CDControl.allCases) { control in
            if let rect = geometry.controls[control] {
                Button { room.perform(control) } label: {
                    RoundedRectangle(cornerRadius: 10).fill(.white.opacity(0.001))
                        .frame(width: max(rect.width, 44 / scale), height: max(rect.height, 44 / scale))
                }
                .disabled(control == .playPause && !playerPresentation.canPlayPause)
                .buttonStyle(CDHardwareButtonStyle())
                .accessibilityLabel(BSLocalization.text(
                    control == .playPause
                        ? (playerPresentation.showsPauseControl ? "暂停" : "播放")
                        : control.label
                ))
                .accessibilityValue(control == .playPause ? playerPresentation.statusText : "")
                .accessibilityHint(control == .playPause ? (playerPresentation.blockingReason ?? "") : "")
                .accessibilityIdentifier(control.rawValue)
                .position(x: rect.midX, y: geometry.projectedY(rect.midY))
            }
        }
    }
}

struct CDHardwareButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .offset(y: configuration.isPressed ? 1 : 0)
            .sensoryFeedback(.impact(weight: .light, intensity: 0.7), trigger: configuration.isPressed)
    }
}
