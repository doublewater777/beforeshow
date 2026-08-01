import Foundation

enum BeforeShowTab: String, CaseIterable, Identifiable {
    case current = "当前"
    case footprints = "足迹"

    var id: String { rawValue }

    var iconName: String {
        switch self {
        case .current: return "clock"
        case .footprints: return "flag"
        }
    }
}
