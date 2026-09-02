import Foundation

enum ProLimitReason: Equatable {
    case saveLimit

    var title: String {
        switch self {
        case .saveLimit:
            return BSLocalization.text("免费版每月可添加 1 场现场")
        }
    }

    var message: String {
        switch self {
        case .saveLimit:
            return BSLocalization.text("开通 Pro 后可以无限保存现场。")
        }
    }
}
