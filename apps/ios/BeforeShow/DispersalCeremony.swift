import Foundation
import SwiftUI

/// 「散场仪式」五档情绪等级。
///
/// 从「拉完了」到「夯爆了」由冷到暖排列，每档绑定一个 emoji、一个中文标签、
/// 一个 tint 色与无障碍朗读文案。`rawValue` 即持久化在 `Show.rating` 的 1...5 整数。
enum DispersalRating: Int, CaseIterable, Identifiable {
    case spoiled = 1
    case meh = 2
    case golden = 3
    case peak = 4
    case fire = 5

    var id: Int { rawValue }

    var emoji: String {
        switch self {
        case .spoiled: "🥀"
        case .meh: "😐"
        case .golden: "😎"
        case .peak: "🤯"
        case .fire: "🔥"
        }
    }

    var label: String {
        switch self {
        case .spoiled: "拉完了"
        case .meh: "NPC"
        case .golden: "人上人"
        case .peak: "顶级"
        case .fire: "夯爆了"
        }
    }

    /// 一句话副标题,让"卡档"有语境。比单独一个 label 更容人接受 —
    /// 拉完了不是"我演砸了",是"今晚有点难评"。
    var sub: String {
        switch self {
        case .spoiled: "今晚有点难评"
        case .meh: "平稳经过这一晚"
        case .golden: "明显高于预期"
        case .peak: "这一晚很值"
        case .fire: "今晚直接封神"
        }
    }

    var accessibilityLabel: String {
        "\(label)，\(sub)，\(rawValue) 星"
    }

    /// 由冷到暖,匹配「场子越热情绪越亮」的视觉直觉。
    var tint: Color {
        switch self {
        case .spoiled: BSColor.Stage.dim
        case .meh: BSColor.Stage.muted
        case .golden: BSColor.Stage.accent
        case .peak: BSColor.Accent.violet
        case .fire: BSColor.Stage.live
        }
    }

    static func from(rawValue value: Int) -> DispersalRating? {
        DispersalRating(rawValue: value)
    }
}

/// 「散场仪式」的纯规则集合:长度上限、动画时长、评分边界与 note 规范化。
/// 供视图层与测试共用,确保规则只有一份真源。
enum DispersalCeremonyPolicy {
    /// 散场文字最大长度。`Show.normalizeClosingNote` 复用同一上限。
    static let maximumNoteLength = 500

    /// 舞台熄灯动画持续时间。3 道光束淡入淡出 + 标题淡入,贴合 V2 原型的"散场"仪式感。
    /// 短到不打断,长到能看见光。reduceMotion 时直接跳到末尾帧。
    static let lightsOutDuration: Double = 2.8

    /// 合法评分范围。
    static let ratingRange: ClosedRange<Int> = 1...5

    /// 把任何 Int 夹到 1...5,出界返回 nil(让上层选择"忽略"或"抛错")。
    static func clampRating(_ raw: Int) -> Int? {
        ratingRange.contains(raw) ? raw : nil
    }

    /// 把任何 Double 四舍五入到最近的合法档位,用于 Slider 拖动后的吸附。
    static func snap(_ raw: Double) -> Int {
        let rounded = Int(raw.rounded())
        return max(ratingRange.lowerBound, min(ratingRange.upperBound, rounded))
    }

    /// 散场文字快捷填充。3 个意图对应"刚好够"的句式,降低散场时敲字的门槛。
    /// 顺序敏感:UI chip 顺序 = 数组顺序,后两个比前一个更短,符合"一句话也行"的设计意图。
    static let quickFillPresets: [(label: String, text: String)] = [
        ("一个瞬间", "最后一首歌结束的时候，灯亮得特别慢。"),
        ("一句话也行", "今晚值了。"),
        ("最喜欢的一首歌", "最喜欢的是最后那首歌。")
    ]
}

/// 散场卡上的可见文案。规则只有一份,视图与测试共用。
enum DispersalCeremonyCardCopy {
    static let brand = "BEFORESHOW · 散场记录"
    static let footerTrailing = "开场前"

    /// 现场名拆成最多两行:有艺人且标题以「艺人 · 」开头时拆开,贴近海报排版。
    static func eventLines(name: String, artistNames: [String]) -> [String] {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        guard let artist = artistNames
            .map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) })
            .first(where: { !$0.isEmpty })
        else {
            return [trimmed]
        }
        if trimmed == artist { return [trimmed] }
        let prefix = artist + " · "
        if trimmed.hasPrefix(prefix) {
            let rest = String(trimmed.dropFirst(prefix.count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return rest.isEmpty ? [artist] : [artist, rest]
        }
        return [artist, trimmed]
    }

    static func ratingTitle(_ rating: DispersalRating) -> String {
        "\(rating.emoji) \(rating.label)"
    }

    static func footerLeading(identity: FootprintDetailIdentity) -> String {
        if let name = identity.companionName, let ordinal = identity.companionOrdinal {
            return "与\(name)第 \(ordinal) 次见面"
        }
        return "我的第 \(identity.showOrdinal) 场现场"
    }
}
