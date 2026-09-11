import Foundation

enum BeforeShowTab: String, CaseIterable, Identifiable {
    case current = "当前"
    case listen = "听"
    case footprints = "足迹"

    var id: String { rawValue }

    var localizedTitle: String {
        BSLocalization.text(rawValue)
    }

    var iconName: String {
        switch self {
        case .current: return "sparkles"
        case .footprints: return "flag"
        case .listen: return "opticaldisc"
        }
    }
}
