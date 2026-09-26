import Foundation

enum ProLimitReason: Equatable {
    case saveLimit

    var title: String {
        switch self {
        case .saveLimit:
            return BSLocalization.text("本月免费容量已用完")
        }
    }

    var message: String {
        switch self {
        case .saveLimit:
            return BSLocalization.text("免费版基础 5 场，之后每个自然月容量增加 1 场；删除现场会释放容量。开通 Pro 后不限制新增场次。")
        }
    }
}
