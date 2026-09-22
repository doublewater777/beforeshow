import SwiftUI

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
                isPlaying: room.isPlaying
            )
            .frame(
                width: geometry.discDiameter * 3.75,
                height: geometry.discDiameter * 2.15
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
            crystalBodySurface
            CDPlayerDiscView(player: player, scale: scale)
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

    private var crystalBodySurface: some View {
        ZStack {
            // The asset now carries the acrylic thickness, bevels and colored
            // refraction. SwiftUI only adds a faint live-material response so the
            // hardware remains integrated with the current room background.
            Image(player.configuration.assets.body)
                .resizable()

            Rectangle()
                .fill(.ultraThinMaterial)
                .opacity(0.13)
                .mask(Image(player.configuration.assets.body).resizable())

            LinearGradient(
                colors: [
                    .white.opacity(0.08),
                    .clear,
                    BSColor.Stage.accent.opacity(room.isPlaying ? 0.055 : 0.025)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .mask(Image(player.configuration.assets.body).resizable())
        }
        .compositingGroup()
        .frame(width: geometry.body.width, height: geometry.body.height)
        .scaleEffect(
            x: 1,
            y: cos(geometry.tiltDegrees * .pi / 180),
            anchor: UnitPoint(
                x: 0.5,
                y: (geometry.hingeY - geometry.body.minY) / geometry.body.height
            )
        )
        .position(x: geometry.body.midX, y: geometry.body.midY)
        .shadow(color: .white.opacity(0.10), radius: 12, y: -2)
        .shadow(color: .black.opacity(0.22), radius: 18, y: 12)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var spindle: some View {
        ZStack {
            Circle()
                .fill(.ultraThinMaterial)
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            .white.opacity(0.48),
                            Color(red: 0.72, green: 0.92, blue: 1).opacity(0.16),
                            .clear
                        ],
                        center: .topLeading,
                        startRadius: 1,
                        endRadius: 28
                    )
                )
            Circle().stroke(.white.opacity(0.52), lineWidth: 1).padding(3)
            Circle().stroke(.black.opacity(0.16), lineWidth: 1).padding(7)
            Circle().fill(.white.opacity(0.56)).frame(width: 8, height: 8)
        }
        .frame(width: 42, height: 42)
        .position(x: geometry.discCenter.x, y: geometry.projectedY(geometry.discCenter.y))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct CDPlayerDiscView: View {
    let player: CDMechanism
    let scale: CGFloat
    private var geometry: CDPlayerConfiguration.Geometry { player.configuration.geometry }
    private var motion: CDMotionDriver { player.motion }

    var body: some View {
        ListeningDiscArtwork(disc: player.disc, image: player.configuration.assets.disc)
            .frame(width: geometry.discDiameter, height: geometry.discDiameter)
            .scaleEffect(motion.discScale.value)
            .rotationEffect(.degrees(motion.discAngle))
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
    private var visibleLidAsset: String {
        isShowingBackFace ? player.configuration.assets.lidInner : player.configuration.assets.lidOuter
    }

    var body: some View {
        ZStack {
            Image(visibleLidAsset)
                .resizable()

            Rectangle()
                .fill(.ultraThinMaterial)
                .opacity(isShowingBackFace ? 0.10 : 0.07)
                .mask(Image(visibleLidAsset).resizable())

            // Opening changes only the live reflection; the vector asset owns the
            // actual crystal rim so the lid does not turn milky over the album art.
            LinearGradient(
                colors: [
                    .white.opacity(0.055 * motion.lid.value),
                    .clear,
                    .black.opacity(0.025 * motion.lid.value)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .mask(Image(visibleLidAsset).resizable())
        }
        .compositingGroup()
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
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(!player.hasDisc ? "NO DISC" : room.track?.title ?? "")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color(red: 0.94, green: 0.96, blue: 0.94))
                    .lineLimit(1)
                Spacer(minLength: 2)
                if player.hasDisc {
                    Text("HI-RES")
                        .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color(red: 0.88, green: 0.92, blue: 0.88).opacity(0.60))
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(player.hasDisc ? room.track?.artistName ?? "—" : "—")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color(red: 0.82, green: 0.85, blue: 0.82).opacity(0.70))
                    .lineLimit(1)
                Spacer(minLength: 2)
                if player.hasDisc {
                    Text("24b/96k")
                        .font(.system(size: 7.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color(red: 0.82, green: 0.85, blue: 0.82).opacity(0.45))
                }
            }
            HStack(spacing: 4) {
                Text(player.hasDisc ? String(format: "TR %02d", room.trackIndex + 1) : "TR --")
                Spacer(minLength: 0)
                if player.hasDisc {
                    Text(room.isPlaying ? "▶ \(room.timeText)" : "⏸ \(room.timeText)")
                }
            }
            .font(.system(size: 9, weight: .medium, design: .monospaced))
            .foregroundStyle(Color(red: 0.88, green: 0.92, blue: 0.88).opacity(0.90))
            .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .frame(width: geometry.lcd.width, height: geometry.lcd.height)
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
