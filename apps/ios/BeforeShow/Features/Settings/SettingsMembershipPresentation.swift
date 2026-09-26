struct SettingsMembershipSummary: Equatable {
    let title: String
    let subtitle: String

    init(entitlement: ProEntitlementState) {
        switch entitlement {
        case .free:
            self.init(title: BSLocalization.text("免费版"), subtitle: BSLocalization.text("基础 5 场 · 每月容量 +1"))
        case .active:
            self.init(title: BSLocalization.text("Pro 已启用"), subtitle: BSLocalization.text("可以无限添加现场"))
        case .expired:
            self.init(title: BSLocalization.text("Pro 已过期"), subtitle: BSLocalization.text("已有现场保留 · 每月容量 +1"))
        }
    }

    init(title: String, subtitle: String) {
        self.title = title
        self.subtitle = subtitle
    }
}
