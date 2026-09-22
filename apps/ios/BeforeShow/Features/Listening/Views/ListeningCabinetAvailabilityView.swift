import SwiftUI

struct ListeningCabinetAvailabilityView: View {
    let room: ListeningRoomCoordinator
    let connectArtist: () -> Void

    var body: some View {
        if room.isAuthorizing || !room.accessResolved ||
            ((room.catalogState == .loading || room.isCatalogEnriching) && room.libraryDiscs.isEmpty) {
            ListeningCatalogStatusView(title: ListeningCopy.text("连接中…"), isLoading: true)
        } else if let recovery = room.display.recoveryAction {
            ListeningCatalogStatusView(
                title: recovery == .retryCatalog ? BSLocalization.text("暂时无法载入音乐") : BSLocalization.text("连接 Apple Music"),
                actionTitle: recovery.title
            ) { room.performListeningRecovery(recovery) }
        } else if room.presentation == .noConnectedArtists {
            ListeningCatalogStatusView(
                title: BSLocalization.text("尚未匹配 Apple Music 艺人"),
                actionTitle: BSLocalization.text("连接艺人"),
                action: connectArtist
            )
        } else if room.libraryDiscs.isEmpty {
            ListeningCatalogStatusView(title: BSLocalization.text("唱片柜暂无唱片"))
        }
    }
}
