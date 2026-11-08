import Foundation
import SwiftData
import SwiftUI

/// Read model for one 现场 under 当前现场 policy: durable selection result and phase.
struct CurrentShowSnapshot {
    let show: Show
    let phase: CurrentShowTimeState
}

/// Product-level read seam for the user-owned Current Show.
struct CurrentShowSession {
    let postShowRetentionDays: Int
    let calendar: Calendar

    init(postShowRetentionDays: Int = 3, calendar: Calendar = .current) {
        self.postShowRetentionDays = postShowRetentionDays
        self.calendar = calendar
    }

    func selectCurrentShow(
        from shows: [Show],
        manualSelection: CurrentShowSelection? = nil,
        now: Date = Date()
    ) -> Show? {
        guard let manualSelection else { return nil }
        if manualSelection.isManual == false {
            return InitialCurrentShowPolicy(calendar: calendar).candidate(
                from: shows,
                retaining: manualSelection.selectedShowID,
                now: now
            )
        }
        guard let selectedShowID = manualSelection.selectedShowID else { return nil }
        return shows.first(where: { $0.id == selectedShowID })
    }

    func isCurrent(
        _ show: Show,
        among shows: [Show],
        manualSelection: CurrentShowSelection? = nil,
        now: Date = Date()
    ) -> Bool {
        selectCurrentShow(from: shows, manualSelection: manualSelection, now: now)?.id == show.id
    }

    /// Any persisted show can be explicitly chosen regardless of lifecycle state.
    func isManuallySelectable(_ show: Show, now _: Date = Date()) -> Bool {
        _ = show
        return true
    }

    func phase(for show: Show, now: Date = Date()) -> CurrentShowTimeState {
        CurrentShowTimeState(
            show: show,
            calendar: calendar,
            now: now,
            retentionDays: postShowRetentionDays
        )
    }

    func snapshot(for show: Show, now: Date = Date()) -> CurrentShowSnapshot {
        CurrentShowSnapshot(show: show, phase: phase(for: show, now: now))
    }

    func resolve(
        shows: [Show],
        manualSelection: CurrentShowSelection? = nil,
        now: Date = Date()
    ) -> CurrentShowSnapshot? {
        guard let show = selectCurrentShow(
            from: shows,
            manualSelection: manualSelection,
            now: now
        ) else {
            return nil
        }
        return snapshot(for: show, now: now)
    }
}

// MARK: - Notification-owned Current Show feature root

/// Owns Current notification destinations. Listening tab routes belong to the app
/// root; destinations of the Current Show open in place on its home, other shows
/// open their detail (ADR 0037). Routing never mutates CurrentShowSelection.
struct CurrentShowFeatureRootView: View {
    var isPlaybackActive = true

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Show.date) private var shows: [Show]
    @Query private var selections: [CurrentShowSelection]
    @State private var notificationRouter = NotificationDeepLinkRouter.shared
    @State private var notificationPresentation: CurrentShowNotificationPresentation?
    /// `notificationPresentation` may become nil before the sheet dismissal
    /// animation has actually finished. Keep a root-owned latch until onDismiss
    /// decides whether another notification destination follows immediately.
    @State private var isNotificationPresentationActive = false

    var body: some View {
        CurrentShowHomeView(
            isPlaybackActive: isPlaybackActive,
            isFeaturePresentationActive: isNotificationPresentationActive
        )
        .task {
            consumeNotificationRouteIfNeeded()
        }
        .onChange(of: notificationRouter.featureRootDeepLink) { _, _ in
            consumeNotificationRouteIfNeeded()
        }
        .onChange(of: notificationRouter.handledRecommendation, initial: true) { _, _ in
            recordHandledRecommendation()
        }
        .sheet(item: $notificationPresentation, onDismiss: notificationPresentationDidDismiss) { presentation in
            if let show = shows.first(where: { $0.id == presentation.showID }) {
                switch presentation.destination {
                case .memoryFragments:
                    MemoryFragmentsSheet(show: show)
                case .memoryCreate:
                    MemoryFragmentsSheet(show: show, pendingCreate: .quick)
                case .addShow:
                    AddShowCoordinatorSheet()
                case .timetable:
                    ShowAssetSheet(showID: show.id, showName: show.name, kind: .timetable)
                case .weatherDetail:
                    CurrentShowWeatherSheet(
                        show: show,
                        initialWeather: LiveShowWeatherService.shared.cachedWeather(for: show.id),
                        venueName: show.venueName,
                        city: show.city
                    )
                default:
                    CurrentShowClosableSheet {
                        ShowDetailView(show: show, onDetailVisibilityChange: { _ in })
                    }
                }
            } else {
                Color.clear
            }
        }
    }

    private func consumeNotificationRouteIfNeeded() {
        guard notificationPresentation == nil,
              let deepLink = notificationRouter.featureRootDeepLink,
              deepLink.destination != .listen else {
            return
        }
        _ = notificationRouter.consumeFeatureRoot()
        let currentShow = CurrentShowSession().selectCurrentShow(
            from: shows,
            manualSelection: CurrentShowSelectionStore.canonical(in: selections)
        )
        let wildcardID = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
        let target = (deepLink.showID == wildcardID ? currentShow : shows.first(where: { $0.id == deepLink.showID })) ?? currentShow
        guard let target else { return }
        let currentShowID = currentShow?.id

        switch deepLink.destination {
        case .home:
            if target.id != currentShowID { present(showID: target.id, destination: .home) }
        case .listen:
            return
        case .memoryFragments, .memoryCreate, .addShow:
            present(showID: target.id, destination: deepLink.destination)
        case .nextShow:
            if let next = FeatureRecommendationLedger.nextFutureShow(excluding: target.id, in: shows, now: Date()) {
                present(showID: next.id, destination: .nextShow)
            } else {
                present(showID: target.id, destination: .addShow)
            }
        default:
            if target.id == currentShowID {
                notificationRouter.forwardToCurrentShow(
                    NotificationDeepLink(
                        showID: target.id,
                        destination: deepLink.destination,
                        feature: deepLink.feature,
                        discID: deepLink.discID,
                        artistID: deepLink.artistID,
                        artistName: deepLink.artistName
                    )
                )
            } else {
                present(showID: target.id, destination: deepLink.destination)
            }
        }
    }

    private func present(showID: UUID, destination: NotificationDeepLink.Destination) {
        isNotificationPresentationActive = true
        notificationPresentation = CurrentShowNotificationPresentation(
            showID: showID,
            destination: destination
        )
    }

    /// 点过推荐通知即算处理过：记下来并重排，后续节点换下一个功能。
    private func recordHandledRecommendation() {
        guard let deepLink = notificationRouter.consumeHandledRecommendation(),
              let feature = deepLink.feature else {
            return
        }
        do {
            try FeatureRecommendationLedger.markHandled(showID: deepLink.showID, feature: feature, in: modelContext)
            try modelContext.save()
            ProductAnalytics.capture(.featureRecommendationTapped(showID: deepLink.showID, feature: feature, surface: .notification))
        } catch {
            modelContext.rollback()
        }
        let container = modelContext.container
        Task {
            await LocalNotificationCenter.shared.reconcilePortfolio(in: ModelContext(container))
        }
    }

    private func notificationPresentationDidDismiss() {
        // A second notification may have arrived while the previous destination
        // was presented. Consume it only after presentation ownership is free.
        consumeNotificationRouteIfNeeded()
        if notificationPresentation == nil {
            isNotificationPresentationActive = false
        }
    }
}

private struct CurrentShowNotificationPresentation: Identifiable {
    let showID: UUID
    let destination: NotificationDeepLink.Destination

    var id: String {
        "\(showID.uuidString)|\(destination.rawValue)"
    }
}
