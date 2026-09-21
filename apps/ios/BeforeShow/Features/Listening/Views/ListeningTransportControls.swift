import SwiftUI

struct ListeningTransportControls: View {
    let room: ListeningRoomCoordinator

    var body: some View {
        HStack(spacing: BSSpacing.md) {
            transport(.previous, symbol: "backward.end.fill", label: BSLocalization.text("上一首"),
                      disabled: !room.mechanism.hasDisc || room.trackIndex == 0)
            transport(.playPause, symbol: room.isPlaying ? "pause.fill" : "play.fill",
                      label: BSLocalization.text(room.isPlaying ? "暂停" : "播放"),
                      disabled: !room.display.player.canPlayPause)
            transport(.next, symbol: "forward.end.fill", label: BSLocalization.text("下一首"),
                      disabled: !room.mechanism.hasDisc || room.trackIndex + 1 >= (room.mechanism.disc?.tracks.count ?? 0))
            Button(action: room.openCabinet) {
                ListeningTransportButtonFace(symbol: "opticaldisc", primary: false, active: false)
            }
            .accessibilityLabel(BSLocalization.text("换碟"))
            .accessibilityIdentifier("changeDisc")
        }
        .buttonStyle(ListeningTransportPressStyle())
        .disabled(room.busy || room.mechanism.isAutomatic)
    }

    private func transport(_ control: CDControl, symbol: String, label: String, disabled: Bool) -> some View {
        Button { room.perform(control) } label: {
            ListeningTransportButtonFace(symbol: symbol, primary: control == .playPause,
                                         active: control == .playPause && room.isPlaying)
        }
        .disabled(disabled)
        .opacity(disabled ? 0.38 : 1)
        .accessibilityLabel(label)
        .accessibilityHint(control == .playPause ? room.display.player.blockingReason ?? "" : "")
        .accessibilityIdentifier(control.rawValue)
    }
}
