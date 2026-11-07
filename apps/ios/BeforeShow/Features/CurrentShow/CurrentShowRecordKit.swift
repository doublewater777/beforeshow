import Foundation

/// 当前 tab 下半部分的记录清单：分段标题和行随阶段变化，每行给出真实状态和下一步动作。
enum CurrentShowRecordKind: Hashable {
    case endShow
    case dispersal(completed: Bool)
    case memory
    case setlist
    case merch
    case spending
    case companion
    case timetable
    case ticket
}

struct CurrentShowRecordFacts: Equatable {
    var hasTicket = false
    var hasTimetable = false
    var companionStatus: ShowCompanionStatus = .none
    var companionNames: [String] = []
    var memoryCount = 0
    var setlistCount = 0
    var merchCount = 0
    var ticketPriceText: String?
    var travelCostText: String?
}

struct CurrentShowRecordRow: Identifiable, Equatable {
    let kind: CurrentShowRecordKind
    let title: String
    let subtitle: String?
    let action: String
    /// 有记录时图标与副标题提亮；缺的给暖金色动作词。
    let isFilled: Bool
    let emphasizesAction: Bool

    var id: CurrentShowRecordKind { kind }

    var iconName: String {
        switch kind {
        case .endShow: return "flag.checkered"
        case .dispersal: return "rectangle.portrait.on.rectangle.portrait"
        case .memory: return "camera"
        case .setlist: return "music.note"
        case .merch: return "tshirt"
        case .spending: return "creditcard"
        case .companion: return "person.2"
        case .timetable: return "list.bullet.rectangle"
        case .ticket: return "ticket"
        }
    }
}

enum CurrentShowRecordKit {
    static func title(for phase: HomeShowPhase) -> String {
        switch phase {
        case .pre, .inactive: return BSLocalization.text("随身带")
        case .live: return BSLocalization.text("此刻")
        case .ended: return BSLocalization.text("留下的")
        }
    }

    static func kinds(for phase: HomeShowPhase) -> [CurrentShowRecordKind] {
        switch phase {
        case .pre, .inactive: return [.ticket, .timetable, .companion]
        case .live: return [.memory, .setlist, .companion, .ticket]
        case .ended: return [.memory, .setlist, .merch, .spending, .companion, .timetable, .ticket]
        }
    }

    /// `leading` 是主按钮没有承载、仍需留在清单最前的动作（结束现场 / 散场记录）。
    static func rows(
        phase: HomeShowPhase,
        facts: CurrentShowRecordFacts,
        leading: [CurrentShowRecordKind] = []
    ) -> [CurrentShowRecordRow] {
        (leading + kinds(for: phase)).map { row($0, phase: phase, facts: facts) }
    }

    static func row(_ kind: CurrentShowRecordKind, phase: HomeShowPhase, facts: CurrentShowRecordFacts) -> CurrentShowRecordRow {
        let open = "›"
        let none = BSLocalization.text("还没有")
        switch kind {
        case .endShow:
            return .init(kind: kind, title: BSLocalization.text("结束现场"), subtitle: nil, action: open, isFilled: true, emphasizesAction: false)
        case .dispersal(let completed):
            return .init(kind: kind, title: BSLocalization.text(completed ? "散场记录" : "记下感受"), subtitle: nil, action: open, isFilled: completed, emphasizesAction: !completed)
        case .memory:
            let has = facts.memoryCount > 0
            let action = phase == .live || !has ? BSLocalization.text("记一笔") : open
            return .init(kind: kind, title: BSLocalization.text("记忆碎片"),
                         subtitle: has ? BSLocalization.format("%lld 条", facts.memoryCount) : none,
                         action: action, isFilled: has, emphasizesAction: action != open)
        case .setlist:
            let has = facts.setlistCount > 0
            let action = phase == .live || !has ? BSLocalization.text("记一首") : open
            return .init(kind: kind, title: BSLocalization.text("现场听到了"),
                         subtitle: has ? BSLocalization.format("已记 %lld 首", facts.setlistCount) : none,
                         action: action, isFilled: has, emphasizesAction: action != open)
        case .merch:
            let has = facts.merchCount > 0
            return .init(kind: kind, title: BSLocalization.text("周边"),
                         subtitle: has ? BSLocalization.format("%lld 件", facts.merchCount) : none,
                         action: BSLocalization.text("拍一张"), isFilled: has, emphasizesAction: !has)
        case .spending:
            let has = facts.ticketPriceText != nil || facts.travelCostText != nil
            let complete = facts.ticketPriceText != nil && facts.travelCostText != nil
            let subtitle = has ? [
                facts.ticketPriceText.map { BSLocalization.format("票价 %@", $0) } ?? BSLocalization.text("票价还没填"),
                facts.travelCostText.map { BSLocalization.format("路费 %@", $0) } ?? BSLocalization.text("路费还没填")
            ].joined(separator: " · ") : none
            return .init(kind: kind, title: BSLocalization.text("花销"), subtitle: subtitle,
                         action: complete ? open : BSLocalization.text("补上"), isFilled: has, emphasizesAction: !complete)
        case .companion:
            let names = CompanionNameList.normalized(facts.companionNames)
            switch facts.companionStatus {
            case .confirmed where !names.isEmpty:
                return .init(kind: kind, title: BSLocalization.text("同行"),
                             subtitle: BSLocalization.format("和 %@", CompanionNameList.joined(names) ?? ""),
                             action: open, isFilled: true, emphasizesAction: false)
            case .pending:
                return .init(kind: kind, title: BSLocalization.text("同行"), subtitle: BSLocalization.text("等待同行"),
                             action: open, isFilled: true, emphasizesAction: false)
            default:
                return .init(kind: kind, title: BSLocalization.text("同行"), subtitle: none,
                             action: BSLocalization.text("邀请"), isFilled: false, emphasizesAction: true)
            }
        case .timetable:
            return .init(kind: kind, title: BSLocalization.text("时刻表"),
                         subtitle: facts.hasTimetable ? BSLocalization.text("已保存") : none,
                         action: facts.hasTimetable ? open : BSLocalization.text("添加"),
                         isFilled: facts.hasTimetable, emphasizesAction: !facts.hasTimetable)
        case .ticket:
            let subtitle: String = {
                guard facts.hasTicket else { return none }
                guard let price = facts.ticketPriceText else { return BSLocalization.text("已保存 1 张") }
                return BSLocalization.format("已保存 1 张 · %@", price)
            }()
            return .init(kind: kind, title: BSLocalization.text("票根"), subtitle: subtitle,
                         action: facts.hasTicket ? open : BSLocalization.text("添加"),
                         isFilled: facts.hasTicket, emphasizesAction: !facts.hasTicket)
        }
    }
}
