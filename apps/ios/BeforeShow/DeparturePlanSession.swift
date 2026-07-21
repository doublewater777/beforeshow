import Foundation
import SwiftData

@MainActor
struct DeparturePlanSession {
    let show: Show
    var routeProvider: any TravelRouteProviding
    var calendar: Calendar

    init(
        show: Show,
        routeProvider: any TravelRouteProviding = MapKitTravelRouteProvider(),
        calendar: Calendar = .current
    ) {
        self.show = show
        self.routeProvider = routeProvider
        self.calendar = calendar
    }

    var effectiveStartDate: Date {
        CurrentShowTimeState.effectiveStartTime(for: show, calendar: calendar)
    }

    var defaultTargetArrivalAt: Date {
        calendar.date(byAdding: .hour, value: -1, to: effectiveStartDate) ?? effectiveStartDate
    }

    /// 演出预计结束时刻（显式结束时间 > 结束日期 > 类型时长估算），未知为 nil。
    var estimatedShowEndAt: Date? {
        CurrentShowTimeState(show: show, calendar: calendar).endBoundary
    }

    /// 返程默认离开时间：未散场取散场后 15 分钟，已散场取 15 分钟后。
    func defaultReturnLeaveAt(now: Date = Date()) -> Date {
        if let end = estimatedShowEndAt, end > now {
            return calendar.date(byAdding: .minute, value: 15, to: end) ?? now
        }
        return calendar.date(byAdding: .minute, value: 15, to: now) ?? now
    }

    var showFingerprint: String {
        [
            String(show.date.timeIntervalSince1970),
            String(show.startTime.timeIntervalSince1970),
            show.postponedDate.map { String($0.timeIntervalSince1970) } ?? "",
            show.changeStatus.rawValue,
            show.venueName ?? "",
            show.venueAddress ?? "",
            show.city ?? "",
        ].joined(separator: "|")
    }

    func generate(
        direction: RoundTripDirection,
        mode: TravelMode,
        origin: TravelPlace,
        destination: TravelPlace,
        targetTime: Date
    ) async throws -> TravelPlan {
        guard mode != .custom else { throw TravelRouteError.unsupportedMode }
        let route = try await routeProvider.route(
            from: origin,
            to: destination,
            mode: mode,
            timing: direction.routeTiming(at: targetTime)
        )
        return makePlan(
            direction: direction,
            mode: mode,
            origin: origin,
            destination: destination,
            targetTime: targetTime,
            route: route
        )
    }

    func generateTransitEstimate(
        direction: RoundTripDirection,
        origin: TravelPlace,
        destination: TravelPlace,
        targetTime: Date,
        durationMinutes: Int
    ) -> TravelPlan {
        makePlan(
            direction: direction,
            mode: .transit,
            origin: origin,
            destination: destination,
            targetTime: targetTime,
            route: TravelRouteResult(
                durationSeconds: TimeInterval(max(1, durationMinutes) * 60),
                distanceMeters: nil,
                steps: []
            )
        )
    }

    private func makePlan(
        direction: RoundTripDirection,
        mode: TravelMode,
        origin: TravelPlace,
        destination: TravelPlace,
        targetTime: Date,
        route: TravelRouteResult
    ) -> TravelPlan {
        let durationMinutes = max(1, Int((route.durationSeconds / 60).rounded(.up)))
        let leaveAt: Date
        let arriveAt: Date
        if direction == .outbound {
            arriveAt = targetTime
            leaveAt = targetTime.addingTimeInterval(-route.durationSeconds)
        } else {
            leaveAt = targetTime
            arriveAt = targetTime.addingTimeInterval(route.durationSeconds)
        }

        return TravelPlan(
            direction: direction,
            mode: mode,
            origin: origin,
            destination: destination,
            leaveAt: leaveAt,
            arriveAt: arriveAt,
            durationMinutes: durationMinutes,
            distanceMeters: route.distanceMeters,
            summary: summary(mode: mode, origin: origin, destination: destination, durationMinutes: durationMinutes),
            timeline: timeline(
                mode: mode,
                origin: origin,
                destination: destination,
                leaveAt: leaveAt,
                arriveAt: arriveAt,
                steps: route.steps
            ),
            showFingerprint: showFingerprint
        )
    }

    func ensurePlan(existing: RoundTripPlan?, in context: ModelContext) -> RoundTripPlan {
        if let existing { return existing }
        let plan = RoundTripPlan(showID: show.id)
        context.insert(plan)
        return plan
    }

    func save(_ travelPlan: TravelPlan, to plan: RoundTripPlan, in context: ModelContext) throws {
        plan.save(travelPlan)
        try context.save()
    }

    func timeText(_ date: Date, relativeTo referenceDate: Date? = nil) -> String {
        let reference = referenceDate ?? effectiveStartDate
        let referenceDay = calendar.startOfDay(for: reference)
        let day = calendar.startOfDay(for: date)
        let clock = Self.timeFormatter.string(from: date)
        let difference = calendar.dateComponents([.day], from: referenceDay, to: day).day ?? 0
        if difference == 0 { return clock }
        if difference == 1 { return "次日 \(clock)" }
        return Self.dateTimeFormatter.string(from: date)
    }

    private func summary(
        mode: TravelMode,
        origin: TravelPlace,
        destination: TravelPlace,
        durationMinutes: Int
    ) -> String {
        "从\(origin.name)\(mode.displayName)到\(destination.name)，约 \(durationMinutes) 分钟"
    }

    private func timeline(
        mode: TravelMode,
        origin: TravelPlace,
        destination: TravelPlace,
        leaveAt: Date,
        arriveAt: Date,
        steps: [String]
    ) -> [TravelTimelineNode] {
        let originNode = TravelTimelineNode(kind: .origin, title: "从\(origin.name)出发", date: leaveAt)
        let destinationNode = TravelTimelineNode(kind: .destination, title: "抵达\(destination.name)", date: arriveAt)

        if mode == .transit {
            let transferNodes = Array(steps
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .prefix(4)
                .map { TravelTimelineNode(kind: .transfer, title: $0) })
            return [originNode] + transferNodes + [destinationNode]
        }

        return [originNode, destinationNode]
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private static let dateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日 HH:mm"
        return formatter
    }()
}
