import Foundation
import SwiftData

/// 某场现场里某个推荐功能的露出与处理记录，只存本机。
@Model
final class FeatureRecommendationRecord {
    var id: UUID
    var showID: UUID
    var featureRawValue: String
    /// 露出过的自然日（设备时区 yyyy-MM-dd）。主卡首页实际可见、推荐通知送达各计一次。
    var exposureDayKeys: [String]
    /// 用户点过主卡或通知。点过即算处理过，本场不再推荐。
    var handledAt: Date?
    var createdAt: Date

    init(showID: UUID, feature: RecommendedFeature, createdAt: Date = Date()) {
        self.id = UUID()
        self.showID = showID
        self.featureRawValue = feature.rawValue
        self.exposureDayKeys = []
        self.handledAt = nil
        self.createdAt = createdAt
    }

    var feature: RecommendedFeature? {
        RecommendedFeature(rawValue: featureRawValue)
    }

    @discardableResult
    func recordExposure(dayKey: String) -> Bool {
        guard !exposureDayKeys.contains(dayKey) else { return false }
        var keys = exposureDayKeys
        keys.append(dayKey)
        exposureDayKeys = keys
        return true
    }

    @discardableResult
    func markHandled(at date: Date) -> Bool {
        guard handledAt == nil else { return false }
        handledAt = date
        return true
    }
}

enum FeatureRecommendationDay {
    static func key(for date: Date, calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }
}
