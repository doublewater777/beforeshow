import Foundation

/// Policy and persistence for smart timetable recognition allowance.
/// - Free tier: 2 lifetime free recognitions.
/// - Pro tier: Unlimited recognitions.
/// - Failure does not consume quota.
/// - Self-import, manual edit, and original image saving are always free.
struct TimetableRecognitionQuota: @unchecked Sendable {
    static let lifetimeFreeQuota = 2
    static let usedCountKey = "beforeshow_timetable_recognition_used_count"

    var userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    var usedCount: Int {
        userDefaults.integer(forKey: Self.usedCountKey)
    }

    func remainingFreeCount(isPro: Bool) -> Int {
        if isPro { return .max }
        return max(0, Self.lifetimeFreeQuota - usedCount)
    }

    func canRecognize(isPro: Bool) -> Bool {
        isPro || usedCount < Self.lifetimeFreeQuota
    }

    func consumeQuotaIfFree(isPro: Bool) {
        guard !isPro else { return }
        userDefaults.set(usedCount + 1, forKey: Self.usedCountKey)
    }

    func badgeText(isPro: Bool) -> String {
        if isPro {
            return BSLocalization.text("Pro 不限次")
        }
        let remaining = remainingFreeCount(isPro: false)
        if remaining > 0 {
            return BSLocalization.format("免费剩余 %d 次", remaining)
        } else {
            return BSLocalization.text("免费额度已用完 · 升级 Pro")
        }
    }
}
