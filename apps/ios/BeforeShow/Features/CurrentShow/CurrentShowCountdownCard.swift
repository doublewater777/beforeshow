import SwiftData
import SwiftUI

/// 首页倒计时信息卡的推荐 owner：每天定一个推荐，首页真正可见时记一次露出，
/// 点过即算处理过（ADR 0037）。卡片本身只负责呈现。
struct CurrentShowCountdownCard: View {
    let show: Show
    let snapshot: HomeHeroSnapshot
    let candidateShows: [Show]
    let recommendation: RecommendedFeature?
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

    var body: some View {
        let todayKey = FeatureRecommendationDay.key(for: snapshot.now)
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
