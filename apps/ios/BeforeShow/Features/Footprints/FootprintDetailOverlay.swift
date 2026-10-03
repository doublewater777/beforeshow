import Foundation

enum FootprintDetailOverlay: Identifiable {
    case textMemory(MemoryFragment, initialIndex: Int)
    case mediaMemory(MemoryFragment, initialIndex: Int)
    case asset(ShowAssetKind)
    case memoryPage
    case editor
    case shareComposer
    case dispersalShare
    case ceremonyEditor
    case deleteConfirmation

    enum Surface {
        case sheet
        case fullScreenCover
        case alert
    }

    var id: String {
        switch self {
        case .textMemory(let fragment, let index): return "text-\(fragment.id)-\(index)"
        case .mediaMemory(let fragment, let index): return "media-\(fragment.id)-\(index)"
        case .asset(let kind): return "asset-\(kind.rawValue)"
        case .memoryPage: return "memoryPage"
        case .editor: return "editor"
        case .shareComposer: return "shareComposer"
        case .dispersalShare: return "dispersalShare"
        case .ceremonyEditor: return "ceremonyEditor"
        case .deleteConfirmation: return "deleteConfirmation"
        }
    }

    var surface: Surface {
        switch self {
        case .mediaMemory, .shareComposer: return .fullScreenCover
        case .deleteConfirmation: return .alert
        default: return .sheet
        }
    }
}
