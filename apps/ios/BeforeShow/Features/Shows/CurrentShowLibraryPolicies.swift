import SwiftUI

/// 「我的现场」分区：即将开始（含延期）在前，往期（已结束 + 已取消）按年份倒序成组。
enum CurrentShowLibrarySectionPolicy {
    struct YearGroup<Item>: Identifiable {
        let year: Int
        let items: [Item]
        var id: Int { year }
    }

    /// 有日期的按开场时间升序；延期且日期待定的排在最后。
    static func upcomingPrecedes(_ lhs: (date: Date, isUndated: Bool), _ rhs: (date: Date, isUndated: Bool)) -> Bool {
        if lhs.isUndated != rhs.isUndated { return rhs.isUndated }
        return lhs.date < rhs.date
    }

    /// 按年份倒序分组；组内按日期倒序。
    static func archiveYearGroups<Item>(_ items: [Item], date: (Item) -> Date, year: (Item) -> Int) -> [YearGroup<Item>] {
        let sorted = items.sorted { date($0) > date($1) }
        var groups: [YearGroup<Item>] = []
        for item in sorted {
            let itemYear = year(item)
            if let last = groups.last, last.year == itemYear {
                groups[groups.count - 1] = YearGroup(year: itemYear, items: last.items + [item])
            } else {
                groups.append(YearGroup(year: itemYear, items: [item]))
            }
        }
        return groups
    }
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
