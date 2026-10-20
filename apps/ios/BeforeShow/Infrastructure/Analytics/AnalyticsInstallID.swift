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
    static func current() -> String {
        if let existing = read() { return existing }
        let generated = UUID().uuidString
        write(generated)
        return generated
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

    private static func write(_ value: String) {
        guard let data = value.data(using: .utf8) else { return }
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
        guard status == errSecDuplicateItem else { return }
        SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
    }
}
