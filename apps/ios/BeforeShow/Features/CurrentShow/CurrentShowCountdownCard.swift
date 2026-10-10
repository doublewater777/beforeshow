import SwiftData
import SwiftUI

/// 首页倒计时信息卡的推荐 owner：每天定一个推荐，首页真正可见时记一次露出，
/// 点过即算处理过（ADR 0037）。卡片本身只负责呈现。
struct CurrentShowCountdownCard: View {
    let show: Show
    let snapshot: HomeHeroSnapshot
    let candidateShows: [Show]
    let isVisible: Bool
    let onRecommendation: (RecommendedFeature) -> Void
    var onEndShow: (() -> Void)? = nil
    var onCompanion: (() -> Void)? = nil
    var onMemoryFragments: (() -> Void)? = nil
    var onMemoryCreate: (() -> Void)? = nil
    var onOpenRoute: (() -> Void)? = nil
    var liveTimetable: LiveModeState? = nil
    var onOpenTimetable: (() -> Void)? = nil

    @Environment(\.modelContext) private var modelContext
    @Query private var recommendationRecords: [FeatureRecommendationRecord]
    @Query private var notificationRecords: [ShowNotificationScheduleRecord]
    @AppStorage(FeatureUsageEnvironment.widgetKey) private var hasInstalledWidget = false
    @AppStorage(FeatureUsageEnvironment.iCloudKey) private var isICloudAvailable = false

    var body: some View {
        let todayKey = FeatureRecommendationDay.key(for: snapshot.now)
        let recommendation = resolvedRecommendation(todayKey: todayKey)
        HomeCountdownLockup(
            show: show,
            snapshot: snapshot,
            onEndShow: onEndShow,
            onCompanion: onCompanion,
            onMemoryFragments: onMemoryFragments,
            onMemoryCreate: onMemoryCreate,
            onOpenRoute: onOpenRoute,
            recommendation: recommendation,
            onRecommendation: handle,
            liveTimetable: liveTimetable,
            onOpenTimetable: onOpenTimetable
        )
        .task(id: "\(show.id.uuidString)|\(recommendation?.rawValue ?? "-")|\(todayKey)|\(isVisible)") {
            recordExposure(recommendation, todayKey: todayKey)
        }
    }

    private func resolvedRecommendation(todayKey: String) -> RecommendedFeature? {
        guard let slot = CurrentShowCardRecommendation.slot(
            timeState: snapshot.timeState,
            hasConfirmedEnd: show.endedAt != nil
        ) else {
            return nil
        }
        let facts = FeatureUsageFacts(hasInstalledWidget: hasInstalledWidget, isICloudAvailable: isICloudAvailable)
        let ledger = FeatureRecommendationLedger.snapshot(
            shows: candidateShows,
            records: recommendationRecords,
            facts: facts,
            now: snapshot.now
        )
        let hasFutureShow = FeatureRecommendationLedger.nextFutureShow(
            excluding: show.id,
            in: candidateShows,
            now: snapshot.now
        ) != nil
        let todayNotificationFeature = notificationRecords.first {
            $0.showID == show.id && $0.feature != nil
                && FeatureRecommendationDay.key(for: $0.fireDate) == todayKey
        }?.feature
        return CurrentShowCardRecommendation.resolve(
            chain: slot.chain(
                isFestival: ShowFlavor.inferred(from: show) == .festival,
                hasFutureShow: hasFutureShow
            ),
            context: ledger.context(for: show.id),
            todayKey: todayKey,
            todayNotificationFeature: todayNotificationFeature
        )
    }

    private func handle(_ feature: RecommendedFeature) {
        do {
            try FeatureRecommendationLedger.markHandled(showID: show.id, feature: feature, in: modelContext)
            try modelContext.save()
        } catch {
            modelContext.rollback()
        }
        onRecommendation(feature)
    }

    private func recordExposure(_ feature: RecommendedFeature?, todayKey: String) {
        guard isVisible, let feature else { return }
        do {
            if try FeatureRecommendationLedger.recordExposure(
                showID: show.id,
                feature: feature,
                dayKey: todayKey,
                in: modelContext
            ) {
                try modelContext.save()
            }
        } catch {
            modelContext.rollback()
        }
    }
}
