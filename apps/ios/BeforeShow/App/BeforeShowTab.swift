import Foundation

enum BeforeShowTab: String, CaseIterable, Identifiable {
    case current = "当前"
    case listen = "听"
    case footprints = "足迹"

    var id: String { rawValue }

    var localizedTitle: String {
        BSLocalization.text(key: rawValue)
    }

    var iconName: String {
        switch self {
        case .current: return "sparkles"
        case .footprints: return "flag"
        case .listen: return "opticaldisc"
        }
    }

    /// 埋点用的稳定键。`rawValue` 是界面文案，会随语言变，不能进分析事件名。
    var analyticsKey: String {
        switch self {
        case .current: return "current"
        case .listen: return "listen"
        case .footprints: return "footprints"
        }
    }
}
