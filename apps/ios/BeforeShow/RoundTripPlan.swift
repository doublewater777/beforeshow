import Foundation
import MapKit
import SwiftData
import UIKit

enum RoundTripDirection: String, CaseIterable, Codable, Equatable {
    case outbound
    case `return`

    var displayName: String {
        switch self {
        case .outbound: return "去程"
        case .return: return "返程"
        }
    }
}

// MARK: - 返程（V2 预留，第一版不启用 UI）
// 第一版去程计划详情页不展示返程；以下返程相关类型与 RoundTripPlan 的返程接口为后续恢复
// 返程能力保留，当前 UI 不读取，避免误用为已启用功能。详见 CONTEXT.md「返程」「未定返程」。
enum ReturnPlanState: String, CaseIterable, Codable, Equatable {
    case undecided
    case planned
}

enum DepartureTransportMode: String, CaseIterable, Codable, Equatable, Hashable {
    case publicTransit
    case driving
    case taxiReference

    var displayName: String {
        switch self {
        case .publicTransit: return "公共交通"
        case .driving: return "驾车"
        case .taxiReference: return "打车参考"
        }
    }

    var iconName: String {
        switch self {
        case .publicTransit: return "tram.fill"
        case .driving: return "car.fill"
        case .taxiReference: return "car.side.fill"
        }
    }
}

enum DepartureRouteProviderID: String, Codable, Equatable {
    case appleMaps
    case manual
}

enum DepartureRouteProviderError: Error, Equatable {
    case missingOrigin
    case missingDestination
    case geocodingFailed
    case noOptions
    case providerUnavailable
}

struct DepartureRouteRequest: Equatable {
    let show: Show
    let origin: String
    let destination: String
    let meetingPoint: String?
    let targetArrivalAt: Date
    let preferredModes: [DepartureTransportMode]
    let notes: String?

    var hasRequiredPlaces: Bool {
        !origin.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !destination.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

struct DepartureTransportOption: Identifiable, Equatable {
    let id: String
    let mode: DepartureTransportMode
    let leaveAt: Date
    let arriveAt: Date
    let durationMinutes: Int
    let distanceMeters: Int?
    let summary: String
    let experienceTag: String
    let provider: DepartureRouteProviderID
    let navigationURL: URL?
    let capturedAt: Date
}

extension DepartureTransportOption {
    var distanceText: String? {
        guard let distanceMeters else { return nil }
        if distanceMeters >= 1000 {
            return String(format: "%.1f km", Double(distanceMeters) / 1000.0)
        }
        return "\(distanceMeters) m"
    }

    var durationText: String {
        "\(durationMinutes) 分钟"
    }
}

@MainActor
protocol DepartureRouteProviding: Sendable {
    func searchOptions(for request: DepartureRouteRequest) async throws -> [DepartureTransportOption]
    func openNavigation(for option: DepartureTransportOption)
}

struct MapKitDepartureRouteProvider: DepartureRouteProviding {
    func searchOptions(for request: DepartureRouteRequest) async throws -> [DepartureTransportOption] {
        guard !request.origin.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DepartureRouteProviderError.missingOrigin
        }
        guard !request.destination.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DepartureRouteProviderError.missingDestination
        }

        let capturedAt = Date()
        let requestedModes = request.preferredModes.isEmpty
            ? [.publicTransit, .taxiReference, .driving]
            : request.preferredModes
        let originItem = try await mapItem(for: request.origin, city: request.show.city)
        let destinationItem = try await mapItem(for: request.destination, city: request.show.city)

        var options: [DepartureTransportOption] = []
        for mode in requestedModes {
            switch mode {
            case .publicTransit:
                if let option = try await routeOption(
                    mode: .publicTransit,
                    request: request,
                    origin: originItem,
                    destination: destinationItem,
                    transportType: .transit,
                    capturedAt: capturedAt
                ) {
                    options.append(option)
                }
            case .driving:
                if let option = try await routeOption(
                    mode: .driving,
                    request: request,
                    origin: originItem,
                    destination: destinationItem,
                    transportType: .automobile,
                    capturedAt: capturedAt
                ) {
                    options.append(option)
                }
            case .taxiReference:
                if let option = try await routeOption(
                    mode: .taxiReference,
                    request: request,
                    origin: originItem,
                    destination: destinationItem,
                    transportType: .automobile,
                    capturedAt: capturedAt
                ) {
                    options.append(option)
                }
            }
        }

        guard !options.isEmpty else {
            throw DepartureRouteProviderError.noOptions
        }

        return options.sorted { first, second in
            Self.modePriority(first.mode) < Self.modePriority(second.mode)
        }
    }

    func openNavigation(for option: DepartureTransportOption) {
        guard let navigationURL = option.navigationURL else { return }
        UIApplication.shared.open(navigationURL)
    }

    private func mapItem(for query: String, city: String?) async throws -> MKMapItem {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let request = MKLocalSearch.Request()
        if let city = city?.trimmingCharacters(in: .whitespacesAndNewlines),
           !city.isEmpty,
           !trimmed.contains(city) {
            request.naturalLanguageQuery = "\(city) \(trimmed)"
        } else {
            request.naturalLanguageQuery = trimmed
        }
        request.resultTypes = [.address, .pointOfInterest]

        let response = try await MKLocalSearch(request: request).start()
        guard let item = response.mapItems.first else {
            throw DepartureRouteProviderError.geocodingFailed
        }
        return item
    }

    private func routeOption(
        mode: DepartureTransportMode,
        request: DepartureRouteRequest,
        origin: MKMapItem,
        destination: MKMapItem,
        transportType: MKDirectionsTransportType,
        capturedAt: Date
    ) async throws -> DepartureTransportOption? {
        let directionsRequest = MKDirections.Request()
        directionsRequest.source = origin
        directionsRequest.destination = destination
        directionsRequest.transportType = transportType

        let route = try await calculateRoute(for: directionsRequest)
        let durationMinutes = max(1, Int((route.expectedTravelTime / 60.0).rounded(.up)))
        let arriveAt = request.targetArrivalAt
        let leaveAt = Calendar.current.date(byAdding: .minute, value: -durationMinutes, to: arriveAt) ?? arriveAt
        let distanceMeters = Int(route.distance.rounded())
        let summary = Self.summary(
            mode: mode,
            stepInstructions: route.stepInstructions,
            destination: request.destination,
            durationMinutes: durationMinutes
        )
        let tag = Self.experienceTag(for: mode)

        return DepartureTransportOption(
            id: "\(mode.rawValue)-\(Int(capturedAt.timeIntervalSince1970))",
            mode: mode,
            leaveAt: leaveAt,
            arriveAt: arriveAt,
            durationMinutes: durationMinutes,
            distanceMeters: distanceMeters,
            summary: summary,
            experienceTag: tag,
            provider: .appleMaps,
            navigationURL: Self.appleMapsDirectionsURL(
                origin: origin,
                destination: destination,
                mode: mode
            ),
            capturedAt: capturedAt
        )
    }

    private struct ResolvedRoute: Sendable {
        let expectedTravelTime: TimeInterval
        let distance: CLLocationDistance
        let stepInstructions: [String]
    }

    private func calculateRoute(for request: MKDirections.Request) async throws -> ResolvedRoute {
        let directions = MKDirections(request: request)
        return try await withCheckedThrowingContinuation { continuation in
            directions.calculate { response, error in
                if let route = response?.routes.first {
                    continuation.resume(returning: ResolvedRoute(
                        expectedTravelTime: route.expectedTravelTime,
                        distance: route.distance,
                        stepInstructions: route.steps.map(\.instructions)
                    ))
                } else if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(throwing: DepartureRouteProviderError.noOptions)
                }
            }
        }
    }

    nonisolated static func summary(
        mode: DepartureTransportMode,
        stepInstructions: [String],
        destination: String,
        durationMinutes: Int
    ) -> String {
        switch mode {
        case .publicTransit:
            let steps = stepInstructions
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .prefix(2)
            if !steps.isEmpty {
                return "\(steps.joined(separator: " → ")) 到 \(destination)，出发前再打开地图确认实时班次。"
            }
            return "公共交通到 \(destination)，出发前再打开地图确认实时班次。"
        case .taxiReference:
            return "按地图驾车路线估算打车耗时，出发前仍需确认叫车等待和实时路况。"
        case .driving:
            return "地图驾车路线约 \(durationMinutes) 分钟，到场前建议再确认停车和拥堵。"
        }
    }

    nonisolated static func experienceTag(for mode: DepartureTransportMode) -> String {
        switch mode {
        case .publicTransit: return "比较稳"
        case .taxiReference: return "适合赶时间"
        case .driving: return "需确认停车"
        }
    }

    nonisolated static func modePriority(_ mode: DepartureTransportMode) -> Int {
        switch mode {
        case .publicTransit: return 0
        case .taxiReference: return 1
        case .driving: return 2
        }
    }

    nonisolated static func appleMapsDirectionsURL(
        origin: MKMapItem,
        destination: MKMapItem,
        mode: DepartureTransportMode
    ) -> URL? {
        var components = URLComponents(string: "https://maps.apple.com/")
        var queryItems = [
            URLQueryItem(
                name: "saddr",
                value: coordinateText(origin.placemark.coordinate)
            ),
            URLQueryItem(
                name: "daddr",
                value: coordinateText(destination.placemark.coordinate)
            ),
            URLQueryItem(name: "dirflg", value: directionsModeValue(mode))
        ]
        components?.queryItems = queryItems
        return components?.url
    }

    nonisolated static func estimatedOption(
        mode: DepartureTransportMode,
        request: DepartureRouteRequest,
        capturedAt: Date
    ) -> DepartureTransportOption {
        let duration: Int
        let distance: Int?
        let summary: String
        let tag = experienceTag(for: mode)

        switch mode {
        case .publicTransit:
            duration = 46
            distance = nil
            summary = "公共交通到 \(request.destination)，出发前再打开地图确认实时班次。"
        case .taxiReference:
            duration = 34
            distance = 12_400
            summary = "按驾车路线估算打车耗时，适合赶时间时参考。"
        case .driving:
            duration = 38
            distance = 12_400
            summary = "驾车前往 \(request.destination)，停车和散场拥堵建议提前确认。"
        }

        let arriveAt = request.targetArrivalAt
        let leaveAt = Calendar.current.date(byAdding: .minute, value: -duration, to: arriveAt) ?? arriveAt

        return DepartureTransportOption(
            id: "\(mode.rawValue)-\(Int(capturedAt.timeIntervalSince1970))",
            mode: mode,
            leaveAt: leaveAt,
            arriveAt: arriveAt,
            durationMinutes: duration,
            distanceMeters: distance,
            summary: summary,
            experienceTag: tag,
            provider: .appleMaps,
            navigationURL: nil,
            capturedAt: capturedAt
        )
    }

    nonisolated private static func coordinateText(_ coordinate: CLLocationCoordinate2D) -> String {
        "\(coordinate.latitude),\(coordinate.longitude)"
    }

    nonisolated private static func directionsModeValue(_ mode: DepartureTransportMode) -> String {
        switch mode {
        case .publicTransit: return "r"
        case .driving, .taxiReference: return "d"
        }
    }
}

struct EstimatedDepartureRouteProvider: DepartureRouteProviding {
    func searchOptions(for request: DepartureRouteRequest) async throws -> [DepartureTransportOption] {
        guard request.hasRequiredPlaces else {
            throw request.origin.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? DepartureRouteProviderError.missingOrigin
                : DepartureRouteProviderError.missingDestination
        }
        let capturedAt = Date()
        let modes = request.preferredModes.isEmpty ? DepartureTransportMode.allCases : request.preferredModes
        return modes.map {
            MapKitDepartureRouteProvider.estimatedOption(
                mode: $0,
                request: request,
                capturedAt: capturedAt
            )
        }
    }

    func openNavigation(for option: DepartureTransportOption) {
        guard let navigationURL = option.navigationURL else { return }
        UIApplication.shared.open(navigationURL)
    }
}

enum RoundTripDraftError: Error, Equatable {
    case insufficientDirectionInformation
    case missingReliableEvidence
    case invalidGenerationPayload
    case networkFailure
    case backendRejected(String)
}

struct RoundTripEvidence: Codable, Equatable {
    let title: String
    let url: URL?

    init(title: String, url: URL? = nil) {
        self.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        self.url = url
    }
}

struct RoundTripDraftStep: Codable, Equatable {
    let title: String
    let detail: String
}

struct RoundTripDraft: Equatable {
    let direction: RoundTripDirection
    let summary: String
    let steps: [RoundTripDraftStep]
    let evidence: [RoundTripEvidence]
}

extension RoundTripDraft: Decodable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case type
        case direction
        case summary
        case steps
        case evidence
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try StrictGenerationDecoding.rejectExtraKeys(
            in: decoder,
            allowed: Set(CodingKeys.allCases.map(\.stringValue))
        )

        let type = try container.decode(String.self, forKey: .type)
        guard type == "roundTripDraft" else {
            throw RoundTripDraftError.invalidGenerationPayload
        }

        let direction = try container.decode(RoundTripDirection.self, forKey: .direction)
        let summary = try container.decode(String.self, forKey: .summary)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let steps = try container.decode([RoundTripDraftStep].self, forKey: .steps)
        let evidence = try container.decode([RoundTripEvidence].self, forKey: .evidence)

        guard !summary.isEmpty, !steps.isEmpty, !evidence.isEmpty else {
            throw RoundTripDraftError.invalidGenerationPayload
        }

        self.init(direction: direction, summary: summary, steps: steps, evidence: evidence)
    }
}

extension RoundTripDraft {
    var editableText: String {
        let stepText = steps.map { "\($0.title)：\($0.detail)" }.joined(separator: "\n")
        let evidenceText = evidence.map { item in
            if let url = item.url {
                return "依据：\(item.title) \(url.absoluteString)"
            }
            return "依据：\(item.title)"
        }.joined(separator: "\n")

        return [summary, stepText, evidenceText]
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: "\n\n")
    }
}

struct RoundTripDraftRequest: Equatable {
    let show: Show
    let direction: RoundTripDirection
    let origin: String?
    let destination: String?
    let hotel: String?
    let meetingPoint: String?
    let notes: String?

    var hasEnoughDirectionInformation: Bool {
        switch direction {
        case .outbound:
            return hasText(origin) || hasText(meetingPoint)
        case .return:
            return hasText(destination) || hasText(hotel) || hasText(meetingPoint) || hasText(notes)
        }
    }

    private func hasText(_ value: String?) -> Bool {
        guard let value else { return false }
        return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

struct RoundTripDraftBuilder {
    func makeDraft(
        for request: RoundTripDraftRequest,
        evidence: [RoundTripEvidence],
        proposedSummary: String,
        proposedSteps: [RoundTripDraftStep]
    ) throws -> RoundTripDraft {
        guard request.hasEnoughDirectionInformation else {
            throw RoundTripDraftError.insufficientDirectionInformation
        }

        let reliableEvidence = evidence.filter { !$0.title.isEmpty }
        guard !reliableEvidence.isEmpty else {
            throw RoundTripDraftError.missingReliableEvidence
        }

        return RoundTripDraft(
            direction: request.direction,
            summary: proposedSummary.trimmingCharacters(in: .whitespacesAndNewlines),
            steps: proposedSteps,
            evidence: reliableEvidence
        )
    }
}

@Model
final class RoundTripPlan {
    var id: UUID
    var showID: UUID
    var outboundContent: String?
    var returnContent: String?
    var returnNote: String?
    var createdAt: Date
    var updatedAt: Date

    private var returnStateRawValue: String
    private var savedDepartureModeRawValue: String?
    private var savedDepartureProviderRawValue: String?
    private var savedDepartureNavigationURLString: String?

    var departureOrigin: String?
    var departureDestination: String?
    var departureMeetingPoint: String?
    var departureLeaveAt: Date?
    var departureArriveAt: Date?
    var departureDurationMinutes: Int?
    var departureDistanceMeters: Int?
    var departureSummary: String?
    var departureExperienceTag: String?
    var departureCapturedAt: Date?

    var returnState: ReturnPlanState {
        get { ReturnPlanState(rawValue: returnStateRawValue) ?? .undecided }
        set {
            returnStateRawValue = newValue.rawValue
            touch()
        }
    }

    var savedDepartureMode: DepartureTransportMode? {
        get {
            guard let savedDepartureModeRawValue else { return nil }
            return DepartureTransportMode(rawValue: savedDepartureModeRawValue)
        }
        set {
            savedDepartureModeRawValue = newValue?.rawValue
            touch()
        }
    }

    var savedDepartureProvider: DepartureRouteProviderID? {
        get {
            guard let savedDepartureProviderRawValue else { return nil }
            if savedDepartureProviderRawValue == "amap" {
                return .appleMaps
            }
            return DepartureRouteProviderID(rawValue: savedDepartureProviderRawValue)
        }
        set {
            savedDepartureProviderRawValue = newValue?.rawValue
            touch()
        }
    }

    var savedDepartureNavigationURL: URL? {
        get {
            guard let savedDepartureNavigationURLString else { return nil }
            return URL(string: savedDepartureNavigationURLString)
        }
        set {
            savedDepartureNavigationURLString = newValue?.absoluteString
            touch()
        }
    }

    /// Structured 已保存出门方案 (leave/arrive/mode/summary). Used by 出行小助手 and 去程计划 UI.
    var hasSavedDeparturePlan: Bool {
        savedDepartureMode != nil
            && departureLeaveAt != nil
            && departureArriveAt != nil
            && trimmedOptional(departureSummary) != nil
    }

    /// Single predicate for Tips + tool-status “已有去程”.
    ///
    /// Includes structured 出门方案 **or** legacy free-text `outboundContent` (old 往返草稿 path).
    /// Deletion test: without this, callers re-OR those two meanings and drift.
    /// Does **not** replace `hasSavedDeparturePlan` for map / 出行小助手.
    var hasOutboundPlan: Bool {
        hasSavedDeparturePlan || trimmedOptional(outboundContent) != nil
    }

    init(
        id: UUID = UUID(),
        showID: UUID,
        outboundContent: String? = nil,
        returnContent: String? = nil,
        returnState: ReturnPlanState = .undecided,
        returnNote: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.showID = showID
        self.outboundContent = trimmedOptional(outboundContent)
        self.returnContent = trimmedOptional(returnContent)
        self.returnStateRawValue = returnState.rawValue
        self.returnNote = trimmedOptional(returnNote)
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.savedDepartureModeRawValue = nil
        self.savedDepartureProviderRawValue = nil
        self.savedDepartureNavigationURLString = nil
    }

    func saveOutbound(_ content: String) {
        outboundContent = trimmedOptional(content)
        touch()
    }

    func saveDeparture(option: DepartureTransportOption, origin: String, destination: String, meetingPoint: String?) {
        departureOrigin = trimmedOptional(origin)
        departureDestination = trimmedOptional(destination)
        departureMeetingPoint = trimmedOptional(meetingPoint)
        departureLeaveAt = option.leaveAt
        departureArriveAt = option.arriveAt
        departureDurationMinutes = option.durationMinutes
        departureDistanceMeters = option.distanceMeters
        departureSummary = trimmedOptional(option.summary)
        departureExperienceTag = trimmedOptional(option.experienceTag)
        departureCapturedAt = option.capturedAt
        savedDepartureModeRawValue = option.mode.rawValue
        savedDepartureProviderRawValue = option.provider.rawValue
        savedDepartureNavigationURLString = option.navigationURL?.absoluteString
        outboundContent = option.summary
        touch()
    }

    func saveManualDeparture(
        origin: String,
        destination: String,
        leaveAt: Date,
        arriveAt: Date,
        mode: DepartureTransportMode,
        summary: String,
        meetingPoint: String? = nil
    ) {
        let minutes = max(1, Calendar.current.dateComponents([.minute], from: leaveAt, to: arriveAt).minute ?? 1)
        let option = DepartureTransportOption(
            id: "manual-\(id.uuidString)",
            mode: mode,
            leaveAt: leaveAt,
            arriveAt: arriveAt,
            durationMinutes: minutes,
            distanceMeters: nil,
            summary: summary,
            experienceTag: "手动保存",
            provider: .manual,
            navigationURL: nil,
            capturedAt: Date()
        )
        saveDeparture(option: option, origin: origin, destination: destination, meetingPoint: meetingPoint)
    }

    // MARK: 返程（V2 预留，当前 UI 不启用）
    func saveReturn(_ content: String) {
        returnContent = trimmedOptional(content)
        returnState = .planned
        touch()
    }

    // MARK: 返程（V2 预留，当前 UI 不启用）
    func markReturnUndecided(note: String? = nil) {
        returnContent = nil
        returnNote = trimmedOptional(note)
        returnState = .undecided
        touch()
    }

    func applySavedUserEdit(_ content: String, direction: RoundTripDirection) {
        switch direction {
        case .outbound:
            saveOutbound(content)
        case .return:
            saveReturn(content)
        }
    }

    private func touch() {
        updatedAt = Date()
    }
}

// MARK: - 常用出发地
// 用户首次填入或定位获取的出发地，跨所有现场自动复用，让新增现场基本零输入。
// 全局单条：最新一条即当前常用出发地。每场现场仍可在 RoundTripPlan.departureOrigin
// 临时覆盖；保存方案时会回写更新常用出发地。未来可扩展为多条（家/公司）。
@Model
final class SavedOrigin {
    var id: UUID
    var name: String
    var addressText: String
    var latitude: Double?
    var longitude: Double?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        addressText: String,
        latitude: Double? = nil,
        longitude: Double? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.addressText = addressText.trimmingCharacters(in: .whitespacesAndNewlines)
        self.latitude = latitude
        self.longitude = longitude
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - Round-trip AI draft (domain kept; remote client removed)
// Product UI for 去程计划 uses MapKit 出门方案 only. RoundTripDraft* types + Builder
// remain for decode/validation tests and backend contract readiness. There was no
// production call site for RemoteRoundTripDraftGenerationService (false depth).

private func trimmedOptional(_ value: String?) -> String? {
    guard let value else { return nil }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}

private enum StrictGenerationDecoding {
    struct AnyCodingKey: CodingKey {
        let stringValue: String
        let intValue: Int? = nil

        init?(stringValue: String) {
            self.stringValue = stringValue
        }

        init?(intValue: Int) {
            return nil
        }
    }

    static func rejectExtraKeys(in decoder: Decoder, allowed: Set<String>) throws {
        let container = try decoder.container(keyedBy: AnyCodingKey.self)
        let unknownKeys = container.allKeys
            .map(\.stringValue)
            .filter { !allowed.contains($0) }

        if !unknownKeys.isEmpty {
            throw RoundTripDraftError.invalidGenerationPayload
        }
    }
}

// MARK: - 常用出发地定位
// 用一次性定位 + 反查地址，帮用户把「出发地」一键填好，免去手输。
// 仅在用户点击「使用当前位置」时请求，不持续追踪。
@MainActor
final class OriginLocator: NSObject, ObservableObject {
    enum LocatorError: LocalizedError, Equatable {
        case authorizationDenied
        case locationUnavailable
        case reverseGeocodingFailed

        var errorDescription: String? {
            switch self {
            case .authorizationDenied: return "没有定位权限，可以在设置里开启后重试。"
            case .locationUnavailable: return "暂时拿不到当前位置，请检查信号后重试。"
            case .reverseGeocodingFailed: return "拿到了位置，但没能转成地址，可以手动填出发地。"
            }
        }
    }

    @Published private(set) var isLocating = false

    private let manager = CLLocationManager()
    private let geocoder = CLGeocoder()
    private var locationContinuation: CheckedContinuation<CLLocation, Error>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func requestCurrentOrigin() async throws -> ResolvedOrigin {
        isLocating = true
        defer { isLocating = false }

        if manager.authorizationStatus == .denied || manager.authorizationStatus == .restricted {
            throw LocatorError.authorizationDenied
        }

        let location = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<CLLocation, Error>) in
            self.locationContinuation = continuation
            if self.manager.authorizationStatus == .notDetermined {
                self.manager.requestWhenInUseAuthorization()
            } else {
                self.manager.requestLocation()
            }
        }

        let placemark = try await reverseGeocode(location)
        return ResolvedOrigin(
            name: placemark.name ?? placemark.locality ?? "当前位置",
            addressText: OriginLocator.composeAddress(from: placemark),
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude
        )
    }

    private func reverseGeocode(_ location: CLLocation) async throws -> CLPlacemark {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<CLPlacemark, Error>) in
            geocoder.reverseGeocodeLocation(location) { placemarks, error in
                if let placemark = placemarks?.first {
                    continuation.resume(returning: placemark)
                } else {
                    continuation.resume(throwing: error ?? LocatorError.reverseGeocodingFailed)
                }
            }
        }
    }

    nonisolated static func composeAddress(from placemark: CLPlacemark) -> String {
        let parts = [placemark.locality, placemark.subLocality, placemark.thoroughfare, placemark.subThoroughfare]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if parts.isEmpty {
            return placemark.name ?? "当前位置"
        }
        return parts.joined()
    }
}

extension OriginLocator: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            guard locationContinuation != nil else { return }
            switch self.manager.authorizationStatus {
            case .authorizedWhenInUse, .authorizedAlways:
                self.manager.requestLocation()
            case .denied, .restricted:
                locationContinuation?.resume(throwing: LocatorError.authorizationDenied)
                locationContinuation = nil
            default:
                break
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in
            locationContinuation?.resume(returning: location)
            locationContinuation = nil
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let locatorError: LocatorError = (error as? CLError)?.code == .denied
            ? .authorizationDenied
            : .locationUnavailable
        Task { @MainActor in
            locationContinuation?.resume(throwing: locatorError)
            locationContinuation = nil
        }
    }
}

struct ResolvedOrigin: Equatable {
    let name: String
    let addressText: String
    let latitude: Double
    let longitude: Double
}
