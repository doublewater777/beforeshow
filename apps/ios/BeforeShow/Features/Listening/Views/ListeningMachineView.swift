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
            Image(player.configuration.assets.body).resizable()
                .frame(width: geometry.body.width, height: geometry.body.height)
                .scaleEffect(x: 1, y: cos(geometry.tiltDegrees * .pi / 180),
                             anchor: UnitPoint(x: 0.5, y: (geometry.hingeY - geometry.body.minY) / geometry.body.height))
                .position(x: geometry.body.midX, y: geometry.body.midY)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            CDPlayerLowerDeckSurface(player: player)
                .zIndex(0.5)
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

    private var spindle: some View {
        ZStack {
            Circle().fill(LinearGradient(colors: [Color(white: 0.30), .black, Color(white: 0.22)], startPoint: .topLeading, endPoint: .bottomTrailing))
            Circle().stroke(Color(white: 0.48), lineWidth: 1).padding(4)
            Circle().fill(Color(white: 0.12)).padding(12)
            Circle().fill(Color(white: 0.62)).frame(width: 8, height: 8)
        }
        .frame(width: 32, height: 32)
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
    private var usesTransparentOuterLid: Bool {
        !isShowingBackFace && player.hasDisc
    }

    var body: some View {
        ZStack {
            // The visible top cover itself becomes clear acrylic only while a
            // disc is seated underneath it. With an empty tray, retain the
            // original opaque photographed lid.
            Image(player.configuration.assets.lidOuter).resizable()
                .opacity(isShowingBackFace ? 0 : (usesTransparentOuterLid ? 0.16 : 1))

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

private struct CDPlayerLowerDeckSurface: View {
    let player: CDMechanism
    private var geometry: CDPlayerConfiguration.Geometry { player.configuration.geometry }

    var body: some View {
        let rect = geometry.lowerDeck
        let projectedHeight = rect.height * cos(geometry.tiltDegrees * .pi / 180)

        ZStack {
            RoundedRectangle(cornerRadius: 24)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.19, green: 0.18, blue: 0.17),
                            Color(red: 0.10, green: 0.10, blue: 0.11),
                            Color(red: 0.16, green: 0.14, blue: 0.13)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            RoundedRectangle(cornerRadius: 24)
                .stroke(.white.opacity(0.10), lineWidth: 1)
            RoundedRectangle(cornerRadius: 21)
                .stroke(BSColor.Stage.accent.opacity(0.14), lineWidth: 1)
                .padding(3)
        }
        .frame(width: rect.width, height: projectedHeight)
        .position(x: rect.midX, y: geometry.projectedY(rect.midY))
        .shadow(color: .black.opacity(0.38), radius: 10, y: 5)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct CDPlayerLCDView: View {
    let room: ListeningRoomCoordinator
    private var player: CDMechanism { room.mechanism }
    private var geometry: CDPlayerConfiguration.Geometry { player.configuration.geometry }

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(player.hasDisc ? (room.track?.title ?? player.disc?.title ?? "CD") : "NO DISC")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.94))
                    .lineLimit(1)

                Text(player.hasDisc
                     ? (room.track?.artistName ?? "—")
                     : BSLocalization.text("选择一张唱片开始播放"))
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.58))
                    .lineLimit(1)

                HStack(spacing: 8) {
                    if player.hasDisc {
                        Text(String(format: "%02d / %02d",
                                    room.trackIndex + 1,
                                    max(player.disc?.tracks.count ?? 0, 1)))
                        Text(room.timeText)
                    } else {
                        Text("READY")
                    }
                    Spacer(minLength: 0)
                    Text(room.isPlaying ? "PLAY" : (player.hasDisc ? "PAUSE" : "STANDBY"))
                }
                .font(.system(size: 7.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color(red: 0.69, green: 0.84, blue: 0.86).opacity(0.82))
            }

            Spacer(minLength: 0)

            HStack(alignment: .bottom, spacing: 2) {
                ForEach(0..<7, id: \.self) { index in
                    Capsule()
                        .fill(Color(red: 0.66, green: 0.88, blue: 0.91).opacity(room.isPlaying ? 0.82 : 0.28))
                        .frame(
                            width: 2.5,
                            height: room.isPlaying
                                ? CGFloat([7, 13, 10, 18, 12, 20, 9][index])
                                : 5
                        )
                }
            }
            .frame(width: 34, height: 22, alignment: .bottom)
        }
        .padding(.horizontal, 14)
        .frame(width: geometry.lcd.width, height: geometry.lcd.height)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.025, green: 0.055, blue: 0.065),
                            Color(red: 0.015, green: 0.020, blue: 0.025)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(.white.opacity(0.14), lineWidth: 1)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 9)
                        .stroke(Color(red: 0.66, green: 0.88, blue: 0.91).opacity(room.isPlaying ? 0.10 : 0.05), lineWidth: 1)
                        .padding(3)
                )
        )
        .shadow(color: .black.opacity(0.42), radius: 7, y: 4)
        .position(x: geometry.lcd.midX, y: geometry.projectedY(geometry.lcd.midY))
        .accessibilityElement(children: .combine)
    }
}

private struct CDPlayerControlsView: View {
    let room: ListeningRoomCoordinator
    let scale: CGFloat
    private var geometry: CDPlayerConfiguration.Geometry { room.mechanism.configuration.geometry }
    private var player: CDMechanism { room.mechanism }
    private var playerPresentation: ListeningPlayerPresentation { room.display.player }

    var body: some View {
        ForEach(CDControl.allCases) { control in
            if let rect = geometry.controls[control] {
                Button { room.perform(control) } label: {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(control == .playPause ? 0.15 : 0.09),
                                        Color.black.opacity(0.44)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                        Circle()
                            .stroke(
                                control == .playPause
                                    ? BSColor.Stage.accent.opacity(room.isPlaying ? 0.88 : 0.56)
                                    : Color.white.opacity(0.14),
                                lineWidth: control == .playPause ? 2 : 1
                            )
                        Image(systemName: symbol(for: control))
                            .font(.system(
                                size: control == .playPause ? 22 : (control == .open ? 15 : 17),
                                weight: .semibold
                            ))
                            .foregroundStyle(Color.white.opacity(0.90))
                            .offset(x: control == .playPause && !room.isPlaying ? 1.5 : 0)
                    }
                    .frame(width: rect.width, height: rect.height)
                    .shadow(
                        color: control == .playPause
                            ? BSColor.Stage.accent.opacity(room.isPlaying ? 0.20 : 0.10)
                            : .black.opacity(0.25),
                        radius: control == .playPause ? 8 : 4,
                        y: 2
                    )
                    .contentShape(Circle())
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

    private func symbol(for control: CDControl) -> String {
        switch control {
        case .previous:
            "backward.end.fill"
        case .next:
            "forward.end.fill"
        case .playPause:
            room.isPlaying ? "pause.fill" : "play.fill"
        case .open:
            "eject.fill"
        case .stop:
            "stop.fill"
        }
    }
}

struct CDHardwareButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.965 : 1)
            .offset(y: configuration.isPressed ? 1 : 0)
            .animation(.easeOut(duration: 0.10), value: configuration.isPressed)
            .sensoryFeedback(.impact(weight: .light, intensity: 0.7), trigger: configuration.isPressed)
    }
}
