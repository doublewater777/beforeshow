import Foundation

/// 现场听到了 / 周边 / 花销：当前 tab 与足迹详情共用的三项记录行。
enum CurrentShowRecordKind: Hashable {
    case setlist
    case merch
    case spending
}

struct CurrentShowRecordFacts: Equatable {
    var setlistCount = 0
    var playedSetlistCount = 0
    var merchCount = 0
    var ticketPriceText: String?
    var travelCostText: String?
}

struct CurrentShowRecordRow: Identifiable, Equatable {
    let kind: CurrentShowRecordKind
    let title: String
    let subtitle: String?
    let action: String
    /// 有记录时图标与副标题提亮；缺的给强调色动作词。
    let isFilled: Bool
    let emphasizesAction: Bool

    var id: CurrentShowRecordKind { kind }

    var iconName: String {
        switch kind {
        case .setlist: return "music.note"
        case .merch: return "tshirt"
        case .spending: return "creditcard"
        }
    }
}

enum CurrentShowRecordKit {
    static func title(for phase: HomeShowPhase) -> String? {
        switch phase {
        case .inactive: return nil
        case .pre: return BSLocalization.text("歌单")
        case .live: return BSLocalization.text("此刻")
        case .ended: return BSLocalization.text("留下的")
        }
    }

    static func kinds(for phase: HomeShowPhase) -> [CurrentShowRecordKind] {
        switch phase {
        case .inactive: return []
        case .pre: return [.setlist]
        case .live: return [.setlist]
        case .ended: return [.setlist, .merch, .spending]
        }
    }

    static func rows(phase: HomeShowPhase, facts: CurrentShowRecordFacts) -> [CurrentShowRecordRow] {
        kinds(for: phase).map { row($0, phase: phase, facts: facts) }
    }

    static func row(_ kind: CurrentShowRecordKind, phase: HomeShowPhase, facts: CurrentShowRecordFacts) -> CurrentShowRecordRow {
        let open = "›"
        let none = BSLocalization.text("还没有")
        switch kind {
        case .setlist:
            switch phase {
            case .pre:
                let has = facts.setlistCount > 0
                let action = has ? open : BSLocalization.text("加一首")
                return .init(
                    kind: kind,
                    title: BSLocalization.text("歌单"),
                    subtitle: has ? BSLocalization.format("%lld 首", facts.setlistCount) : none,
                    action: action,
                    isFilled: has,
                    emphasizesAction: !has
                )
            case .live:
                let played = facts.playedSetlistCount
                let total = facts.setlistCount
                let action = BSLocalization.text("打勾")
                let sub = total > 0 ? BSLocalization.format("已唱 %lld / %lld", played, total) : none
                return .init(
                    kind: kind,
                    title: BSLocalization.text("歌单"),
                    subtitle: sub,
                    action: action,
                    isFilled: total > 0,
                    emphasizesAction: total == 0 || played < total
                )
            case .ended, .inactive:
                let count = facts.playedSetlistCount > 0 ? facts.playedSetlistCount : facts.setlistCount
                let hasPlayed = count > 0
                let action = hasPlayed ? open : BSLocalization.text("补一首")
                return .init(
                    kind: kind,
                    title: BSLocalization.text("现场听到了"),
                    subtitle: hasPlayed ? BSLocalization.format("%lld 首", count) : none,
                    action: action,
                    isFilled: hasPlayed,
                    emphasizesAction: !hasPlayed
                )
            }
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
        }
    }
}
