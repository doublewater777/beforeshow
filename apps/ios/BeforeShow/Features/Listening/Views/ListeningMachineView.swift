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

struct ListeningMachineView: View {
    @Bindable var room: ListeningRoomCoordinator
    private var player: CDMechanism { room.mechanism }
    let scale: CGFloat
    private var geometry: CDPlayerConfiguration.Geometry { player.configuration.geometry }

    var body: some View {
        ZStack(alignment: .topLeading) {
            ListeningPlayerAmbientHalo(
                artworkURL: player.disc?.artworkURL,
                phase: ListeningAtmospherePhase(room: room)
            )
            .frame(
                width: geometry.discDiameter * BSListeningTokens.haloWidth,
                height: geometry.discDiameter * BSListeningTokens.haloHeight
            )
            .position(
                x: geometry.discCenter.x,
                y: geometry.projectedY(geometry.discCenter.y) + geometry.discDiameter * 0.10
            )

            Ellipse()
                .fill(BSColor.Stage.accent.opacity(room.isPlaying ? 0.14 : 0.07))
                .frame(width: geometry.body.width * 0.90, height: 110)
                .position(x: geometry.body.midX, y: geometry.body.maxY - 20)
                .blur(radius: 38)

            Ellipse()
                .fill(.black.opacity(0.45)).blur(radius: 22)
                .frame(width: 370, height: 130).position(x: 232, y: 679)
            CDPlayerDiscWellView(player: player)
            CDPlayerBodyShellView(player: player)
            ListeningTrayLight(phase: ListeningAtmospherePhase(room: room))
                .frame(width: geometry.discWellDiameter,
                       height: geometry.discWellDiameter)
                .scaleEffect(x: 1, y: cos(geometry.tiltDegrees * .pi / 180))
                .position(x: geometry.discCenter.x, y: geometry.projectedY(geometry.discCenter.y))
            CDPlayerDiscView(player: player, scale: scale, isPlaying: room.isPlaying)
                .zIndex(player.position == .seated ? 1 : 4)
            spindle.zIndex(2)
            CDPlayerLidView(player: player, scale: scale)
                .zIndex(3)
            CDPlayerLCDView(room: room)
                .zIndex(5)
            CDPlayerControlsView(room: room, scale: scale)
                .zIndex(6)
        }
        .frame(width: geometry.canvas.width, height: geometry.canvas.height)
        .allowsHitTesting(!player.isAutomatic)
        .disabled(player.isAutomatic)
        .scaleEffect(scale, anchor: .topLeading)
        .frame(width: geometry.canvas.width * scale, height: geometry.canvas.height * scale, alignment: .topLeading)
    }

    private var spindle: some View {
        let diameter = geometry.discDiameter * BSListeningTokens.discSpindleRadiusFraction * 2
        return ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color(white: 0.46), Color(white: 0.12), Color(white: 0.30)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Circle()
                .stroke(Color.white.opacity(0.34), lineWidth: max(0.6, diameter * 0.055))
                .padding(diameter * 0.16)
            Circle()
                .fill(Color(white: 0.66))
                .frame(width: diameter * 0.30, height: diameter * 0.30)
        }
        .frame(width: diameter, height: diameter)
        .position(x: geometry.discCenter.x, y: geometry.projectedY(geometry.discCenter.y))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct CDPlayerDiscWellView: View {
    let player: CDMechanism
    private var geometry: CDPlayerConfiguration.Geometry { player.configuration.geometry }

    var body: some View {
        Image(player.configuration.assets.discWell)
            .resizable()
            .frame(width: geometry.discWellDiameter, height: geometry.discWellDiameter)
            .scaleEffect(x: 1, y: cos(geometry.tiltDegrees * .pi / 180))
            .position(x: geometry.discCenter.x, y: geometry.projectedY(geometry.discCenter.y))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

private struct CDPlayerBodyShellView: View {
    let player: CDMechanism
    private var geometry: CDPlayerConfiguration.Geometry { player.configuration.geometry }

    var body: some View {
        Image(player.configuration.assets.body)
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
    let player: CDMechanism
    let scale: CGFloat
    let isPlaying: Bool
    private var geometry: CDPlayerConfiguration.Geometry { player.configuration.geometry }
    private var motion: CDMotionDriver { player.motion }
    private var rotationIdentity: String {
        "\(player.disc?.id ?? "empty"):\(player.position == .stored ? "stored" : "active")"
    }

    var body: some View {
        CDContinuousRotationLayer(
            identity: rotationIdentity,
            isRotating: isPlaying && !motion.reducedMotion,
            revolutionsPerMinute: BSListeningTokens.discRotationRPM
        ) {
            ListeningDiscArtwork(disc: player.disc, image: player.configuration.assets.disc)
        }
            .frame(width: geometry.discDiameter, height: geometry.discDiameter)
            .scaleEffect(motion.discScale.value)
            .opacity(player.position == .stored ? 0 : 1)
            .scaleEffect(x: 1, y: cos(geometry.tiltDegrees * .pi / 180))
            .shadow(color: .black.opacity(0.3), radius: 3 + motion.lift.value * 9, y: 4 + motion.lift.value * 13)
            .contentShape(Circle())
            .gesture(DragGesture(minimumDistance: 5, coordinateSpace: .named("playerStage"))
                .onChanged { value in
                    player.dragDisc(CGSize(width: value.translation.width / scale,
                                           height: value.translation.height / scale / cos(geometry.tiltDegrees * .pi / 180)))
                }.onEnded { _ in player.endDiscDrag() })
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(player.disc?.title ?? "CD") CD")
            .accessibilityAction(named: BSLocalization.text("取出")) { player.removeDisc() }
            .accessibilityAction(named: BSLocalization.text("放回唱片柜")) {
                if player.position == .seated { player.returnCurrentDiscToCabinet() }
                else { player.returnDisc() }
            }
            .accessibilityAction(named: BSLocalization.text("放入")) { player.insertDisc() }
            .position(x: motion.discX.value, y: geometry.projectedY(motion.discY.value) - (motion.reducedMotion ? 0 : motion.lift.value * 20))
            .allowsHitTesting(player.position != .stored && !player.isReturning)
            .phaseAnimator([false, true, false], trigger: player.occupiedAttemptCount) { content, emphasized in
                content.scaleEffect(emphasized && !motion.reducedMotion ? 1.035 : 1)
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
    let player: CDMechanism
    let scale: CGFloat
    private var geometry: CDPlayerConfiguration.Geometry { player.configuration.geometry }
    private var motion: CDMotionDriver { player.motion }
    private var lidAngle: Double {
        geometry.tiltDegrees + motion.lid.value * geometry.maximumOpening
    }
    private var isShowingBackFace: Bool {
        cos(lidAngle * .pi / 180) < 0
    }
    private var usesTransparentOuterLid: Bool {
        !isShowingBackFace && player.hasDisc
    }

    var body: some View {
        ZStack {
            // The visible top cover itself becomes clear acrylic only while a
            // disc is seated underneath it. With an empty tray, retain the
            // original opaque photographed lid.
            Image(player.configuration.assets.lidOuter).resizable()
                .opacity(isShowingBackFace ? 0 : (usesTransparentOuterLid ? BSListeningTokens.loadedLidOpacity : 1))

            // The inside face is not part of the transparent treatment.
            Image(player.configuration.assets.lidInner).resizable()
                .opacity(isShowingBackFace ? 1 : 0)

            if usesTransparentOuterLid {
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
                .mask(Image(player.configuration.assets.lidOuter).resizable())

                // Keep the acrylic rim readable even though the disc is visible
                // through the center of the closed top cover.
                Ellipse()
                    .strokeBorder(.white.opacity(0.28), lineWidth: 2.2)
                    .padding(2)
                Ellipse()
                    .strokeBorder(.black.opacity(0.16), lineWidth: 1)
                    .padding(5)
            }

            LinearGradient(
                colors: [
                    .white.opacity((usesTransparentOuterLid ? 0.025 : 0.07) * motion.lid.value),
                    .clear,
                    .black.opacity((usesTransparentOuterLid ? 0.035 : 0.10) * motion.lid.value)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .mask(
                Image(isShowingBackFace ? player.configuration.assets.lidInner : player.configuration.assets.lidOuter)
                    .resizable()
            )
        }
        .frame(width: geometry.lid.width, height: geometry.lid.height)
        .contentShape(Ellipse())
        .modifier(HingedPlane(angle: lidAngle))
        .offset(x: geometry.lid.minX, y: geometry.hingeY)
        .gesture(DragGesture(minimumDistance: 3, coordinateSpace: .named("playerStage"))
            .onChanged { value in player.dragLid(value.translation.height / scale) }
            .onEnded { value in player.endLidDrag(value.translation.height / scale,
                                                predicted: value.predictedEndTranslation.height / scale) })
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(BSLocalization.text("播放器上盖"))
        .accessibilityValue(BSLocalization.text(player.isOpen ? "已打开" : "已合上"))
        .accessibilityAction(named: BSLocalization.text("打开")) { player.setLid(open: true) }
        .accessibilityAction(named: BSLocalization.text("合上")) { player.setLid(open: false) }
    }
}

private struct CDPlayerLCDView: View {
    let room: ListeningRoomCoordinator
    private var player: CDMechanism { room.mechanism }
    private var geometry: CDPlayerConfiguration.Geometry { player.configuration.geometry }

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(!player.hasDisc ? "NO DISC" : room.track?.title ?? "")
                .font(.system(size: 9, weight: .semibold, design: .monospaced)).lineLimit(1)
            Text(player.hasDisc ? room.track?.artistName ?? "—" : "—")
                .font(.system(size: 7, weight: .medium, design: .monospaced)).lineLimit(1)
            HStack(spacing: 3) {
                Text(player.hasDisc ? String(format: "TR %02d", room.trackIndex + 1) : "TR --")
                Spacer(minLength: 0)
                if player.hasDisc {
                    Text(room.isPlaying ? "▶ \(room.timeText)" : "⏸ \(room.timeText)")
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
    private var geometry: CDPlayerConfiguration.Geometry { room.mechanism.configuration.geometry }
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
                .accessibilityLabel(BSLocalization.text(control == .playPause ? (room.isPlaying ? "暂停" : "播放") : control.label))
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
