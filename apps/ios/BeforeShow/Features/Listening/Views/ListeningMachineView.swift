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
            CDPlayerBodyShellView(player: player)
                .zIndex(0)
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
        .frame(width: 26, height: 26)
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

private struct CDPlayerBodyShellView: View {
    let player: CDMechanism
    private var geometry: CDPlayerConfiguration.Geometry { player.configuration.geometry }

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 34)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.28, green: 0.26, blue: 0.24),
                            Color(red: 0.13, green: 0.13, blue: 0.14),
                            Color(red: 0.20, green: 0.18, blue: 0.17)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 34)
                        .stroke(.white.opacity(0.11), lineWidth: 1)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 31)
                        .stroke(BSColor.Stage.accent.opacity(0.16), lineWidth: 1)
                        .padding(3)
                )
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

            tray
            hingeBridge
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var tray: some View {
        ZStack {
            Ellipse()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 0.11, green: 0.11, blue: 0.12),
                            Color(red: 0.045, green: 0.045, blue: 0.05)
                        ],
                        center: .center,
                        startRadius: 28,
                        endRadius: geometry.discDiameter * 0.62
                    )
                )
            Ellipse()
                .stroke(.white.opacity(0.07), lineWidth: 1)
                .padding(3)
            Ellipse()
                .stroke(BSColor.Stage.accent.opacity(0.12), lineWidth: 1.5)
                .padding(10)
            Ellipse()
                .stroke(.black.opacity(0.72), lineWidth: 8)
                .padding(17)
        }
        .frame(
            width: geometry.discDiameter + 54,
            height: (geometry.discDiameter + 54) * cos(geometry.tiltDegrees * .pi / 180)
        )
        .position(
            x: geometry.discCenter.x,
            y: geometry.projectedY(geometry.discCenter.y)
        )
        .shadow(color: .black.opacity(0.36), radius: 9, y: 5)
    }

    private var hingeBridge: some View {
        Capsule()
            .fill(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.11),
                        Color.black.opacity(0.55),
                        Color.white.opacity(0.06)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .overlay(Capsule().stroke(.white.opacity(0.08), lineWidth: 1))
            .frame(width: 112, height: 18)
            .position(x: geometry.body.midX, y: geometry.projectedY(geometry.hingeY + 8))
            .shadow(color: .black.opacity(0.34), radius: 4, y: 2)
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
            if isShowingBackFace {
                innerFace
            } else if usesTransparentOuterLid {
                transparentOuterFace
            } else {
                opaqueOuterFace
            }
        }
        .frame(width: geometry.lid.width, height: geometry.lid.height)
        .contentShape(Ellipse())
        .modifier(HingedPlane(angle: lidAngle))
        .offset(x: geometry.lid.minX, y: geometry.hingeY)
        .shadow(
            color: .black.opacity(0.20 + 0.20 * motion.lid.value),
            radius: 9 + 8 * motion.lid.value,
            y: 5 + 7 * motion.lid.value
        )
        .gesture(
            DragGesture(minimumDistance: 3, coordinateSpace: .named("playerStage"))
                .onChanged { value in
                    player.dragLid(value.translation.height / scale)
                }
                .onEnded { value in
                    player.endLidDrag(
                        value.translation.height / scale,
                        predicted: value.predictedEndTranslation.height / scale
                    )
                }
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(BSLocalization.text("播放器上盖"))
        .accessibilityValue(BSLocalization.text(player.isOpen ? "已打开" : "已合上"))
        .accessibilityAction(named: BSLocalization.text("打开")) { player.setLid(open: true) }
        .accessibilityAction(named: BSLocalization.text("合上")) { player.setLid(open: false) }
    }

    private var opaqueOuterFace: some View {
        ZStack {
            Ellipse()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 0.30, green: 0.28, blue: 0.26),
                            Color(red: 0.15, green: 0.145, blue: 0.15),
                            Color(red: 0.075, green: 0.075, blue: 0.085)
                        ],
                        center: .topLeading,
                        startRadius: 18,
                        endRadius: geometry.lid.width * 0.58
                    )
                )
            Ellipse()
                .stroke(BSColor.Stage.accent.opacity(0.24), lineWidth: 2)
                .padding(2)
            Ellipse()
                .stroke(.white.opacity(0.11), lineWidth: 1)
                .padding(7)
            metallicSweep.opacity(0.32)
        }
    }

    private var transparentOuterFace: some View {
        ZStack {
            Ellipse()
                .fill(Color.black.opacity(0.13))
            Ellipse()
                .fill(
                    LinearGradient(
                        colors: [
                            .white.opacity(0.10),
                            .white.opacity(0.018),
                            .clear,
                            .black.opacity(0.05)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Ellipse()
                .stroke(BSColor.Stage.accent.opacity(0.30), lineWidth: 3)
                .padding(1)
            Ellipse()
                .stroke(.white.opacity(0.26), lineWidth: 1.2)
                .padding(6)
            Ellipse()
                .stroke(.black.opacity(0.42), lineWidth: 7)
                .padding(12)

            Capsule()
                .fill(.white.opacity(0.11))
                .frame(width: geometry.lid.width * 0.30, height: 20)
                .rotationEffect(.degrees(-28))
                .offset(x: -geometry.lid.width * 0.18, y: -geometry.lid.height * 0.20)
                .blur(radius: 4)
        }
        .compositingGroup()
    }

    private var innerFace: some View {
        ZStack {
            Ellipse()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 0.12, green: 0.12, blue: 0.13),
                            Color(red: 0.045, green: 0.045, blue: 0.052)
                        ],
                        center: .center,
                        startRadius: 30,
                        endRadius: geometry.lid.width * 0.55
                    )
                )
            Ellipse()
                .stroke(.white.opacity(0.08), lineWidth: 1)
                .padding(5)
            Ellipse()
                .stroke(.black.opacity(0.62), lineWidth: 10)
                .padding(14)
            Ellipse()
                .stroke(BSColor.Stage.accent.opacity(0.10), lineWidth: 1.5)
                .padding(25)
        }
    }

    private var metallicSweep: some View {
        AngularGradient(
            colors: [
                .white.opacity(0.18),
                .clear,
                BSColor.Stage.accent.opacity(0.10),
                .clear,
                .white.opacity(0.08),
                .clear
            ],
            center: .center
        )
        .mask(Ellipse())
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

private enum LCDPlaybackStatus: Equatable {
    case noDisc, ready, playing, paused

    var label: String {
        switch self {
        case .noDisc: "STANDBY"
        case .ready: "READY"
        case .playing: "PLAY"
        case .paused: "PAUSE"
        }
    }
}

private struct CDPlayerLCDView: View {
    let room: ListeningRoomCoordinator
    private var player: CDMechanism { room.mechanism }
    private var geometry: CDPlayerConfiguration.Geometry { player.configuration.geometry }

    private var status: LCDPlaybackStatus {
        if !player.hasDisc { return .noDisc }
        if room.isPlaying { return .playing }
        if room.track != nil { return .paused }
        return .ready
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(player.hasDisc ? (room.track?.title ?? player.disc?.title ?? "CD") : "NO DISC")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.94))
                    .lineLimit(1)

                Text(player.hasDisc ? (room.track?.artistName ?? "—") : BSLocalization.text("选择一张唱片开始播放"))
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.56))
                    .lineLimit(1)

                CDPlayerLCDStatusView(
                    hasDisc: player.hasDisc,
                    trackIndex: room.trackIndex,
                    trackCount: max(player.disc?.tracks.count ?? 0, 1),
                    timeText: room.timeText,
                    status: status
                )
            }

            Spacer(minLength: 8)
            CDPlayerLCDMeterView(status: status)
        }
        .padding(.horizontal, 14)
        .frame(width: geometry.lcd.width, height: geometry.lcd.height)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.026, green: 0.052, blue: 0.061),
                            Color(red: 0.012, green: 0.018, blue: 0.022)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.14), lineWidth: 1))
                .overlay(
                    RoundedRectangle(cornerRadius: 9)
                        .stroke(Color(red: 0.66, green: 0.88, blue: 0.91).opacity(status == .playing ? 0.11 : 0.05), lineWidth: 1)
                        .padding(3)
                )
        )
        .shadow(color: .black.opacity(0.42), radius: 7, y: 4)
        .position(x: geometry.lcd.midX, y: geometry.projectedY(geometry.lcd.midY))
        .animation(.easeInOut(duration: 0.18), value: status)
        .accessibilityElement(children: .combine)
    }
}

private struct CDPlayerLCDStatusView: View {
    let hasDisc: Bool
    let trackIndex: Int
    let trackCount: Int
    let timeText: String
    let status: LCDPlaybackStatus

    var body: some View {
        HStack(spacing: 10) {
            if hasDisc {
                Text(String(format: "%02d / %02d", trackIndex + 1, trackCount))
                Text(timeText)
            } else {
                Text("READY")
            }
            Spacer(minLength: 0)
            Text(status.label)
                .contentTransition(.opacity)
        }
        .animation(.easeInOut(duration: 0.16), value: status)
        .font(.system(size: 7.5, weight: .semibold, design: .monospaced))
        .foregroundStyle(Color(red: 0.69, green: 0.84, blue: 0.86).opacity(0.84))
        .lineLimit(1)
    }
}

private struct CDPlayerLCDMeterView: View {
    let status: LCDPlaybackStatus
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let baseHeights: [CGFloat] = [7, 13, 10, 18, 12, 20, 9]

    var body: some View {
        TimelineView(
            .animation(
                minimumInterval: 1.0 / 12.0,
                paused: status != .playing || reduceMotion
            )
        ) { context in
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(baseHeights.indices, id: \.self) { index in
                    Capsule()
                        .fill(Color(red: 0.66, green: 0.88, blue: 0.91).opacity(opacity))
                        .frame(width: 2.5, height: barHeight(at: index, date: context.date))
                        .animation(.easeOut(duration: 0.10), value: status)
                }
            }
        }
        .frame(width: 34, height: 22, alignment: .bottom)
        .accessibilityHidden(true)
    }

    private func barHeight(at index: Int, date: Date) -> CGFloat {
        let full = baseHeights[index]

        switch status {
        case .playing:
            guard !reduceMotion else { return full }
            let phase = date.timeIntervalSinceReferenceDate * 5.8 + Double(index) * 0.83
            let wave = (sin(phase) + sin(phase * 0.53 + Double(index))) * 0.25 + 0.5
            return max(4, full * CGFloat(0.48 + wave * 0.52))
        case .paused:
            return max(4, full * 0.28)
        case .ready:
            return max(3, full * 0.18)
        case .noDisc:
            return 2
        }
    }

    private var opacity: Double {
        switch status {
        case .playing: 0.84
        case .paused: 0.38
        case .ready: 0.28
        case .noDisc: 0.14
        }
    }
}

private enum CDPlayerButtonRole: Equatable {
    case primary, secondary, mechanical
}

private struct CDPlayerButtonFace<Content: View>: View {
    let role: CDPlayerButtonRole
    let isActive: Bool
    let size: CGSize
    private let content: Content

    init(
        role: CDPlayerButtonRole,
        isActive: Bool,
        size: CGSize,
        @ViewBuilder content: () -> Content
    ) {
        self.role = role
        self.isActive = isActive
        self.size = size
        self.content = content()
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: fillColors,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Circle().stroke(rimColor, lineWidth: role == .primary ? 2 : 1)

            if role == .primary {
                Circle()
                    .stroke(BSColor.Stage.accent.opacity(isActive ? 0.24 : 0.08), lineWidth: 5)
                    .blur(radius: 5)
                    .padding(2)
            }

            content
        }
        .frame(width: size.width, height: size.height)
        .shadow(color: shadowColor, radius: role == .primary ? 8 : 4, y: 2)
        .animation(.easeInOut(duration: 0.18), value: isActive)
        .contentShape(Circle())
    }

    private var fillColors: [Color] {
        switch role {
        case .primary:
            [
                Color.white.opacity(isActive ? 0.18 : 0.13),
                Color(red: 0.11, green: 0.10, blue: 0.095),
                Color.black.opacity(0.48)
            ]
        case .secondary:
            [
                Color.white.opacity(0.09),
                Color(red: 0.10, green: 0.10, blue: 0.105),
                Color.black.opacity(0.46)
            ]
        case .mechanical:
            [
                BSColor.Stage.accent.opacity(isActive ? 0.14 : 0.08),
                Color(red: 0.12, green: 0.105, blue: 0.09),
                Color.black.opacity(0.48)
            ]
        }
    }

    private var rimColor: Color {
        switch role {
        case .primary:
            BSColor.Stage.accent.opacity(isActive ? 0.90 : 0.56)
        case .secondary:
            Color.white.opacity(0.14)
        case .mechanical:
            BSColor.Stage.accent.opacity(isActive ? 0.62 : 0.28)
        }
    }

    private var shadowColor: Color {
        switch role {
        case .primary:
            BSColor.Stage.accent.opacity(isActive ? 0.20 : 0.09)
        case .mechanical where isActive:
            BSColor.Stage.accent.opacity(0.12)
        case .secondary, .mechanical:
            .black.opacity(0.28)
        }
    }
}

private struct CDPlayerControlIcon: View {
    let control: CDControl
    let isPlaying: Bool
    let isLidOpen: Bool

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(Color.white.opacity(control == .open && isLidOpen ? 1 : 0.90))
            .offset(
                x: control == .playPause && !isPlaying ? 1.5 : 0,
                y: control == .open && isLidOpen ? -1 : 0
            )
            .rotationEffect(.degrees(control == .open && isLidOpen ? -6 : 0))
            .animation(.easeInOut(duration: 0.18), value: isLidOpen)
            .accessibilityHidden(true)
    }

    private var symbol: String {
        switch control {
        case .previous: "backward.end.fill"
        case .next: "forward.end.fill"
        case .playPause: isPlaying ? "pause.fill" : "play.fill"
        case .open: "eject.fill"
        case .stop: "stop.fill"
        }
    }

    private var size: CGFloat {
        switch control {
        case .playPause: 22
        case .open: 15
        case .previous, .next, .stop: 17
        }
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
                    CDPlayerButtonFace(
                        role: role(for: control),
                        isActive: isActive(control),
                        size: rect.size
                    ) {
                        CDPlayerControlIcon(
                            control: control,
                            isPlaying: room.isPlaying,
                            isLidOpen: room.mechanism.isOpen
                        )
                    }
                    .frame(
                        width: max(rect.width, 44 / scale),
                        height: max(rect.height, 44 / scale)
                    )
                }
                .disabled(control == .playPause && !playerPresentation.canPlayPause)
                .buttonStyle(CDHardwareButtonStyle())
                .accessibilityLabel(
                    BSLocalization.text(
                        control == .playPause ? (room.isPlaying ? "暂停" : "播放") : control.label
                    )
                )
                .accessibilityValue(control == .playPause ? playerPresentation.statusText : "")
                .accessibilityHint(control == .playPause ? (playerPresentation.blockingReason ?? "") : "")
                .accessibilityIdentifier(control.rawValue)
                .position(x: rect.midX, y: geometry.projectedY(rect.midY))
            }
        }
    }

    private func role(for control: CDControl) -> CDPlayerButtonRole {
        switch control {
        case .playPause: .primary
        case .open: .mechanical
        case .previous, .next, .stop: .secondary
        }
    }

    private func isActive(_ control: CDControl) -> Bool {
        switch control {
        case .playPause:
            room.isPlaying
        case .open:
            room.mechanism.isOpen
        case .previous, .next, .stop:
            false
        }
    }
}

struct CDHardwareButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .offset(y: configuration.isPressed ? 1.5 : 0)
            .animation(.easeOut(duration: 0.10), value: configuration.isPressed)
            .sensoryFeedback(.impact(weight: .light, intensity: 0.7), trigger: configuration.isPressed)
    }
}
