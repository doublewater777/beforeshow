import Foundation

/// Entry title for a show's companions: 「和谁去」 when empty, otherwise who.
struct CompanionQuickActionPresentation: Equatable {
    let displayTitle: String
    let accessibilityLabel: String
    let companionName: String?
    let companionNames: [String]

    var showsAvatars: Bool { !companionNames.isEmpty }

    init(companionNames: [String]) {
        let names = CompanionNameList.normalized(companionNames)
        self.companionNames = names
        self.companionName = CompanionNameList.joined(names)
        if names.count == 1, let name = names.first {
            displayTitle = BSLocalization.format("与%@同行", name)
        } else if names.count > 1 {
            displayTitle = BSLocalization.format("%lld 人同行", Int64(names.count + 1))
        } else {
            displayTitle = BSLocalization.text("和谁去")
        }
        accessibilityLabel = companionName.map { BSLocalization.format("同行，%@", $0) }
            ?? BSLocalization.text("同行，和谁去")
    }
}
