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
        now _: Date = Date()
    ) -> Show? {
        guard let selectedShowID = manualSelection?.selectedShowID else { return nil }
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

/// CurrentShowManagementSection still contains its pre-Phase-1 notification observer,
/// but the router no longer publishes new delivery to that legacy property. This root
/// is now the only live owner of notification navigation and can open any Show without
/// changing the user's durable Current Show.
struct CurrentShowFeatureRootView: View {
    var isPlaybackActive = true
    @Binding var ceremonyPendingDetail: FootprintDetailDestination?

    @Query(sort: \Show.date) private var shows: [Show]
    @ObservedObject private var notificationRouter = NotificationDeepLinkRouter.shared
    @State private var notificationPresentation: CurrentShowNotificationPresentation?
    @State private var pendingMemoryCreate: PendingNotificationMemoryCreate?

    var body: some View {
        CurrentShowHomeView(
            isPlaybackActive: isPlaybackActive,
            ceremonyPendingDetail: $ceremonyPendingDetail
        )
        .task {
            consumeNotificationRouteIfNeeded()
        }
        .onChange(of: notificationRouter.featureRootDeepLink) { _, _ in
            consumeNotificationRouteIfNeeded()
        }
        .sheet(item: $notificationPresentation, onDismiss: presentPendingMemoryCreateIfNeeded) { presentation in
            if let show = shows.first(where: { $0.id == presentation.showID }) {
                switch presentation.destination {
                case .home:
                    NavigationStack {
                        ShowDetailView(show: show)
                    }
                    .preferredColorScheme(.dark)
                case .memoryFragments:
                    MemoryFragmentsSheet(show: show, pendingCreate: presentation.pendingCreate)
                case .memoryCreate:
                    MemoryCreateSourceSheet { option in
                        pendingMemoryCreate = PendingNotificationMemoryCreate(
                            showID: show.id,
                            option: option
                        )
                        notificationPresentation = nil
                    }
                }
            } else {
                Color.clear
            }
        }
    }

    private func consumeNotificationRouteIfNeeded() {
        guard notificationPresentation == nil,
              let deepLink = notificationRouter.featureRootDeepLink else {
            return
        }
        guard shows.contains(where: { $0.id == deepLink.showID }) else {
            _ = notificationRouter.consumeFeatureRoot()
            return
        }
        notificationPresentation = CurrentShowNotificationPresentation(
            showID: deepLink.showID,
            destination: deepLink.destination,
            pendingCreate: nil
        )
        _ = notificationRouter.consumeFeatureRoot()
    }

    private func presentPendingMemoryCreateIfNeeded() {
        guard let pendingMemoryCreate else {
            // A second notification may have arrived while the previous destination
            // was presented. Consume it only after presentation ownership is free.
            consumeNotificationRouteIfNeeded()
            return
        }
        self.pendingMemoryCreate = nil
        Task { @MainActor in
            await Task.yield()
            notificationPresentation = CurrentShowNotificationPresentation(
                showID: pendingMemoryCreate.showID,
                destination: .memoryFragments,
                pendingCreate: pendingMemoryCreate.option
            )
        }
    }
}

private struct PendingNotificationMemoryCreate {
    let showID: UUID
    let option: MemoryCreateSourceOption
}

private struct CurrentShowNotificationPresentation: Identifiable {
    let showID: UUID
    let destination: NotificationDeepLinkDestination
    let pendingCreate: MemoryCreateSourceOption?

    var id: String {
        "\(showID.uuidString)|\(destination.rawValue)|\(pendingCreate?.rawValue ?? "-")"
    }
}
