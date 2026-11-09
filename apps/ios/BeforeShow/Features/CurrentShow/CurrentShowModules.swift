import SwiftUI

/// 当前 tab 功能区里的一项：现场工具或一类记录，各占一行。
enum CurrentShowModule: Hashable {
    case action(CurrentShowQuickAction)
    case record(CurrentShowRecordKind)
}

/// 顺序跟着阶段走，不让用户拖。开场前路线放到第二屏；现场进行中时刻表排第一；散场后先看留下的。
/// 哪些模块出现仍由 actions 决定（能否结束、路线是否已在主按钮上等）。
enum CurrentShowModuleOrder {
    private enum Slot {
        case action(CurrentShowQuickAction)
        case dispersal
        case record(CurrentShowRecordKind)
    }

    static func modules(actions: [CurrentShowQuickAction], phase: HomeShowPhase, timetableIsLive: Bool) -> [CurrentShowModule] {
        guard let slots = slots(for: phase) else { return actions.map(CurrentShowModule.action) }
        let records = Set(CurrentShowRecordKit.kinds(for: phase))
        var modules: [CurrentShowModule] = slots.compactMap { slot in
            switch slot {
            case .action(let action):
                return actions.contains(action) ? .action(action) : nil
            case .dispersal:
                return actions.first { if case .dispersal = $0 { true } else { false } }.map(CurrentShowModule.action)
            case .record(let kind):
                return records.contains(kind) ? .record(kind) : nil
            }
        }
        if timetableIsLive, let index = modules.firstIndex(of: .action(.timetable)) {
            modules.insert(modules.remove(at: index), at: 0)
        }
        return modules
    }

    private static func slots(for phase: HomeShowPhase) -> [Slot]? {
        switch phase {
        case .pre:
            [.action(.ticket), .action(.timetable), .action(.companion), .record(.setlist),
             .action(.memoryFragments), .action(.route), .record(.merch), .record(.spending)]
        case .live:
            [.action(.memoryFragments), .record(.setlist), .action(.companion), .record(.merch), .record(.spending),
             .action(.ticket), .action(.timetable), .action(.route), .action(.endShow)]
        case .ended:
            [.action(.memoryFragments), .record(.setlist), .dispersal, .action(.companion), .record(.merch),
             .record(.spending), .action(.ticket), .action(.timetable), .action(.route)]
        case .inactive:
            nil
        }
    }
}
