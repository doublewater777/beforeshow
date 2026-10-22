import Foundation
import Security

/// 设备端持有的随机管理凭据，用于验证该安装对云端实时活动计划的所有权（ADR 0044）。
enum LiveActivityPlanSecretStore {
    private static let keychainAccount = "live-activity-plan-secret"
    private static let userDefaultsFallbackKey = "com.doublewaterapps.beforeshow.liveActivityPlanSecret"

    static func current(userDefaults: UserDefaults = .standard) -> String {
        if let existing = readKeychain() {
            return existing
        }
        if let fallback = userDefaults.string(forKey: userDefaultsFallbackKey), !fallback.isEmpty {
            return fallback
        }

        let fresh = UUID().uuidString.replacingOccurrences(of: "-", with: "") + UUID().uuidString.replacingOccurrences(of: "-", with: "")
        if writeKeychain(fresh) {
            return fresh
        }
        userDefaults.set(fresh, forKey: userDefaultsFallbackKey)
        return fresh
    }

    private static func readKeychain() -> String? {
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

    private static func writeKeychain(_ value: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }
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
        return status == errSecSuccess || status == errSecDuplicateItem
    }
}
