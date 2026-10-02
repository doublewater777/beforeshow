import Foundation
import SwiftData

/// 从现场与本机记录得出推荐事实，并写入露出 / 处理记录。
@MainActor
enum FeatureRecommendationLedger {
    static func snapshot(
        shows: [Show],
        records: [FeatureRecommendationRecord],
        facts: FeatureUsageFacts,
        now: Date
    ) -> FeatureRecommendationSnapshot {
        let hasFuture = nextFutureShow(excluding: nil, in: shows, now: now) != nil
        let recordsByShow = Dictionary(grouping: records, by: \.showID)
        let showFacts = shows.map { show in
            var snapshots: [RecommendedFeature: FeatureRecommendationRecordSnapshot] = [:]
            for record in recordsByShow[show.id] ?? [] {
                guard let feature = record.feature else { continue }
                snapshots[feature] = FeatureRecommendationRecordSnapshot(
                    exposureDayKeys: Set(record.exposureDayKeys),
                    isHandled: record.handledAt != nil
                )
            }
            return FeatureRecommendationShowFacts(
                showID: show.id,
                sortDate: CurrentShowTimeState.effectiveStartTime(for: show, calendar: show.timingCalendar()),
                used: usedFeatures(in: show, facts: facts, hasFutureShow: hasFuture),
                records: snapshots
            )
        }
        return FeatureRecommendationSnapshot(
            shows: showFacts.sorted { $0.sortDate < $1.sortDate },
            facts: facts
        )
    }

    /// 「用过」只看用户自己留下的结果；听、足迹、下一场没有用过状态，只按点过与露出天数轮换。
    static func usedFeatures(
        in show: Show,
        facts: FeatureUsageFacts,
        hasFutureShow: Bool
    ) -> Set<RecommendedFeature> {
        var used = Set<RecommendedFeature>()
        if facts.hasInstalledWidget { used.insert(.widget) }
        if !show.companionMembers.isEmpty || show.companionInvitationShared { used.insert(.companion) }
        if show.assets.contains(where: { $0.kind == .timetable }) { used.insert(.timetable) }
        if show.hasCompletedDispersalCeremony { used.insert(.dispersal) }
        if !show.memoryFragments.isEmpty { used.insert(.memoryFragments) }
        if hasFutureShow { used.insert(.addShow) }
        return used
    }

    /// 开场时间最近的未来现场；不含已取消、补录和没有新日期的延期现场。
    nonisolated static func nextFutureShow(excluding showID: UUID?, in shows: [Show], now: Date) -> Show? {
        shows
            .filter { show in
                guard show.id != showID,
                      show.wasAddedAsHistorical != true,
                      show.changeStatus != .canceled else {
                    return false
                }
                return !(show.changeStatus == .postponed && show.postponedDate == nil)
            }
            .compactMap { show -> (Show, Date)? in
                let start = CurrentShowTimeState.effectiveStartTime(for: show, calendar: show.timingCalendar())
                return start > now ? (show, start) : nil
            }
            .min { lhs, rhs in
                lhs.1 != rhs.1 ? lhs.1 < rhs.1 : lhs.0.id.uuidString < rhs.0.id.uuidString
            }?
            .0
    }

    @discardableResult
    static func recordExposure(
        showID: UUID,
        feature: RecommendedFeature,
        dayKey: String,
        in context: ModelContext
    ) throws -> Bool {
        try record(showID: showID, feature: feature, in: context).recordExposure(dayKey: dayKey)
    }

    @discardableResult
    static func markHandled(
        showID: UUID,
        feature: RecommendedFeature,
        at date: Date = Date(),
        in context: ModelContext
    ) throws -> Bool {
        try record(showID: showID, feature: feature, in: context).markHandled(at: date)
    }

    static func deleteOrphans(validShowIDs: Set<UUID>, in context: ModelContext) throws {
        for record in try context.fetch(FetchDescriptor<FeatureRecommendationRecord>())
        where !validShowIDs.contains(record.showID) {
            context.delete(record)
        }
    }

    private static func record(
        showID: UUID,
        feature: RecommendedFeature,
        in context: ModelContext
    ) throws -> FeatureRecommendationRecord {
        let rawValue = feature.rawValue
        let descriptor = FetchDescriptor<FeatureRecommendationRecord>(
            predicate: #Predicate { $0.showID == showID && $0.featureRawValue == rawValue }
        )
        if let existing = try context.fetch(descriptor).first {
            return existing
        }
        let created = FeatureRecommendationRecord(showID: showID, feature: feature)
        context.insert(created)
        return created
    }
}
