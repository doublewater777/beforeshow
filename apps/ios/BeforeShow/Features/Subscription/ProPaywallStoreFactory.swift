import Foundation

enum ProPaywallStoreFactory {
    static func makeDefault() -> any ProSubscriptionStore {
        let key = Bundle.main.object(forInfoDictionaryKey: "RevenueCatAPIKey") as? String ?? ""
        if key.isEmpty || key == "appl_REPLACE_ME" {
            #if DEBUG
            print("[Pro] RevenueCatAPIKey missing — falling back to Mock store")
            #endif
            return MockProSubscriptionStore()
        }
        return RevenueCatProSubscriptionStore()
    }
}
