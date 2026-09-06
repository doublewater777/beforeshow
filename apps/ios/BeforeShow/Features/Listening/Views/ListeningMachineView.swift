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
    private var motion: CDMotionDriver { player.motion }
    private var lidAngle: Double { geometry.tiltDegrees + motion.lid.value * geometry.maximumOpening }
    var body: some View {
        ZStack(alignment: .topLeading) {
            Ellipse()
                .fill(.black.opacity(0.45)).blur(radius: 22)
                .frame(width: 370, height: 130).position(x: 232, y: 679)
            Image(player.configuration.assets.body).resizable()
                .frame(width: geometry.body.width, height: geometry.body.height)
                .scaleEffect(x: 1, y: cos(geometry.tiltDegrees * .pi / 180),
                             anchor: UnitPoint(x: 0.5, y: (geometry.hingeY - geometry.body.minY) / geometry.body.height))
                .position(x: geometry.body.midX, y: geometry.body.midY)
                .allowsHitTesting(false)
            discView.zIndex(player.position == .seated ? 1 : 4)
            spindle.zIndex(2)
            lid.zIndex(3)
            lcd.zIndex(5)
            ForEach(CDControl.allCases) { control in
                if let rect = geometry.controls[control] {
                    Button { room.perform(control) } label: {
                        RoundedRectangle(cornerRadius: 10).fill(.white.opacity(0.001))
                            .frame(width: max(rect.width, 44 / scale), height: max(rect.height, 44 / scale))
                    }
                    .disabled(control == .playPause && ListeningPlaybackSourceResolver.resolve(capability: room.capability(for: room.track)) == nil)
                    .buttonStyle(CDHardwareButtonStyle())
                    .accessibilityLabel(BSLocalization.text(control.label))
                    .accessibilityIdentifier(control.rawValue)
                    .position(x: rect.midX, y: geometry.projectedY(rect.midY)).zIndex(6)
                }
            }
        }
        .frame(width: geometry.canvas.width, height: geometry.canvas.height)
        .allowsHitTesting(!player.isAutomatic)
        .disabled(player.isAutomatic)
        .scaleEffect(scale, anchor: .topLeading)
        .frame(width: geometry.canvas.width * scale, height: geometry.canvas.height * scale, alignment: .topLeading)
    }
    private var lid: some View {
        ZStack {
            // At the face boundary the plane has zero projected area. There is
            // no crossfade, duplicate object, layout mutation or moving anchor.
            Image(player.configuration.assets.lidOuter).resizable()
                .opacity(cos(lidAngle * .pi / 180) >= 0 ? 1 : 0)
            Image(player.configuration.assets.lidInner).resizable()
                .opacity(cos(lidAngle * .pi / 180) < 0 ? 1 : 0)
            LinearGradient(colors: [.white.opacity(0.07 * motion.lid.value), .clear, .black.opacity(0.10 * motion.lid.value)], startPoint: .top, endPoint: .bottom)
                .mask(Image(player.configuration.assets.lidOuter).resizable())
        }
        .frame(width: geometry.lid.width, height: geometry.lid.height)
        .contentShape(Ellipse())
        .modifier(HingedPlane(angle: lidAngle))
        .offset(x: geometry.lid.minX, y: geometry.hingeY)
        .highPriorityGesture(DragGesture(minimumDistance: 3, coordinateSpace: .named("playerStage"))
            .onChanged { value in player.dragLid( value.translation.height / scale) }
            .onEnded { value in player.endLidDrag( value.translation.height / scale,
                                                predicted: value.predictedEndTranslation.height / scale) })
        .accessibilityLabel(BSLocalization.text("播放器上盖"))
        .accessibilityValue(BSLocalization.text(player.isOpen ? "已打开" : "已合上"))
        .accessibilityAction(named: BSLocalization.text("打开")) { player.setLid(open: true) }
        .accessibilityAction(named: BSLocalization.text("合上")) { player.setLid(open: false) }
    }
    private var discView: some View {
        ListeningDiscArtwork(disc: player.disc, image: player.configuration.assets.disc)
            .frame(width: geometry.discDiameter, height: geometry.discDiameter)
            .scaleEffect(motion.discScale.value)
            .opacity(player.position == .stored ? 0 : 1)
            .scaleEffect(x: 1, y: cos(geometry.tiltDegrees * .pi / 180))
            .shadow(color: .black.opacity(0.3), radius: 3 + motion.lift.value * 9, y: 4 + motion.lift.value * 13)
            .contentShape(Circle())
            .highPriorityGesture(DragGesture(minimumDistance: 5, coordinateSpace: .named("playerStage"))
                .onChanged { value in
                    player.dragDisc(CGSize(width: value.translation.width / scale,
                                           height: value.translation.height / scale / cos(geometry.tiltDegrees * .pi / 180)))
                }.onEnded { _ in player.endDiscDrag() })
            .onTapGesture { if player.position == .released { player.seatDisc() } }
            .accessibilityLabel("\(player.disc?.title ?? "CD") CD")
            .accessibilityAction(named: BSLocalization.text("取出")) { player.removeDisc() }
            .accessibilityAction(named: BSLocalization.text("放入")) { player.insertDisc() }
            .accessibilityAction(named: BSLocalization.text("卡入中心轴")) { player.seatDisc() }
            .position(x: motion.discX.value, y: geometry.projectedY(motion.discY.value) - motion.lift.value * 20)
            .allowsHitTesting(player.position != .stored && !player.isReturning)
    }
    private var spindle: some View {
        Button { player.releaseDisc() } label: {
            ZStack {
                Circle().fill(LinearGradient(colors: [Color(white: 0.30), .black, Color(white: 0.22)], startPoint: .topLeading, endPoint: .bottomTrailing))
                Circle().stroke(Color(white: 0.48), lineWidth: 1).padding(4)
                Circle().fill(Color(white: 0.12)).padding(12)
                Circle().fill(Color(white: 0.62)).frame(width: 8, height: 8)
            }.frame(width: 42, height: 42)
        }
        .buttonStyle(CDHardwareButtonStyle())
        .position(x: geometry.discCenter.x, y: geometry.projectedY(geometry.discCenter.y))
        .disabled(!player.isOpen || player.position != .seated)
        .accessibilityLabel(BSLocalization.text("释放 CD 中心轴"))
    }
    private var lcd: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(!player.hasDisc ? "--" : String(format: "%02d", room.trackIndex + 1))
                    .font(.system(size: 15, weight: .medium, design: .monospaced))
                Text(room.timeText).font(.system(size: 14, weight: .medium, design: .monospaced))
                Spacer(minLength: 0)
                Image(systemName: room.isPlaying ? "play.fill" : "stop.fill")
                    .font(.system(size: 6))
            }
            Text(!player.hasDisc ? "NO DISC" : room.track?.title.uppercased() ?? "")
                .font(.system(size: 6.8, weight: .semibold, design: .monospaced))
                .lineLimit(1).minimumScaleFactor(0.7)
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

struct CDHardwareButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .overlay(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(configuration.isPressed ? 0.20 : 0)))
            .offset(y: configuration.isPressed ? 1 : 0)
    }
}

