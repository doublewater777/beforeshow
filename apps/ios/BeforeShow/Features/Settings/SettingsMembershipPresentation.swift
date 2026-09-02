struct SettingsMembershipSummary: Equatable {
    let title: String
    let subtitle: String

    init(entitlement: ProEntitlementState) {
        switch entitlement {
        case .free:
            self.init(title: BSLocalization.text("免费版"), subtitle: BSLocalization.text("每月可添加 1 场现场"))
        case .active:
            self.init(title: BSLocalization.text("Pro 已启用"), subtitle: BSLocalization.text("可以无限添加现场"))
        case .expired:
            self.init(title: BSLocalization.text("Pro 已过期"), subtitle: BSLocalization.text("已有本地内容仍可查看和编辑"))
        }
    }

    init(title: String, subtitle: String) {
        self.title = title
        self.subtitle = subtitle
    }
}
