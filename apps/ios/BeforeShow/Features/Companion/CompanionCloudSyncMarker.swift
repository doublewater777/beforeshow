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

enum CompanionUserProfile {
    static let userDefaultsKey = "companion.user-nickname.v1"

    static var nickname: String? {
        get {
            let value = UserDefaults.standard.string(forKey: userDefaultsKey)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return (value?.isEmpty == false) ? value : nil
        }
        set {
            if let trimmed = newValue?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty {
                UserDefaults.standard.set(trimmed, forKey: userDefaultsKey)
            } else {
                UserDefaults.standard.removeObject(forKey: userDefaultsKey)
            }
        }
    }
}

extension CompanionSharingCoordinator {
    static let cloudSyncEnabledKey = CompanionCloudSyncMarker.userDefaultsKey

    static func persistAcceptedShare(
        _ metadata: CKShare.Metadata,
        userDefaults: UserDefaults = .standard
    ) {
        CompanionAcceptedShareInbox.append(metadata, to: userDefaults)
        CompanionCloudSyncMarker.enable(in: userDefaults, usesKeychain: true)
    }

}
