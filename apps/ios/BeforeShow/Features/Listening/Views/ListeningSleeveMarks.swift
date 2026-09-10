import SwiftUI

struct ListeningSleeveMarks: View {
    let room: ListeningRoomCoordinator
    let disc: ListeningDisc

    var body: some View {
        Group {
            if room.containsHeardSongs(disc) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(BSColor.Stage.accent)
                    .accessibilityLabel(BSLocalization.text("包含听过的歌曲"))
            }
        }
    }

    static func accessibilityText(room: ListeningRoomCoordinator, disc: ListeningDisc) -> String {
        [
            room.isPlayingDisc(disc) ? BSLocalization.text("正在播放") : nil,
            room.isRecentDisc(disc) ? BSLocalization.text("最近播放") : nil,
            room.containsHeardSongs(disc) ? BSLocalization.text("包含听过的歌曲") : nil
        ].compactMap { $0 }.joined(separator: ", ")
    }
}
