import SwiftUI

enum CurrentShowLibraryFilter: String, CaseIterable, Identifiable {
    case upcoming = "即将开始"
    case ended = "已结束"
    case all = "全部"

    var id: Self { self }
}

enum CurrentShowLibraryLayout: String {
    case list
    case covers

    static let storageKey = "currentShowLibraryLayout"
}

enum CurrentShowLibraryMenuAction: String, Hashable {
    case setCurrent = "设为当前"
    case edit = "编辑"
    case postpone = "延期"
    case editPostponedDate = "编辑新日期"
    case restoreScheduled = "恢复正常"
    case restoreCanceled = "恢复演出"
    case cancel = "取消演出"
    case delete = "删除"

    var isDestructive: Bool {
        self == .cancel || self == .delete
    }

    var isStatusAction: Bool {
        switch self {
        case .postpone, .editPostponedDate, .restoreScheduled, .restoreCanceled, .cancel:
            return true
        case .setCurrent, .edit, .delete:
            return false
        }
    }

    var title: String {
        switch self {
        case .setCurrent: return BSLocalization.text("设为当前现场")
        case .edit: return BSLocalization.text("编辑现场")
        case .postpone: return BSLocalization.text("延期")
        case .editPostponedDate: return BSLocalization.text("修改延期")
        case .restoreScheduled, .restoreCanceled: return BSLocalization.text("恢复正常状态")
        case .cancel: return BSLocalization.text("记录取消")
        case .delete: return BSLocalization.text("删除记录")
        }
    }
}

enum CurrentShowLibraryMenuPolicy {
    static func actions(
        for changeStatus: ShowChangeStatus,
        timeKind: CurrentShowTimeKind,
        canSetCurrent: Bool
    ) -> [CurrentShowLibraryMenuAction] {
        switch changeStatus {
        case .postponed:
            return [.edit, .editPostponedDate, .restoreScheduled, .cancel, .delete]
        case .canceled:
            return [.edit, .restoreCanceled, .delete]
        case .scheduled:
            if timeKind == .ended {
                return [.edit, .delete]
            }
            if timeKind == .postShow {
                return (canSetCurrent ? [.setCurrent] : []) + [.edit, .delete]
            }
            return (canSetCurrent ? [.setCurrent] : []) + [.edit, .postpone, .cancel, .delete]
        }
    }
}

extension CurrentShowLibraryMenuAction {
    var icon: String {
        switch self {
        case .setCurrent: return "music.note.house"
        case .edit: return "pencil"
        case .postpone, .editPostponedDate: return "calendar.badge.clock"
        case .restoreScheduled, .restoreCanceled: return "arrow.uturn.backward"
        case .cancel: return "xmark.circle"
        case .delete: return "trash"
        }
    }
}


/// 列表 / 封面网格的逐行入场:每行按索引延后 40ms 淡入并上移,
/// 上限 8 行(第 9 行起与第 8 行同时出现),避免长列表尾部等太久。
