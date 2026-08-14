import Foundation

enum BeforeShowTab: String, CaseIterable, Identifiable {
    case current = "当前"
    case warmup = "预热"
    case footprints = "足迹"

    var id: String { rawValue }

    var localizedTitle: String {
        BSLocalization.text(rawValue)
    }

    var iconName: String {
        switch self {
        case .current: return "sparkles"
        case .warmup: return "music.note"
        case .footprints: return "flag"
        }
    }
}
