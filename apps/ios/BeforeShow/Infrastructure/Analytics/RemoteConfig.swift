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
