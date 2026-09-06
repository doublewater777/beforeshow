import Foundation

enum BeforeShowTab: String, CaseIterable, Identifiable {
    case current = "当前"
    case footprints = "足迹"
    case listening = "听"

    var id: String { rawValue }

    var localizedTitle: String {
        BSLocalization.text(rawValue)
    }

    var iconName: String {
        switch self {
        case .current: return "sparkles"
        case .footprints: return "flag"
        case .listening: return "opticaldisc"
        }
    }
}
