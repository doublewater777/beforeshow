import Foundation

/// 推荐判断需要、但只能由系统服务给出的全局事实。
struct FeatureUsageFacts: Equatable, Sendable {
    var hasInstalledWidget: Bool
    var isICloudAvailable: Bool

    static let unknown = FeatureUsageFacts(hasInstalledWidget: false, isICloudAvailable: false)
}

struct FeatureRecommendationRecordSnapshot: Equatable, Sendable {
    var exposureDayKeys: Set<String>
    var isHandled: Bool
}

/// 一场现场里推荐相关的事实；按开场时间排序后用于判断「连续两场被跳过」。
struct FeatureRecommendationShowFacts: Equatable, Sendable {
    let showID: UUID
    let sortDate: Date
    let used: Set<RecommendedFeature>
    let records: [RecommendedFeature: FeatureRecommendationRecordSnapshot]
}

struct FeatureRecommendationContext: Equatable, Sendable {
    var used: Set<RecommendedFeature> = []
    var usedInOtherShows: Set<RecommendedFeature> = []
    var unavailable: Set<RecommendedFeature> = []
    var muted: Set<RecommendedFeature> = []
    var records: [RecommendedFeature: FeatureRecommendationRecordSnapshot] = [:]
}

struct FeatureRecommendationSnapshot: Equatable, Sendable {
    let shows: [FeatureRecommendationShowFacts]
    let facts: FeatureUsageFacts

    func context(for showID: UUID) -> FeatureRecommendationContext {
        let target = shows.first { $0.showID == showID }
        let others = shows.filter { $0.showID != showID }
        return FeatureRecommendationContext(
            used: target?.used ?? [],
            usedInOtherShows: others.reduce(into: Set<RecommendedFeature>()) { $0.formUnion($1.used) },
            unavailable: facts.isICloudAvailable ? [] : [.companion],
            muted: FeatureRecommendationPolicy.mutedFeatures(in: others),
            records: target?.records ?? [:]
        )
    }
}

enum FeatureRecommendationPolicy {
    /// 一个功能在一场现场里最多露出的自然日数，满了没点就本场跳过。
    static let maximumExposureDays = 2

    /// 按候选顺序取第一个可推荐的功能；在其他现场用过的排到最后。
    /// `todayKey` 让今天已经露出的功能在今天内保持；`plannedExposures` 计入同一次排期里
    /// 更早节点已经安排的露出，避免多条通知把同一个功能推满。
    static func candidate(
        from chain: [RecommendedFeature],
        context: FeatureRecommendationContext,
        todayKey: String? = nil,
        plannedExposures: [RecommendedFeature: Int] = [:]
    ) -> RecommendedFeature? {
        let eligible = chain.filter {
            isEligible($0, context: context, todayKey: todayKey, plannedExposures: plannedExposures[$0] ?? 0)
        }
        let fresh = eligible.filter { !context.usedInOtherShows.contains($0) }
        let familiar = eligible.filter { context.usedInOtherShows.contains($0) }
        return (fresh + familiar).first
    }

    static func isEligible(
        _ feature: RecommendedFeature,
        context: FeatureRecommendationContext,
        todayKey: String? = nil,
        plannedExposures: Int = 0
    ) -> Bool {
        guard !context.used.contains(feature),
              !context.unavailable.contains(feature),
              !context.muted.contains(feature) else {
            return false
        }
        guard let record = context.records[feature] else {
            return plannedExposures < maximumExposureDays
        }
        guard !record.isHandled else { return false }
        if let todayKey, record.exposureDayKeys.contains(todayKey) {
            return true
        }
        return record.exposureDayKeys.count + plannedExposures < maximumExposureDays
    }

    /// 同一功能在最近两场有结论的现场里都被跳过，就暂停推荐；任何一场用过或点过即恢复。
    static func mutedFeatures(in shows: [FeatureRecommendationShowFacts]) -> Set<RecommendedFeature> {
        let ordered = shows.sorted { $0.sortDate < $1.sortDate }
        var muted = Set<RecommendedFeature>()
        for feature in RecommendedFeature.allCases {
            let outcomes = ordered.compactMap { show -> Bool? in
                if show.used.contains(feature) || show.records[feature]?.isHandled == true {
                    return false
                }
                guard let record = show.records[feature],
                      record.exposureDayKeys.count >= maximumExposureDays else {
                    return nil
                }
                return true
            }
            if outcomes.count >= 2, outcomes.suffix(2).allSatisfy({ $0 }) {
                muted.insert(feature)
            }
        }
        return muted
    }
}
