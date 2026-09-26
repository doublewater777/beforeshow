import Foundation

struct FreeShowCapacityStateStore {
    private static let storageKey = "freeShowCapacityState.v1"

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func load() -> FreeShowCapacityState? {
        guard let data = userDefaults.data(forKey: Self.storageKey) else { return nil }
        return try? JSONDecoder().decode(FreeShowCapacityState.self, from: data)
    }

    func save(_ state: FreeShowCapacityState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        userDefaults.set(data, forKey: Self.storageKey)
    }

    func reset() {
        userDefaults.removeObject(forKey: Self.storageKey)
    }
}
