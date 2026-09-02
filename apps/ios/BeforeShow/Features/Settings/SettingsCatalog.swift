import Foundation

enum SettingsEntry: String, CaseIterable, Equatable {
    case proMembership = "Pro会员"
    case privacyAndLocalData = "隐私与本地数据"
    case feedback = "意见反馈"
    case rateApp = "评价此应用"
    case about = "关于开场前"

    var displayTitle: String { BSLocalization.text(rawValue) }
}

enum SettingsInformation {
    static let orderedEntries: [SettingsEntry] = [
        .proMembership,
        .privacyAndLocalData,
        .feedback,
        .rateApp,
        .about
    ]
}
