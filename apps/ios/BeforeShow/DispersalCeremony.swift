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

    /// 舞台熄灯动画持续时间。3 道光束淡入淡出 + 标题淡入。
    /// 4.2s 让「散场」按 25%–80% 包络至少停住 2 秒;2.8s 时只有 1.5s,会像闪一下。
    /// reduceMotion 时直接跳到中段停驻帧(progress 0.5)。
    static let lightsOutDuration: Double = 4.2

    /// 熄灯动画开表前的停顿。等 fullScreenCover 上滑转场落定,
    /// 否则转场会吃掉标题渐入(0–25%)的前三分之一,看起来"突然开始"。
    static let lightsOutTransitionLeadIn: Double = 0.45

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

/// 评级吸附条:轨道两端落在首尾圆点中心,拉到顶时线不会在圆点外多出一截。
enum DispersalSnapSliderLayout {
    static func trackInset(width: CGFloat, nodeCount: Int = DispersalRating.allCases.count) -> CGFloat {
        guard nodeCount > 0, width > 0 else { return 0 }
        return width / CGFloat(nodeCount * 2)
    }
}

/// 熄灯动画时间轴。视图用 `TimelineView` 每帧喂 elapsed,这里只算 0...1 进度与透明度。
enum DispersalLightsOutMotion {
    static func progress(elapsed: TimeInterval, duration: TimeInterval) -> Double {
        guard duration > 0 else { return 1 }
        return min(1, max(0, elapsed / duration))
    }

    /// 标题在 [0, 25%] 渐入, [80%, 100%] 渐出,中段保持。
    static func titleOpacity(progress: Double) -> Double {
        if progress < 0.25 {
            return progress / 0.25
        } else if progress < 0.80 {
            return 1
        } else {
            return max(0, 1 - (progress - 0.80) / 0.20)
        }
    }

    /// 光束:0 起、25% 到峰、85% 收到 35%、结束收光。
    static func beamOpacity(progress: Double, peak: Double) -> Double {
        if progress < 0.25 {
            return peak * (progress / 0.25)
        } else if progress < 0.85 {
            let t = (progress - 0.25) / 0.60
            return peak * (1 - 0.65 * t)
        } else {
            return peak * 0.35 * max(0, 1 - (progress - 0.85) / 0.15)
        }
    }
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
            return BSLocalization.format("与%@第 %lld 次见面", name, ordinal)
        }
        return BSLocalization.format("我的第 %lld 场现场", identity.showOrdinal)
    }
}
