import SwiftUI

struct ListeningOverviewStatus: View {
    @Bindable var room: ListeningRoomCoordinator
    let onMatchArtist: (ListeningBrowseArtist) -> Void

    var body: some View {
        switch room.display.catalogChrome {
        case .preparing:
            ProgressView().frame(maxWidth: .infinity).padding(.top, BSSpacing.xl)
        case .needsMusicAccess(let prompt):
            ListeningCatalogStatusView(
                title: BSLocalization.text("连接 Apple Music"),
                subtitle: Self.musicAccessSubtitle(prompt),
                icon: "music.note",
                actionTitle: room.display.recoveryAction?.title
            ) { recover() }
        case .connectArtist(let slotIndex, let name):
            ListeningCatalogStatusView(
                title: BSLocalization.text("尚未匹配 Apple Music 艺人"),
                icon: "link.badge.plus",
                actionTitle: BSLocalization.text("连接艺人")
            ) {
                if let artist = room.browseArtists.first(where: { $0.slotIndex == slotIndex })
                    ?? room.browseArtists.first(where: { $0.name == name }) {
                    onMatchArtist(artist)
                }
            }
        case .unavailable(let isStale):
            ListeningCatalogStatusView(
                title: BSLocalization.text(isStale ? "暂时无法更新专场唱片" : "暂时无法载入音乐"),
                icon: "wifi.exclamationmark",
                actionTitle: room.display.recoveryAction?.title
            ) { recover() }
        case .empty:
            ListeningCatalogStatusView(title: BSLocalization.text("暂时没有找到可翻的唱片"))
        }
    }

    private func recover() {
        if let action = room.display.recoveryAction { room.performListeningRecovery(action) }
    }

    private static func musicAccessSubtitle(_ prompt: ListeningMusicAccessPrompt) -> String {
        switch prompt {
        case .notDetermined: ListeningCopy.text("授权后载入唱片")
        case .denied: BSLocalization.text("请在系统设置中允许访问 Apple Music")
        case .restricted: ListeningCopy.text("Apple Music 访问受到系统限制，无法在此更改。")
        }
    }
}
