import Foundation

enum ProLimitReason: Equatable {
    case saveLimit
    case hardCapLimit
    case recognitionLimit

    var title: String {
        switch self {
        case .saveLimit, .hardCapLimit:
            return BSLocalization.text("已达到免费 20 场上限")
        case .recognitionLimit:
            return BSLocalization.text("免费智能识别次数已用完")
        }
    }

    var message: String {
        switch self {
        case .saveLimit, .hardCapLimit:
            return BSLocalization.text("免费版最多可添加 20 场现场；删除现场可释放容量。开通 Pro 后不限制新增场次。")
        case .recognitionLimit:
            return BSLocalization.text("普通用户赠送 2 次时刻表智能识别；开通 Pro 后不限使用次数。自行导入排期与原图保存始终免费。")
        }
    }
}
