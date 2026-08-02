import Foundation
import SwiftData

/// Save / 现场状态 / notification-sync for a single `Show`.
/// Detail screen and draft editor both call through here so apply + status +
/// reschedule stay consistent and unit-testable without a SwiftUI view.
enum ShowMutationCoordinator {
    /// Apply draft fields to an existing show, persist, then reschedule notifications
    /// for the current focus. Throws on draft apply / save failure (after rollback).
    /// Returns whether notification reschedule succeeded.
    @MainActor
    static func applyDraft(
        _ draft: ShowDraft,
        to show: Show,
        shows: [Show],
        selections: [CurrentShowSelection],
        notificationStates: [NotificationSchedulingState],
        in modelContext: ModelContext,
        session: CurrentShowSession = CurrentShowSession()
    ) async throws -> Bool {
        do {
            try show.apply(draft)
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }
        return await syncNotifications(
            shows: shows,
            selections: selections,
            notificationStates: notificationStates,
            in: modelContext,
            session: session
        )
    }

    /// Apply a status mutation (postpone / cancel / restore), clear manual current
    /// if canceled, persist, then reschedule. Returns toast tone + message.
    @MainActor
    static func updateStatus(
        show: Show,
        message: String,
        shows: [Show],
        selections: [CurrentShowSelection],
        notificationStates: [NotificationSchedulingState],
        in modelContext: ModelContext,
        session: CurrentShowSession = CurrentShowSession(),
        mutation: () -> Void
    ) async -> ShowStatusActionResult {
        mutation()
        if show.changeStatus == .canceled,
           selections.first?.selectedShowID == show.id {
            selections.first?.clearManualSelection()
        }

        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            return ShowStatusActionResult(tone: .failure, message: "状态没有保存，请重试")
        }

        let didSync = await syncNotifications(
            shows: shows,
            selections: selections,
            notificationStates: notificationStates,
            in: modelContext,
            session: session
        )
        let presentedMessage = didSync ? message : "\(message)，通知暂未更新"
        return ShowStatusActionResult(
            tone: didSync ? .success : .neutral,
            message: presentedMessage
        )
    }

    /// Point notification focus at the session's current show and apply schedules.
    @MainActor
    @discardableResult
    static func syncNotifications(
        shows: [Show],
        selections: [CurrentShowSelection],
        notificationStates: [NotificationSchedulingState],
        in modelContext: ModelContext,
        session: CurrentShowSession = CurrentShowSession()
    ) async -> Bool {
        let currentShow = session.selectCurrentShow(
            from: shows,
            manualSelection: selections.first
        )
        updateNotificationFocus(
            showID: currentShow?.id,
            notificationStates: notificationStates,
            in: modelContext
        )

        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            return false
        }

        return await LocalNotificationCenter.shared.applyFocusChange(
            to: currentShow,
            in: modelContext
        )
    }

    /// Update manual current-show selection + notification focus models.
    @MainActor
    static func updateCurrentShowFocus(
        showID: UUID?,
        selections: [CurrentShowSelection],
        notificationStates: [NotificationSchedulingState],
        in modelContext: ModelContext
    ) {
        if let selection = selections.first {
            if let showID {
                selection.select(showID: showID)
            } else {
                selection.clearManualSelection()
            }
        } else if let showID {
            modelContext.insert(CurrentShowSelection(selectedShowID: showID))
        }

        updateNotificationFocus(
            showID: showID,
            notificationStates: notificationStates,
            in: modelContext
        )
    }

    @MainActor
    static func updateNotificationFocus(
        showID: UUID?,
        notificationStates: [NotificationSchedulingState],
        in modelContext: ModelContext
    ) {
        if let notificationState = notificationStates.first {
            notificationState.focus(showID: showID)
        } else if showID != nil {
            modelContext.insert(NotificationSchedulingState(focusedShowID: showID))
        }
    }
}
