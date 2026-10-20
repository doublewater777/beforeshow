import Foundation
import PostHog

/// Remote 配置的唯一出口。
///
/// 只在这里读 PostHog feature flags；业务代码通过 `isEnabled(_:)` / `variantKey(_:)`
/// 取值，不接触 SDK。flag key 固定为常量，避免散落魔法字符串。
///
/// 注意 PostHog flag 在首次请求返回前 `isFeatureEnabled` 为 false，所以每个 flag
/// 的默认值都必须是「关闭」也安全的那一侧。
enum RemoteConfig {
    /// 挽留弹窗文案实验：开启后把「省 40%」换成更高价值的表述。
    /// flag 关闭时沿用现有文案，App Store 已审文案不变。
    enum FlagKey {
        static let winbackSaveCopyVariant = "winback-save-copy-variant"
    }

    enum WinbackSaveCopyVariant: String {
        /// 现有文案（默认）。
        case control = "control"
        /// 强调「Pro 内容不丢」而不是折扣百分比。
        case access = "access"
    }

    static func isEnabled(_ key: String) -> Bool {
        PostHogSDK.shared.isFeatureEnabled(key)
    }

    /// 取 multivariant flag 的 variant key。未命中或 flag 关闭时返回 nil。
    static func variantKey(_ key: String) -> String? {
        guard let result = PostHogSDK.shared.getFeatureFlagResult(key) else { return nil }
        return result.enabled ? result.variant : nil
    }
}

/// 一次展示的实验分组快照（PR #357 review P2）。
///
/// 付费墙的文案与曝光事件必须来自同一次取值：flag 在首次请求返回前读不到，
/// 若两处各自读取，界面可能在 flag 加载完成后重绘出新文案，而事件里记的仍是
/// 旧的（或没有的）分组，导致实验数据与实际展示不一致。
struct WinbackCopyExperiment: Equatable {
    /// 本次展示采用的文案分支；读不到 flag 时按 control（线上已审文案）。
    let variant: RemoteConfig.WinbackSaveCopyVariant
    /// flag 是否真正命中。false 表示走的是默认回退，不是真实分组。
    let isFlagResolved: Bool

    init(variant: RemoteConfig.WinbackSaveCopyVariant, isFlagResolved: Bool) {
        self.variant = variant
        self.isFlagResolved = isFlagResolved
    }

    /// - Parameter variantKey: `RemoteConfig.variantKey(_:)` 的返回值。
    static func resolve(variantKey: String?) -> WinbackCopyExperiment {
        guard let variantKey,
              let variant = RemoteConfig.WinbackSaveCopyVariant(rawValue: variantKey) else {
            // 未命中 / flag 关闭 / 值非法：退回 control 并标记「未解析」，
            // 避免把默认回退当成真实实验分组写进 super properties。
            return WinbackCopyExperiment(variant: .control, isFlagResolved: false)
        }
        return WinbackCopyExperiment(variant: variant, isFlagResolved: true)
    }

    /// 写进 super properties 的值；未解析时写 control 并带一个未解析标记，
    /// 分析时可区分「真实 control 分组」与「flag 没加载」。
    var superPropertyKey: String {
        RemoteConfig.FlagKey.winbackSaveCopyVariant
    }

    var superPropertyValue: String {
        variant.rawValue
    }
}
