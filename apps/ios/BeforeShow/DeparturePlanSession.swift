import Foundation
import SwiftData

enum DepartureSessionFeedback: Equatable {
    case success(String)
    case failure(String)
    case neutral(String)
}

/// Outcome of searching 交通选项 for a 去程计划 form.
struct DepartureSearchOutcome: Equatable {
    var recommendations: [DepartureTransportMode: DepartureTransportOption]
    var searchError: String?
    /// When true, UI should expand manual-save panel (empty/failed search, no saved plan yet).
    var shouldOfferManualSave: Bool
    var feedback: DepartureSessionFeedback?
}

/// Deep module for 去程计划 / 出门方案: bootstrap form, search options, save, 常用出发地.
///
/// Deletion test: removing this module scatters origin/destination bootstrap,
/// provider error copy, save + SavedOrigin upsert, and clock helpers across
/// RoundTripPlanView (and home 出行小助手 map URL). Interface is small; behavior is not.
@MainActor
struct DeparturePlanSession {
    let show: Show
    var routeProvider: any DepartureRouteProviding
    var calendar: Calendar

    init(
        show: Show,
        routeProvider: any DepartureRouteProviding = MapKitDepartureRouteProvider(),
        calendar: Calendar = .current
    ) {
        self.show = show
        self.routeProvider = routeProvider
        self.calendar = calendar
    }

    // MARK: - Clocks

    var effectiveStartDate: Date {
        CurrentShowTimeState.effectiveStartTime(for: show, calendar: calendar)
    }

    var defaultTargetArrivalAt: Date {
        calendar.date(byAdding: .hour, value: -1, to: effectiveStartDate) ?? effectiveStartDate
    }

    var isShowStarted: Bool {
        effectiveStartDate <= Date()
    }

    // MARK: - Bootstrap

    /// 出发地优先级：本场已保存 > 常用出发地 > 空
    func resolvedOrigin(plan: RoundTripPlan?, savedOrigin: SavedOrigin?) -> String {
        if let savedPlanOrigin = plan?.departureOrigin, !savedPlanOrigin.isEmpty {
            return savedPlanOrigin
        }
        if let originText = savedOrigin?.addressText, !originText.isEmpty {
            return originText
        }
        return ""
    }

    func resolvedDestination(plan: RoundTripPlan?) -> String {
        plan?.departureDestination ?? show.departureDestination.text
    }

    func resolvedMeetingPoint(plan: RoundTripPlan?) -> String {
        plan?.departureMeetingPoint ?? ""
    }

    // MARK: - Search

    func searchOptions(
        origin: String,
        destination: String,
        meetingPoint: String,
        targetArrivalAt: Date,
        preferredModes: [DepartureTransportMode],
        selectedMode: DepartureTransportMode,
        force: Bool,
        hasSavedDeparturePlan: Bool
    ) async -> DepartureSearchOutcome {
        let trimmedOrigin = origin.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDestination = destination.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedOrigin.isEmpty, !trimmedDestination.isEmpty else {
            let missingDestination = trimmedDestination.isEmpty
            return DepartureSearchOutcome(
                recommendations: [:],
                searchError: missingDestination
                    ? "这场还没填场馆地址，去编辑现场补一下。"
                    : "请先填写或定位出发地。",
                shouldOfferManualSave: false,
                feedback: .neutral(missingDestination ? "请先补场馆地址" : "请先填写或定位出发地")
            )
        }

        let request = DepartureRouteRequest(
            show: show,
            origin: trimmedOrigin,
            destination: trimmedDestination,
            meetingPoint: meetingPoint,
            targetArrivalAt: targetArrivalAt,
            preferredModes: preferredModes,
            notes: nil
        )

        do {
            let options = try await routeProvider.searchOptions(for: request)
            var newRecommendations: [DepartureTransportMode: DepartureTransportOption] = [:]
            for option in options {
                newRecommendations[option.mode] = option
            }

            if newRecommendations.isEmpty {
                return DepartureSearchOutcome(
                    recommendations: [:],
                    searchError: "没查到路线。请把到场地址写得更具体，或检查出发地。",
                    shouldOfferManualSave: !hasSavedDeparturePlan,
                    feedback: hasSavedDeparturePlan ? nil : .failure("暂时没拿到路线")
                )
            }

            return DepartureSearchOutcome(
                recommendations: newRecommendations,
                searchError: nil,
                shouldOfferManualSave: false,
                feedback: force ? .success("已重新生成") : nil
            )
        } catch {
            return DepartureSearchOutcome(
                recommendations: [:],
                searchError: errorMessage(for: error),
                shouldOfferManualSave: !hasSavedDeparturePlan,
                feedback: hasSavedDeparturePlan ? nil : .failure("暂时没拿到路线")
            )
        }
    }

    func preferredMode(
        after recommendations: [DepartureTransportMode: DepartureTransportOption],
        current: DepartureTransportMode,
        displayOrder: [DepartureTransportMode]
    ) -> DepartureTransportMode {
        if recommendations[current] != nil {
            return current
        }
        return displayOrder.first(where: { recommendations[$0] != nil }) ?? current
    }

    func errorMessage(for error: Error) -> String {
        if let providerError = error as? DepartureRouteProviderError {
            switch providerError {
            case .providerUnavailable:
                return "地图服务暂时不可用，可以手动保存出门方案，不会编造路线。"
            case .geocodingFailed:
                return "出发地或到场地址没识别到，写得更具体试试，或手动保存。"
            case .noOptions:
                return "没查到路线。请把到场地址写得更具体，或检查出发地。"
            case .missingOrigin, .missingDestination:
                return "出发地和到场地址都要填。"
            }
        }
        return "没查到路线。请把到场地址写得更具体，或检查出发地，也可以先手动保存出门方案。"
    }

    // MARK: - Save

    func ensurePlan(existing: RoundTripPlan?, in context: ModelContext) -> RoundTripPlan {
        if let existing {
            return existing
        }
        let plan = RoundTripPlan(showID: show.id)
        context.insert(plan)
        return plan
    }

    func save(
        option: DepartureTransportOption,
        plan: RoundTripPlan,
        origin: String,
        destination: String,
        meetingPoint: String,
        savedOrigin: SavedOrigin?,
        in context: ModelContext
    ) throws {
        let trimmedOrigin = origin.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDestination = destination.trimmingCharacters(in: .whitespacesAndNewlines)
        plan.saveDeparture(
            option: option,
            origin: trimmedOrigin,
            destination: trimmedDestination,
            meetingPoint: meetingPoint
        )
        try context.save()
        try upsertSavedOrigin(addressText: trimmedOrigin, existing: savedOrigin, in: context)
    }

    enum ManualSaveError: Error, Equatable {
        case missingOrigin
        case missingDestination
    }

    func saveManual(
        plan: RoundTripPlan,
        origin: String,
        destination: String,
        leaveAt: Date,
        arriveAt: Date,
        mode: DepartureTransportMode,
        summary: String,
        meetingPoint: String,
        savedOrigin: SavedOrigin?,
        in context: ModelContext
    ) throws {
        let trimmedOrigin = origin.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDestination = destination.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedOrigin.isEmpty else { throw ManualSaveError.missingOrigin }
        guard !trimmedDestination.isEmpty else { throw ManualSaveError.missingDestination }

        let trimmedSummary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalSummary = trimmedSummary.isEmpty
            ? "\(mode.displayName)到 \(trimmedDestination)"
            : trimmedSummary

        plan.saveManualDeparture(
            origin: trimmedOrigin,
            destination: trimmedDestination,
            leaveAt: leaveAt,
            arriveAt: arriveAt,
            mode: mode,
            summary: finalSummary,
            meetingPoint: meetingPoint
        )
        try context.save()
        try upsertSavedOrigin(addressText: trimmedOrigin, existing: savedOrigin, in: context)
    }

    func upsertSavedOrigin(
        addressText: String,
        existing: SavedOrigin?,
        in context: ModelContext
    ) throws {
        let trimmed = addressText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if let existing, existing.addressText != trimmed {
            existing.addressText = trimmed
            existing.name = trimmed
            existing.updatedAt = Date()
        } else if existing == nil {
            context.insert(SavedOrigin(name: trimmed, addressText: trimmed))
        }
        try context.save()
    }

    // MARK: - Presentation helpers (domain clocks / saved option)

    func savedOption(from plan: RoundTripPlan) -> DepartureTransportOption? {
        guard let mode = plan.savedDepartureMode,
              let leaveAt = plan.departureLeaveAt,
              let arriveAt = plan.departureArriveAt,
              let duration = plan.departureDurationMinutes,
              let summary = plan.departureSummary,
              let provider = plan.savedDepartureProvider else {
            return nil
        }
        return DepartureTransportOption(
            id: plan.id.uuidString,
            mode: mode,
            leaveAt: leaveAt,
            arriveAt: arriveAt,
            durationMinutes: duration,
            distanceMeters: plan.departureDistanceMeters,
            summary: summary,
            experienceTag: plan.departureExperienceTag ?? "已保存",
            provider: provider,
            navigationURL: plan.savedDepartureNavigationURL,
            capturedAt: plan.departureCapturedAt ?? plan.updatedAt
        )
    }

    func savedDepartureTimeLine(_ plan: RoundTripPlan) -> String {
        guard let mode = plan.savedDepartureMode,
              let leaveAt = plan.departureLeaveAt,
              let arriveAt = plan.departureArriveAt,
              let duration = plan.departureDurationMinutes else {
            return "出发前打开地图确认实时路线"
        }
        return "\(timeText(leaveAt)) 出门 · \(mode.displayName)约 \(duration) 分钟 · \(timeText(arriveAt)) 到"
    }

    func timeText(_ date: Date) -> String {
        let showDay = calendar.startOfDay(for: effectiveStartDate)
        let day = calendar.startOfDay(for: date)
        if day == showDay {
            return Self.timeFormatter.string(from: date)
        }
        let clock = Self.timeFormatter.string(from: date)
        let dayDiff = calendar.dateComponents([.day], from: showDay, to: day).day ?? 0
        if dayDiff == 1 {
            return "次日 \(clock)"
        }
        if dayDiff > 1 {
            return "\(calendar.component(.month, from: date))/\(calendar.component(.day, from: date)) \(clock)"
        }
        return "前日 \(clock)"
    }

    func navigationURL(for plan: RoundTripPlan) -> URL? {
        if let option = savedOption(from: plan), let url = option.navigationURL {
            return url
        }
        return Self.appleMapsDirectionsURL(
            origin: plan.departureOrigin,
            destination: plan.departureDestination
        )
    }

    nonisolated static func appleMapsDirectionsURL(origin: String?, destination: String?) -> URL? {
        guard let destination,
              !destination.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        var components = URLComponents(string: "https://maps.apple.com/")
        var items: [URLQueryItem] = [URLQueryItem(name: "daddr", value: destination)]
        if let origin, !origin.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            items.insert(URLQueryItem(name: "saddr", value: origin), at: 0)
        }
        components?.queryItems = items
        return components?.url
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}
