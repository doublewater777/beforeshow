import SwiftUI

struct CDPlayerTransportControls: View {
    let room: ListeningRoomCoordinator
    let scale: CGFloat
    private var player: CDMechanism { room.mechanism }

    var body: some View {
        ForEach(CDPlayerSurfaceTokens.orderedControls) { control in
            if let rect = player.configuration.geometry.controls[control] {
                Button { room.perform(control) } label: {
                    CDPlayerControlFace(control: control, isPlaying: room.isPlaying, isOpen: player.isOpen)
                        .frame(width: rect.width, height: rect.height)
                        .frame(width: max(rect.width, BSLayout.minTouchTarget / scale),
                               height: max(rect.height, BSLayout.minTouchTarget / scale))
                        .contentShape(Circle())
                }
                .buttonStyle(BSListeningPressStyle())
                .disabled(isDisabled(control))
                .opacity(isDisabled(control) ? 0.38 : 1)
                .accessibilityLabel(label(control))
                .accessibilityHint(control == .playPause ? (room.display.player.blockingReason ?? "") : "")
                .accessibilityIdentifier(control.rawValue)
                .position(x: rect.midX, y: rect.midY)
            }
        }
    }

    private func isDisabled(_ control: CDControl) -> Bool {
        if room.busy || player.isAutomatic { return true }
        switch control {
        case .playPause: return !room.display.player.canPlayPause
        case .previous: return !player.isClosed || !player.hasDisc || room.trackIndex == 0
        case .next: return !player.isClosed || !player.hasDisc || room.trackIndex + 1 >= (player.disc?.tracks.count ?? 0)
        case .open: return room.cabinet.phase != .idle
        case .stop: return false
        }
    }

    private func label(_ control: CDControl) -> String {
        switch control {
        case .playPause: BSLocalization.text(room.isPlaying ? "暂停" : "播放")
        case .open: BSLocalization.text(player.isOpen ? "合上上盖" : "打开上盖")
        default: BSLocalization.text(control.label)
        }
    }
}
