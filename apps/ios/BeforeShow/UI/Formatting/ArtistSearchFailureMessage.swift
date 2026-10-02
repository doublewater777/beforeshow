import Foundation

struct ArtistSearchFailureMessage {
    enum Recovery {
        case retry, authorize, openSettings
    }

    let title: String
    let detail: String
    let icon: String
    let recovery: Recovery?

    var actionTitle: String? {
        switch recovery {
        case .retry: BSLocalization.text("重试")
        case .authorize: BSLocalization.text("授权 Apple Music")
        case .openSettings: BSLocalization.text("打开设置")
        case nil: nil
        }
    }

    init(error: any Error) {
        if case let .authorizationRequired(status) = error as? ArtistSearchError {
            icon = "music.note"
            switch status {
            case .notDetermined:
                title = "允许访问 Apple Music"
                detail = "授权后可搜索更多艺人。"
                recovery = .authorize
            case .denied:
                title = "未允许访问 Apple Music"
                detail = "请在设置中允许访问，以搜索更多艺人。"
                recovery = .openSettings
            case .restricted:
                title = "Apple Music 访问受限"
                detail = "请检查设备的访问限制。"
                recovery = nil
            case .authorized:
                title = "Apple Music 搜索暂不可用"
                detail = "部分艺人可能无法搜到，请稍后再试。"
                recovery = .retry
            }
            return
        }
        recovery = .retry
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
