import Foundation

enum BeforeShowTab: String, CaseIterable, Identifiable {
    case current = "当前"
    case myShows = "我的现场"

    var id: String { rawValue }

    var iconName: String {
        switch self {
        case .current: return "music.note.house.fill"
        case .myShows: return "music.note.list"
        }
    }
}
