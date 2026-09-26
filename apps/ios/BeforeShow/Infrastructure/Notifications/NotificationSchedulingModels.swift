import Foundation
import SwiftData
import UserNotifications

enum NotificationAuthorizationState: String, Codable, Equatable {
    case notDetermined
    case denied
    case authorized
    case provisional
}

extension NotificationAuthorizationState {
    init(_ status: UNAuthorizationStatus) {
        switch status {
        case .notDetermined: self = .notDetermined
        case .denied: self = .denied
        case .authorized: self = .authorized
        case .provisional: self = .provisional
        case .ephemeral: self = .authorized
        @unknown default: self = .notDetermined
        }
    }
}

struct NotificationPermissionPolicy {
    func shouldRequestPermission(
        hasAddedShow: Bool,
        authorizationState: NotificationAuthorizationState,
        hasRequestedPermissionAfterFirstShow: Bool
    ) -> Bool {
        hasAddedShow
            && authorizationState == .notDetermined
            && !hasRequestedPermissionAfterFirstShow
    }

    func shouldRequestOnCurrentShow(
        authorizationState: NotificationAuthorizationState,
        hasRequestedPermissionAfterFirstShow: Bool,
        currentShowKind: CurrentShowTimeKind,
        isCurrentShowVisible: Bool
    ) -> Bool {
        guard isCurrentShowVisible,
              shouldRequestPermission(
                hasAddedShow: true,
                authorizationState: authorizationState,
                hasRequestedPermissionAfterFirstShow: hasRequestedPermissionAfterFirstShow
              ) else {
            return false
        }

        switch currentShowKind {
        case .before, .today, .dayEnded:
            return true
        case .postShow, .ended, .canceled, .postponed:
            return false
        }
    }
}

enum ShowNotificationMilestone: String, CaseIterable, Codable, Equatable {
    case fourteenDaysBefore
    case sevenDaysBefore
    case threeDaysBefore
    case oneDayBefore
    case showDayMorning
    case showDay
    case openingMemory
    case afterShow
}

extension ShowNotificationMilestone {
    var isTimeSensitive: Bool {
        self == .showDay
    }

    var isAnticipation: Bool {
        switch self {
        case .fourteenDaysBefore, .sevenDaysBefore, .threeDaysBefore, .oneDayBefore:
            return true
        case .showDayMorning, .showDay, .openingMemory, .afterShow:
            return false
        }
    }

    fileprivate var portfolioPriority: Int {
        switch self {
        case .showDay: return 0
        case .openingMemory: return 1
        case .showDayMorning: return 2
        case .afterShow: return 3
        case .oneDayBefore: return 4
        case .threeDaysBefore: return 5
        case .sevenDaysBefore: return 6
        case .fourteenDaysBefore: return 7
        }
    }
}

enum ShowFlavor {
    case festival
    case livehouse
    case concert

    static func inferred(from show: Show) -> ShowFlavor {
        let haystack = [show.name, show.venueName ?? ""]
            .joined(separator: " ")
            .lowercased()

        if haystack.contains("音乐节") || haystack.contains("festival")
            || haystack.contains("live house 音乐节") {
            return .festival
        }
        if haystack.contains("livehouse") || haystack.contains("live house")
            || haystack.contains("酒球会") || haystack.contains("club") {
            return .livehouse
        }
        return .concert
    }
}

struct NotificationCopyContext {
    let showName: String
    let flavor: ShowFlavor
    let place: String?
    let isMultiDay: Bool
    let startClock: String?

    init(show: Show, timeState: CurrentShowTimeState, calendar: Calendar) {
        self.showName = show.name
        self.flavor = ShowFlavor.inferred(from: show)

        let venue = show.venueName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let city = show.city?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let venue, !venue.isEmpty {
            self.place = venue
        } else if let city, !city.isEmpty {
            self.place = city
        } else {
            self.place = nil
        }

        if let endDate = timeState.effectiveEndDate {
            self.isMultiDay = calendar.startOfDay(for: endDate) > calendar.startOfDay(for: timeState.effectiveDate)
        } else {
            self.isMultiDay = false
        }

        if let start = timeState.effectiveStartTime {
            self.startClock = String(
                format: "%02d:%02d",
                calendar.component(.hour, from: start),
                calendar.component(.minute, from: start)
            )
        } else {
            self.startClock = nil
        }
    }
}

struct ScheduledShowNotification: Equatable {
    let showID: UUID
    let milestone: ShowNotificationMilestone
    let fireDate: Date
    let title: String
    let body: String
    var isBackfill: Bool = false
}

enum NotificationReconcileReason: Equatable {
    case startup
    case foreground
    case mutation
    /// Compatibility hand-off from Add Show: only this reason may mint anticipation backfill.
    case showAddedCandidate(UUID)
}

struct NotificationPortfolioPlan {
    static let maximumScheduledRequests = 56

    /// Requests that should exist in UNUserNotificationCenter now.
    let scheduledRequests: [ScheduledShowNotification]
    /// Backfills keep their minted fire date/copy even when capacity temporarily defers them.
    let retainedBackfillRequests: [ScheduledShowNotification]
    let backfillShowIDsToMarkMinted: [UUID]

    var modelRequests: [ScheduledShowNotification] {
        var byIdentifier = Dictionary(
            uniqueKeysWithValues: scheduledRequests.map { ($0.requestIdentifier, $0) }
        )
        for request in retainedBackfillRequests {
            byIdentifier[request.requestIdentifier] = request
        }
        return Array(byIdentifier.values)
    }
}

struct NotificationPortfolioPlanner {
    let scheduler: LocalNotificationScheduler

    init(calendar: Calendar = .current) {
        self.scheduler = LocalNotificationScheduler(calendar: calendar)
    }

    func plan(
        shows: [Show],
        existingRecords: [ShowNotificationScheduleRecord],
        schedulingState: NotificationSchedulingState?,
        reason: NotificationReconcileReason,
        now: Date = Date()
    ) -> NotificationPortfolioPlan {
        let eligibleShows = shows.filter(Self.isEligibleForPortfolio)
        let liveShowIDs = Set(eligibleShows.map(\.id))

        var naturalRequests: [ScheduledShowNotification] = []
        for show in eligibleShows {
            if show.endedAt != nil {
                if let afterShow = scheduler.afterShowRequest(for: show, now: now) {
                    naturalRequests.append(afterShow)
                }
            } else {
                naturalRequests.append(contentsOf: scheduler.futureRequests(for: show, now: now))
            }
        }

        var backfillRequests = existingRecords
            .filter {
                $0.isBackfill == true
                    && $0.fireDate > now
                    && liveShowIDs.contains($0.showID)
            }
            .map {
                ScheduledShowNotification(
                    showID: $0.showID,
                    milestone: $0.milestone,
                    fireDate: $0.fireDate,
                    title: $0.title ?? "",
                    body: $0.body ?? "",
                    isBackfill: true
                )
            }

        var backfillShowIDsToMarkMinted: [UUID] = []
        if case .showAddedCandidate(let showID) = reason,
           let show = eligibleShows.first(where: { $0.id == showID }),
           schedulingState?.hasMintedBackfill(for: showID) != true {
            backfillRequests.append(contentsOf: scheduler.backfillRequests(for: show, now: now))
            backfillShowIDsToMarkMinted.append(showID)
        }

        naturalRequests = Self.deduplicated(naturalRequests)
        backfillRequests = Self.deduplicated(backfillRequests)

        let allCandidates = Self.sortedForScheduling(naturalRequests + backfillRequests)
        let scheduled = Array(allCandidates.prefix(NotificationPortfolioPlan.maximumScheduledRequests))

        return NotificationPortfolioPlan(
            scheduledRequests: scheduled,
            retainedBackfillRequests: backfillRequests,
            backfillShowIDsToMarkMinted: backfillShowIDsToMarkMinted
        )
    }

    private static func isEligibleForPortfolio(_ show: Show) -> Bool {
        guard show.wasAddedAsHistorical != true,
              show.changeStatus != .canceled else {
            return false
        }
        if show.changeStatus == .postponed, show.postponedDate == nil {
            return false
        }
        return true
    }

    private static func deduplicated(
        _ requests: [ScheduledShowNotification]
    ) -> [ScheduledShowNotification] {
        var seen = Set<String>()
        return requests.filter { seen.insert($0.requestIdentifier).inserted }
    }

    private static func sortedForScheduling(
        _ requests: [ScheduledShowNotification]
    ) -> [ScheduledShowNotification] {
        requests.sorted { lhs, rhs in
            if lhs.fireDate != rhs.fireDate { return lhs.fireDate < rhs.fireDate }
            if lhs.milestone.portfolioPriority != rhs.milestone.portfolioPriority {
                return lhs.milestone.portfolioPriority < rhs.milestone.portfolioPriority
            }
            if lhs.showID != rhs.showID {
                return lhs.showID.uuidString < rhs.showID.uuidString
            }
            return lhs.requestIdentifier < rhs.requestIdentifier
        }
    }
}

@Model
final class NotificationSchedulingState {
    var id: UUID
    /// Crash-safe hand-off between Add Show persistence and the next portfolio reconcile.
    /// The original persisted name is mapped so existing development stores migrate
    /// without losing an interrupted just-added-show hand-off.
    @Attribute(originalName: "focusedShowID")
    var stagedBackfillShowID: UUID?
    var hasRequestedPermissionAfterFirstShow: Bool
    var backfillMintedShowIDs: [UUID]?
    /// Optional keeps the development-store schema lightweight. Version 1 means
    /// pre-portfolio shows were marked as already backfill-minted.
    var portfolioMigrationVersion: Int?
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        stagedBackfillShowID: UUID? = nil,
        hasRequestedPermissionAfterFirstShow: Bool = false,
        backfillMintedShowIDs: [UUID]? = nil,
        portfolioMigrationVersion: Int? = nil,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.stagedBackfillShowID = stagedBackfillShowID
        self.hasRequestedPermissionAfterFirstShow = hasRequestedPermissionAfterFirstShow
        self.backfillMintedShowIDs = backfillMintedShowIDs
        self.portfolioMigrationVersion = portfolioMigrationVersion
        self.updatedAt = updatedAt
    }

    func recordPermissionRequest() {
        hasRequestedPermissionAfterFirstShow = true
        updatedAt = Date()
    }

    /// Transitional hand-off used only between Add Show persistence and portfolio reconcile.
    func stageBackfillCandidate(showID: UUID) {
        stagedBackfillShowID = showID
        updatedAt = Date()
    }

    func clearStagedBackfillCandidate() {
        stagedBackfillShowID = nil
        updatedAt = Date()
    }

    func hasMintedBackfill(for showID: UUID) -> Bool {
        backfillMintedShowIDs?.contains(showID) ?? false
    }

    func markBackfillMinted(showID: UUID) {
        var ids = backfillMintedShowIDs ?? []
        if !ids.contains(showID) {
            ids.append(showID)
            backfillMintedShowIDs = ids
        }
        updatedAt = Date()
    }
}

@Model
final class ShowNotificationScheduleRecord {
    var id: UUID
    var showID: UUID
    var milestoneRawValue: String
    var fireDate: Date
    var isBackfill: Bool?
    var title: String?
    var body: String?
    var createdAt: Date

    var milestone: ShowNotificationMilestone {
        ShowNotificationMilestone(rawValue: milestoneRawValue) ?? .showDay
    }

    init(
        id: UUID = UUID(),
        showID: UUID,
        milestone: ShowNotificationMilestone,
        fireDate: Date,
        isBackfill: Bool = false,
        title: String = "",
        body: String = "",
        createdAt: Date = Date()
    ) {
        self.id = id
        self.showID = showID
        self.milestoneRawValue = milestone.rawValue
        self.fireDate = fireDate
        self.isBackfill = isBackfill
        self.title = title
        self.body = body
        self.createdAt = createdAt
    }

    func matches(_ request: ScheduledShowNotification) -> Bool {
        showID == request.showID
            && milestoneRawValue == request.milestone.rawValue
            && fireDate == request.fireDate
            && (isBackfill == true) == request.isBackfill
            && (title ?? "") == request.title
            && (body ?? "") == request.body
    }

    func apply(_ request: ScheduledShowNotification) {
        showID = request.showID
        milestoneRawValue = request.milestone.rawValue
        fireDate = request.fireDate
        isBackfill = request.isBackfill
        title = request.title
        body = request.body
    }
}
