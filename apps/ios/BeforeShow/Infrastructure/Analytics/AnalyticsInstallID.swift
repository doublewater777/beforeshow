import Foundation
import Security

/// 匿名的安装级 ID，只用于 PostHog `identify`，让留存和漏斗按「人」而不是按设备聚合。
///
/// 刻意**不**用 iCloud `userRecordID` / CloudKit 用户身份：那会超出「匿名分析」的
/// 口径，把分析身份和用户的 Apple 身份绑定。刻意**不**用 UserDefaults：重装 App
/// 后应视为同一用户，UserDefaults 会在重装时清空。
///
/// Keychain 数据在同一设备的 App 重装后保留；跟随设备备份（`ThisDeviceOnly` 之外的
/// 默认策略会随 iCloud 备份走，这里保持默认，不引入额外的恢复策略）。
enum AnalyticsInstallID {
    private static let keychainAccount = "analytics-install-id"

    /// 读取；不存在时生成并持久化。返回值稳定。
    ///
    /// 写入失败时返回 nil：宁可本次不 identify，也不把无法持久化的随机 UUID
    /// 上报成 Person 身份——那会让同一装在不同启动周期被切成多个 Person，
    /// 污染留存和漏斗。
    static func current() -> String? {
        if let existing = read() { return existing }
        let generated = UUID().uuidString
        let outcome = AnalyticsInstallIDResolution.resolve(
            existing: nil,
            writeStatus: write(generated)
        )
        return outcome.identifiedID
    }

    private static func read() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8),
              !value.isEmpty
        else {
            return nil
        }
        return value
    }

    /// 写入一条新 ID。并发竞争（已有条目）时绝不覆盖已建立身份：
    /// 只重读现有值并抄它作为赢家。否则两个并发调用各自拿到不同 ID，
    /// 其中一个已上报给 PostHog，之后的事件会挂到另一个 Person 上。
    private static func write(_ value: String) -> AnalyticsInstallIDResolution.KeychainWriteStatus {
        guard let data = value.data(using: .utf8) else { return .failed }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: keychainAccount
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        let status = SecItemAdd(
            query.merging(attributes, uniquingKeysWith: { _, new in new }) as CFDictionary,
            nil
        )
        switch status {
        case errSecSuccess:
            return .succeeded(value)
        case errSecDuplicateItem:
            // 竞争：已存在的那条就是赢家，只重读，不覆盖。
            if let existing = read() { return .succeeded(existing) }
            return .failed
        default:
            return .failed
        }
    }
}

/// 匿名安装 ID 的一次性决策：读取 → 写入 → 决定上报身份。
/// 纯函数，便于覆盖「Keychain 写入失败」等分支。
enum AnalyticsInstallIDResolution {
    enum KeychainWriteStatus: Equatable {
        case succeeded(String)
        case failed
    }

    struct Outcome: Equatable {
        /// 最终上报的稳定身份；nil 表示本次没有可信身份，调用方不应 identify。
        let identifiedID: String?
        /// 待持久化的新值（已持久化或失败时为 nil）。
        let valueToPersist: String?
    }

    static func resolve(existing: String?, writeStatus: KeychainWriteStatus) -> Outcome {
        // 已持久化 ID 优先，空串等同缺失。
        if let existing, !existing.isEmpty {
            return Outcome(identifiedID: existing, valueToPersist: nil)
        }
        switch writeStatus {
        case .succeeded(let generated):
            return Outcome(identifiedID: generated, valueToPersist: nil)
        case .failed:
            return Outcome(identifiedID: nil, valueToPersist: nil)
        }
    }
}
