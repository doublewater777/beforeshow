import Foundation

// MARK: - Live Activity Opening Coverage
// 实时活动开场段预约成功 → 它到点的 alert 就是「开场前」提醒,本地那条不再排。
// 开场前撤销预约 → 交还本地通知;开场后记录保留,免得本地通知再补发一条。

struct LiveActivityOpeningCoverage {
    static let storageKey = "com.doublewaterapps.beforeshow.liveActivityOpeningCoverage"
    private static let retention: TimeInterval = 2 * 86_400

    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// showID → 接管的那次开场 alert 时间;只对同一次开场的本地提醒生效。
    func coveredOpenings(now: Date) -> [UUID: Date] {
        entries().filter { $0.value > now.addingTimeInterval(-Self.retention) }
    }

    /// 以当前实时活动现场的开场段预约结果更新记录;有变化时返回 true。
    @discardableResult
    func reconcile(liveShowID: UUID?, coveredOpening: Date?, now: Date) -> Bool {
        let before = entries()
        var after = before.filter { $0.value <= now && $0.value > now.addingTimeInterval(-Self.retention) }
        if let liveShowID, let coveredOpening {
            after[liveShowID] = coveredOpening
        }
        guard after != before else { return false }
        defaults.set(
            Dictionary(uniqueKeysWithValues: after.map { ($0.key.uuidString, $0.value.timeIntervalSince1970) }),
            forKey: Self.storageKey
        )
        return true
    }

    private func entries() -> [UUID: Date] {
        let raw = defaults.dictionary(forKey: Self.storageKey) as? [String: Double] ?? [:]
        return Dictionary(uniqueKeysWithValues: raw.compactMap { key, value in
            UUID(uuidString: key).map { ($0, Date(timeIntervalSince1970: value)) }
        })
    }
}
