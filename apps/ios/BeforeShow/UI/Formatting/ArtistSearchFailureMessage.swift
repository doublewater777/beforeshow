import Foundation

struct ArtistSearchFailureMessage {
    let title: String
    let detail: String
    let icon: String
    var actionTitle: String { BSLocalization.text("重试") }

    init(error: any Error) {
        switch error as? ArtistSearchError {
        case .catalogUnavailable:
            title = "Apple Music 搜索暂不可用"
            detail = "部分艺人可能无法搜到，请稍后再试。"
            icon = "music.note"
        case .rateLimited:
            title = "搜索过于频繁"
            detail = "请稍后再试。"
            icon = "clock"
        case .network:
            title = "无法完成搜索"
            detail = "请检查网络连接后重试。"
            icon = "wifi.exclamationmark"
        default:
            title = "无法完成搜索"
            detail = error is URLError ? "请检查网络连接后重试。" : "请稍后再试。"
            icon = error is URLError ? "wifi.exclamationmark" : "exclamationmark.circle"
        }
    }
}
