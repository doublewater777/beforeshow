import Foundation

struct AppVersionInformation: Equatable {
    let marketingVersion: String
    let buildNumber: String

    init(infoDictionary: [String: Any]) {
        self.init(
            marketingVersion: infoDictionary["CFBundleShortVersionString"] as? String ?? BSLocalization.text("未知版本"),
            buildNumber: infoDictionary["CFBundleVersion"] as? String ?? BSLocalization.text("未知构建")
        )
    }

    init(marketingVersion: String, buildNumber: String) {
        self.marketingVersion = marketingVersion
        self.buildNumber = buildNumber
    }

    static var current: AppVersionInformation {
        AppVersionInformation(infoDictionary: Bundle.main.infoDictionary ?? [:])
    }

    var compactCopy: String { "v\(marketingVersion)" }
    var fullCopy: String { BSLocalization.format("版本 %@（构建 %@）", marketingVersion, buildNumber) }
}
