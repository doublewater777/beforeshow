enum NotificationSettingsAction: Equatable {
    case requestPermission
    case openSystemSettings
}

struct NotificationSettingsPresentation: Equatable {
    /// 设置里这一行的标题：这是整套本地通知的权限入口，不只是开场那一条。
    var title: String { BSLocalization.text("通知") }

    let status: String
    let action: NotificationSettingsAction

    init(authorizationState: NotificationAuthorizationState) {
        switch authorizationState {
        case .notDetermined:
            self.init(
                status: BSLocalization.text("尚未开启"),
                action: .requestPermission
            )
        case .denied:
            self.init(
                status: BSLocalization.text("未开启"),
                action: .openSystemSettings
            )
        case .authorized, .provisional:
            self.init(status: BSLocalization.text("已开启"), action: .openSystemSettings)
        }
    }

    init(status: String, action: NotificationSettingsAction) {
        self.status = status
        self.action = action
    }
}
