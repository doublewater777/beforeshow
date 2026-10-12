import SwiftData
import SwiftUI

/// 使用父级同一次推荐决策呈现 Banner；可见时记录曝光，点击时标记处理（ADR 0037）。
struct CurrentShowCountdownCard: View {
    let show: Show
    let snapshot: HomeHeroSnapshot
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
