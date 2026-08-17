import Foundation

/// Home overlays that occupy the single sheet slot.
enum CurrentShowPresentedSheet: Identifiable, Equatable, Hashable {
    case endConfirmation
    case companion
    case asset(ShowAssetKind)
    case memory
    case mapChooser

    var id: String {
        switch self {
        case .endConfirmation: return "endConfirmation"
        case .companion: return "companion"
        case .asset(let kind): return "asset-\(kind.rawValue)"
        case .memory: return "memory"
        case .mapChooser: return "mapChooser"
        }
    }
}

enum MemoryCreateSourceOption: String, CaseIterable {
    case camera = "相机"
    case library = "图库"
    case text = "文字"

    var title: String { BSLocalization.text(rawValue) }

    var iconName: String {
        switch self {
        case .camera: return "camera"
        case .library: return "photo.on.rectangle"
        case .text: return "text.alignleft"
        }
    }

}

enum MemoryCreateSourcePresentation {
    static let title = BSLocalization.text("新增记忆")
    static let message = BSLocalization.text("拍一张、选一段、写一句。")
}

enum ShowAssetPresentationStyle: Equatable {
    case sheet
    case push

    static func style(hasSavedAsset _: Bool) -> Self {
        .sheet
    }
}

/// Show-detail overlays that occupy the single sheet slot.
enum ShowDetailPresentedSheet: Identifiable, Equatable, Hashable {
    case editor
    case confirmedEnd
    case companion
    case asset(ShowAssetKind)
    case postpone
    case memory

    var id: String {
        switch self {
        case .editor: return "editor"
        case .confirmedEnd: return "confirmedEnd"
        case .companion: return "companion"
        case .asset(let kind): return "asset-\(kind.rawValue)"
        case .postpone: return "postpone"
        case .memory: return "memory"
        }
    }
}

/// Add-show paywall occupies one sheet; limit replaces into membership.
enum AddShowPaywallSheet: String, Identifiable, Equatable {
    case limit
    case membership

    var id: String { rawValue }
}

enum MapChooserPresentation {
    enum Resolution: Equatable {
        case pick([ExternalMapApp])
        case missingDestination
        case noneInstalled
    }

    static func resolution(
        hasDestination: Bool,
        installed: [ExternalMapApp]
    ) -> Resolution {
        guard hasDestination else { return .missingDestination }
        if installed.isEmpty { return .noneInstalled }
        return .pick(installed)
    }

    static func visibleApps(
        hasDestination: Bool,
        installed: [ExternalMapApp]
    ) -> [ExternalMapApp] {
        hasDestination ? installed : []
    }

    static func message(
        hasDestination: Bool,
        destinationLabel: String,
        installed: [ExternalMapApp]
    ) -> String {
        if !hasDestination {
            return BSLocalization.text("补充场馆或地址后，就能跳到地图 App。")
        }
        if installed.isEmpty {
            return BSLocalization.text("没有检测到可用的地图 App。")
        }
        return destinationLabel
    }

    static func title(hasDestination: Bool) -> String {
        hasDestination ? BSLocalization.text("在地图中打开") : BSLocalization.text("还没有目的地")
    }
}

enum DangerConfirmation: Equatable {
    case deleteShow
    case cancelShow
    case deleteShowFromEditor
    case cancelShowFromEditor
    case clearLocalData
    case deleteAsset(ShowAssetKind)
    case deleteMemory

    var title: String {
        switch self {
        case .deleteShow:
            return BSLocalization.text("删除这条现场记录？")
        case .cancelShow:
            return BSLocalization.text("取消这场演出？")
        case .deleteShowFromEditor:
            return BSLocalization.text("删除现场")
        case .cancelShowFromEditor:
            return BSLocalization.text("记录取消")
        case .clearLocalData:
            return BSLocalization.text("清除本地数据")
        case .deleteAsset(let kind):
            return BSLocalization.format("删除%@？", kind.title)
        case .deleteMemory:
            return BSLocalization.text("删除这条记忆？")
        }
    }

    var message: String {
        switch self {
        case .deleteShow:
            return BSLocalization.text("删除后不会出现在“我的现场”和足迹中，此操作无法恢复。")
        case .cancelShow:
            return BSLocalization.text("取消后会停止倒计时和提醒，这场仍会保留在“我的现场”。")
        case .deleteShowFromEditor:
            return BSLocalization.text("删除后，这场现场将无法恢复，也会从足迹统计中移除。")
        case .cancelShowFromEditor:
            return BSLocalization.text("记录为取消后，这场现场仍会保留在“我的现场”中，但不会出现在当前现场。")
        case .clearLocalData:
            return BSLocalization.text("这会删除 BeforeShow 管理的本地记录和副本，且无法恢复；系统相册原图不会删除。")
        case .deleteAsset:
            return BSLocalization.text("删除后可以重新添加。App 内保存的图片会一起移除。")
        case .deleteMemory:
            return BSLocalization.text("照片、视频和文字都会从本地时间流中移除。")
        }
    }

    var confirmTitle: String {
        switch self {
        case .deleteShow:
            return BSLocalization.text("确认删除")
        case .cancelShow:
            return BSLocalization.text("确认取消演出")
        case .deleteShowFromEditor:
            return BSLocalization.text("删除")
        case .cancelShowFromEditor:
            return BSLocalization.text("确认取消")
        case .clearLocalData:
            return BSLocalization.text("清除")
        case .deleteAsset(let kind):
            return BSLocalization.format("删除%@", kind.title)
        case .deleteMemory:
            return BSLocalization.text("删除")
        }
    }
}
