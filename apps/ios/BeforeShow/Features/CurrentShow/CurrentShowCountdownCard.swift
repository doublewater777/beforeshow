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
            onRecommendation: handle
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

enum CurrentShowCardRecommendation {
    /// 主卡在哪个阶段做功能推荐：开场前（分 7 天内外）与确认散场之后。
    static func slot(timeState: CurrentShowTimeState, hasConfirmedEnd: Bool) -> FeatureRecommendationSlot? {
        if hasConfirmedEnd {
            switch timeState.kind {
            case .postShow: return .cardPostShow
            case .ended: return .cardAfterRetention
            default: return nil
            }
        }
        guard timeState.kind == .before else { return nil }
        return timeState.dayDistance > 7 ? .cardFarBefore : .cardNearBefore
    }

    /// 一天只换一次：今天已经露出（卡片或通知）的功能保持到今天结束，用过或点过就收起；
    /// 当天有推荐通知时推同一个；否则按候选顺序取第一个可推荐的。
    static func resolve(
        chain: [RecommendedFeature],
        context: FeatureRecommendationContext,
        todayKey: String,
        todayNotificationFeature: RecommendedFeature?
    ) -> RecommendedFeature? {
        let ordered = chain + RecommendedFeature.allCases.filter { !chain.contains($0) }
        let exposedToday = ordered.filter { context.records[$0]?.exposureDayKeys.contains(todayKey) == true }
        if !exposedToday.isEmpty {
            return exposedToday.first {
                FeatureRecommendationPolicy.isEligible($0, context: context, todayKey: todayKey)
            }
        }
        if let feature = todayNotificationFeature,
           FeatureRecommendationPolicy.isEligible(feature, context: context, todayKey: todayKey) {
            return feature
        }
        return FeatureRecommendationPolicy.candidate(from: chain, context: context, todayKey: todayKey)
    }
}
