import Foundation
import Security

enum CompanionCloudSyncMarker {
    static let userDefaultsKey = "companion.cloud-sync-enabled.v1"

    private static let keychainService = "com.doublewaterapps.beforeshow.companion"
    private static let keychainAccount = "cloud-sync-enabled"

    static func isEnabled(in userDefaults: UserDefaults, usesKeychain: Bool) -> Bool {
        userDefaults.bool(forKey: userDefaultsKey)
            || (usesKeychain && hasKeychainMarker())
    }

    static func enable(in userDefaults: UserDefaults, usesKeychain: Bool) {
        userDefaults.set(true, forKey: userDefaultsKey)
        if usesKeychain {
            persistKeychainMarker()
        }
    }

    private static func hasKeychainMarker() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: false,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        return SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
    }

    private static func persistKeychainMarker() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: Data([1]),
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
