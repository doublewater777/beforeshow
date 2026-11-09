import SwiftUI

/// 当前 tab 功能区里的一项：现场工具或一类记录，各占一行。
enum CurrentShowModule: Hashable {
    case action(CurrentShowQuickAction)
    case record(CurrentShowRecordKind)
}

/// 顺序跟着阶段走，不让用户拖。路线地图不排第一；现场进行中时刻表排第一；散场后先看留下的。
/// 哪些模块出现仍由 actions 决定（能否结束、路线是否已在主按钮上等）。
enum CurrentShowModuleOrder {
    private enum Slot {
        case action(CurrentShowQuickAction)
        /// 散场卡没做时排第一，做完沉到最后。
        case dispersal(completed: Bool)
        case record(CurrentShowRecordKind)
    }

    static func modules(actions: [CurrentShowQuickAction], phase: HomeShowPhase, timetableIsLive: Bool) -> [CurrentShowModule] {
        guard let slots = slots(for: phase) else { return actions.map(CurrentShowModule.action) }
        let records = Set(CurrentShowRecordKit.kinds(for: phase))
        var modules: [CurrentShowModule] = slots.compactMap { slot in
            switch slot {
            case .action(let action):
                return actions.contains(action) ? .action(action) : nil
            case .dispersal(let completed):
                return actions.contains(.dispersal(completed: completed)) ? .action(.dispersal(completed: completed)) : nil
            case .record(let kind):
                return records.contains(kind) ? .record(kind) : nil
            }
        }
        // 没做的散场卡和同行拼成第一行。
        if modules.first == .action(.dispersal(completed: false)), let index = modules.firstIndex(of: .action(.companion)) {
            modules.insert(modules.remove(at: index), at: 1)
        }
        if timetableIsLive, let index = modules.firstIndex(of: .action(.timetable)) {
            modules.insert(modules.remove(at: index), at: 0)
        }
        return modules
    }

    /// 票在入场时用的是票务平台的动态码，这里只是存根，排在后面。
    private static func slots(for phase: HomeShowPhase) -> [Slot]? {
        switch phase {
        case .pre:
            [.action(.companion), .record(.setlist), .action(.timetable), .record(.merch), .record(.spending),
             .action(.route), .action(.memoryFragments), .action(.ticket)]
        case .live:
            [.action(.memoryFragments), .record(.setlist), .action(.companion), .record(.merch), .record(.spending),
             .action(.timetable), .action(.route), .action(.ticket), .action(.endShow)]
        case .ended:
            [.dispersal(completed: false), .action(.memoryFragments), .record(.setlist), .action(.companion),
             .record(.merch), .record(.spending), .action(.ticket), .action(.timetable), .action(.route),
             .dispersal(completed: true)]
        case .inactive:
            nil
        }
    }
}
