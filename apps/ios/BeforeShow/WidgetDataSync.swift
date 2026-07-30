import ActivityKit
import Foundation
import WidgetKit

// MARK: - Widget Data Sync
// 「当前现场」变化时的单一出口:写 App Group 快照 → 刷新 widget timeline →
// 对齐 Live Activity 生命周期。RootView 在 shows/selections 变化与回到前台时调用。

enum WidgetDataSync {
    static func sync(shows: [Show], manualSelection: CurrentShowSelection?, now: Date = Date()) {
        let session = CurrentShowSession()
        let show = session.selectCurrentShow(from: shows, manualSelection: manualSelection, now: now)
        let snapshot = show.map { WidgetShowSnapshot(show: $0, generatedAt: now) }
        WidgetSnapshotStore.write(snapshot)
        WidgetCenter.shared.reloadAllTimelines()

        // Show 是 SwiftData @Model(非 Sendable),跨并发边界只传值类型快照
        Task {
            await ShowLiveActivityController.shared.sync(snapshot: snapshot, now: now)
        }
    }
}

extension WidgetShowSnapshot {
    init(show: Show, generatedAt: Date) {
        self.init(
            showID: show.id,
            name: show.name,
            city: show.city,
            venueName: show.venueName,
            coverImageURL: show.coverImageURL,
            timing: show.timingFields,
            generatedAt: generatedAt
        )
    }
}

// MARK: - Live Activity Controller

/// 生命周期(设计定稿):开场前 12h 内启动(平台实时活动上限),越过预计谢幕结束。
/// 启动前先把封面拉进 App Group 缓存,banner 才能直接显示海报。
/// 无可变状态,Sendable 安全。
final class ShowLiveActivityController: @unchecked Sendable {
    static let shared = ShowLiveActivityController()

    private static let leadTime: TimeInterval = 12 * 3_600

    private init() {}

    func sync(snapshot: WidgetShowSnapshot?, now: Date) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            await endAll()
            return
        }

        guard let snapshot,
              snapshot.timing.changeStatus != .canceled else {
            await endAll()
            return
        }

        let state = CurrentShowTimeState(timing: snapshot.timing, now: now)
        guard let start = state.effectiveStartTime else {
            await endAll()
            return
        }
        let activityEnd = state.endBoundary ?? start
        guard now >= start.addingTimeInterval(-Self.leadTime), now < activityEnd else {
            await endAll()
            return
        }

        if let cover = snapshot.coverImageURL {
            await WidgetCoverCache.refresh(for: cover)
        }

        let attributes = ShowLiveActivityAttributes(
            showID: snapshot.showID.uuidString,
            showName: snapshot.name,
            city: snapshot.city,
            venueName: snapshot.venueName,
            startDate: start,
            endDate: state.endBoundary,
            coverImageFilename: snapshot.coverImageURL.flatMap { WidgetCoverCache.freshCoverFilename(for: $0) }
        )
        let phase: ShowLiveActivityPhase = now >= start ? .live : .countdown
        let content = ActivityContent(state: ShowLiveActivityAttributes.ContentState(phase: phase), staleDate: nil)

        let existing = Activity<ShowLiveActivityAttributes>.activities.first
        if let existing, existing.attributes.showID == attributes.showID {
            await existing.update(content)
        } else {
            if let existing {
                await existing.end(nil, dismissalPolicy: .immediate)
            }
            _ = try? Activity<ShowLiveActivityAttributes>.request(
                attributes: attributes,
                content: content,
                pushType: nil
            )
        }
    }

    private func endAll() async {
        for activity in Activity<ShowLiveActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }
}
