import CoreLocation
import Foundation
import MapKit
import SwiftData
import UIKit

enum RoundTripDirection: String, CaseIterable, Codable, Equatable {
    case outbound
    case `return`

    var displayName: String { self == .outbound ? "去程" : "返程" }

    func routeTiming(at targetTime: Date) -> TravelRouteTiming {
        self == .outbound ? .arriveAt(targetTime) : .departAt(targetTime)
    }
}

enum TravelRouteTiming: Equatable, Sendable {
    case departAt(Date)
    case arriveAt(Date)
}

enum TravelMode: String, CaseIterable, Codable, Equatable, Hashable {
    case driving
    case walking
    case transit
    case cycling
    case custom

    var displayName: String {
        switch self {
        case .driving: return "驾车"
        case .walking: return "步行"
        case .transit: return "公共交通"
        case .cycling: return "骑行"
        case .custom: return "自定义"
        }
    }

    var iconName: String {
        switch self {
        case .driving: return "car.fill"
        case .walking: return "figure.walk"
        case .transit: return "tram.fill"
        case .cycling: return "bicycle"
        case .custom: return "slider.horizontal.3"
        }
    }

    var mapKitTransportType: MKDirectionsTransportType? {
        switch self {
        case .driving: return .automobile
        case .walking: return .walking
        case .transit: return .transit
        case .cycling: return .cycling
        case .custom: return nil
        }
    }

    var mapKitCalculation: MapKitRouteCalculation? {
        switch self {
        case .transit: return .estimatedTime
        case .driving, .walking, .cycling: return .route
        case .custom: return nil
        }
    }

    var appleMapsDirectionFlag: String? {
        switch self {
        case .driving: return "d"
        case .walking: return "w"
        case .transit: return "r"
        case .cycling: return "b"
        case .custom: return nil
        }
    }
}

enum MapKitRouteCalculation: Equatable {
    case route
    case estimatedTime
}

struct TravelPlace: Codable, Equatable, Hashable {
    let name: String
    let address: String
    let latitude: Double
    let longitude: Double

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

enum TravelTimelineNodeKind: String, Codable, Equatable {
    case origin
    case travel
    case transfer
    case destination
}

struct TravelTimelineNode: Identifiable, Codable, Equatable {
    var id: UUID
    let kind: TravelTimelineNodeKind
    let title: String
    let detail: String?
    let date: Date?

    init(
        id: UUID = UUID(),
        kind: TravelTimelineNodeKind,
        title: String,
        detail: String? = nil,
        date: Date? = nil
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.detail = detail
        self.date = date
    }
}

enum TravelPlanValidity: String, Codable, Equatable {
    case valid
    case needsRegeneration
}

struct TravelPlan: Codable, Equatable {
    let id: UUID
    let direction: RoundTripDirection
    let mode: TravelMode
    let origin: TravelPlace
    let destination: TravelPlace
    let leaveAt: Date
    let arriveAt: Date
    let durationMinutes: Int
    let distanceMeters: Int?
    let summary: String
    let timeline: [TravelTimelineNode]
    let showFingerprint: String
    let capturedAt: Date
    var validity: TravelPlanValidity

    init(
        id: UUID = UUID(),
        direction: RoundTripDirection,
        mode: TravelMode,
        origin: TravelPlace,
        destination: TravelPlace,
        leaveAt: Date,
        arriveAt: Date,
        durationMinutes: Int,
        distanceMeters: Int?,
        summary: String,
        timeline: [TravelTimelineNode],
        showFingerprint: String,
        capturedAt: Date = Date(),
        validity: TravelPlanValidity = .valid
    ) {
        self.id = id
        self.direction = direction
        self.mode = mode
        self.origin = origin
        self.destination = destination
        self.leaveAt = leaveAt
        self.arriveAt = arriveAt
        self.durationMinutes = durationMinutes
        self.distanceMeters = distanceMeters
        self.summary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        self.timeline = Array(timeline.prefix(6))
        self.showFingerprint = showFingerprint
        self.capturedAt = capturedAt
        self.validity = validity
    }

    static func custom(
        direction: RoundTripDirection,
        origin: TravelPlace,
        destination: TravelPlace,
        leaveAt: Date,
        arriveAt: Date,
        summary: String,
        showFingerprint: String,
        capturedAt: Date = Date()
    ) -> TravelPlan {
        TravelPlan(
            direction: direction,
            mode: .custom,
            origin: origin,
            destination: destination,
            leaveAt: leaveAt,
            arriveAt: arriveAt,
            durationMinutes: max(1, Int(arriveAt.timeIntervalSince(leaveAt) / 60)),
            distanceMeters: nil,
            summary: summary,
            timeline: [
                TravelTimelineNode(kind: .origin, title: "从\(origin.name)出发", date: leaveAt),
                TravelTimelineNode(kind: .destination, title: "抵达\(destination.name)", date: arriveAt),
            ],
            showFingerprint: showFingerprint,
            capturedAt: capturedAt
        )
    }

    var navigationURL: URL? {
        guard let flag = mode.appleMapsDirectionFlag else { return nil }
        var components = URLComponents(string: "https://maps.apple.com/")
        components?.queryItems = [
            URLQueryItem(name: "saddr", value: "\(origin.latitude),\(origin.longitude)"),
            URLQueryItem(name: "daddr", value: "\(destination.latitude),\(destination.longitude)"),
            URLQueryItem(name: "dirflg", value: flag),
        ]
        return components?.url
    }
}

@Model
final class RoundTripPlan {
    var id: UUID
    var showID: UUID
    var createdAt: Date
    var updatedAt: Date
    private var outboundPlanData: Data?
    private var returnPlanData: Data?

    var outboundPlan: TravelPlan? {
        get { decode(outboundPlanData) }
        set { outboundPlanData = encode(newValue) }
    }

    var returnPlan: TravelPlan? {
        get { decode(returnPlanData) }
        set { returnPlanData = encode(newValue) }
    }

    init(id: UUID = UUID(), showID: UUID, createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id
        self.showID = showID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.outboundPlanData = nil
        self.returnPlanData = nil
    }

    func plan(for direction: RoundTripDirection) -> TravelPlan? {
        direction == .outbound ? outboundPlan : returnPlan
    }

    func hasPlan(for direction: RoundTripDirection) -> Bool {
        plan(for: direction) != nil
    }

    func hasValidPlan(for direction: RoundTripDirection) -> Bool {
        plan(for: direction)?.validity == .valid
    }

    var hasOutboundPlan: Bool { hasPlan(for: .outbound) }
    var hasReturnPlan: Bool { hasPlan(for: .return) }

    func save(_ plan: TravelPlan) {
        if plan.direction == .outbound {
            outboundPlan = plan
        } else {
            returnPlan = plan
        }
        updatedAt = Date()
    }

    @discardableResult
    func invalidatePlans(ifShowFingerprintChangedTo fingerprint: String) -> Bool {
        var didInvalidate = false
        if var outboundPlan,
           outboundPlan.showFingerprint != fingerprint,
           outboundPlan.validity != .needsRegeneration {
            outboundPlan.validity = .needsRegeneration
            self.outboundPlan = outboundPlan
            didInvalidate = true
        }
        if var returnPlan,
           returnPlan.showFingerprint != fingerprint,
           returnPlan.validity != .needsRegeneration {
            returnPlan.validity = .needsRegeneration
            self.returnPlan = returnPlan
            didInvalidate = true
        }
        if didInvalidate { updatedAt = Date() }
        return didInvalidate
    }

    private func decode(_ data: Data?) -> TravelPlan? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(TravelPlan.self, from: data)
    }

    private func encode(_ plan: TravelPlan?) -> Data? {
        guard let plan else { return nil }
        return try? JSONEncoder().encode(plan)
    }
}

enum TravelRouteError: Error, Equatable {
    case noRoute
    case unsupportedMode
}

struct TravelRouteResult: Equatable, Sendable {
    let durationSeconds: TimeInterval
    let distanceMeters: Int?
    let steps: [String]
}

protocol TravelRouteProviding: Sendable {
    func route(
        from origin: TravelPlace,
        to destination: TravelPlace,
        mode: TravelMode,
        timing: TravelRouteTiming
    ) async throws -> TravelRouteResult
}

struct MapKitTravelRouteProvider: TravelRouteProviding {
    func route(
        from origin: TravelPlace,
        to destination: TravelPlace,
        mode: TravelMode,
        timing: TravelRouteTiming
    ) async throws -> TravelRouteResult {
        guard
            let transportType = mode.mapKitTransportType,
            let calculation = mode.mapKitCalculation
        else {
            throw TravelRouteError.unsupportedMode
        }
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: origin.coordinate))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: destination.coordinate))
        request.transportType = transportType

        if calculation == .estimatedTime {
            switch timing {
            case .departAt(let date): request.departureDate = date
            case .arriveAt(let date): request.arrivalDate = date
            }
        }

        let directions = MKDirections(request: request)
        switch calculation {
        case .route:
            let response = try await directions.calculate()
            guard let route = response.routes.first else { throw TravelRouteError.noRoute }
            return TravelRouteResult(
                durationSeconds: route.expectedTravelTime,
                distanceMeters: Int(route.distance.rounded()),
                steps: route.steps.map(\.instructions).filter { !$0.isEmpty }
            )
        case .estimatedTime:
            let response = try await directions.calculateETA()
            return TravelRouteResult(
                durationSeconds: response.expectedTravelTime,
                distanceMeters: Int(response.distance.rounded()),
                steps: []
            )
        }
    }
}

@MainActor
final class OriginLocator: NSObject, ObservableObject {
    enum LocatorError: LocalizedError, Equatable {
        case authorizationDenied
        case locationUnavailable
        case reverseGeocodingFailed

        var errorDescription: String? {
            switch self {
            case .authorizationDenied: return "没有定位权限，可以在设置里开启后手动选择地点。"
            case .locationUnavailable: return "暂时拿不到当前位置，请手动选择地点。"
            case .reverseGeocodingFailed: return "拿到了位置，但没能识别地址，请手动选择地点。"
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
        let location = try await withCheckedThrowingContinuation { continuation in
            locationContinuation = continuation
            manager.authorizationStatus == .notDetermined
                ? manager.requestWhenInUseAuthorization()
                : manager.requestLocation()
        }
        let placemark = try await reverseGeocode(location)
        return ResolvedOrigin(
            name: placemark.name ?? placemark.locality ?? "我的位置",
            addressText: Self.composeAddress(from: placemark),
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude
        )
    }

    private func reverseGeocode(_ location: CLLocation) async throws -> CLPlacemark {
        try await withCheckedThrowingContinuation { continuation in
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
        return parts.isEmpty ? (placemark.name ?? "我的位置") : parts.joined()
    }
}

extension OriginLocator: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor [weak self] in
            guard let self else { return }
            guard self.locationContinuation != nil else { return }
            switch status {
            case .authorizedAlways, .authorizedWhenInUse:
                self.manager.requestLocation()
            case .denied, .restricted:
                self.locationContinuation?.resume(throwing: LocatorError.authorizationDenied)
                self.locationContinuation = nil
            default:
                break
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor [weak self] in
            self?.locationContinuation?.resume(returning: location)
            self?.locationContinuation = nil
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor [weak self] in
            self?.locationContinuation?.resume(throwing: LocatorError.locationUnavailable)
            self?.locationContinuation = nil
        }
    }
}

struct ResolvedOrigin: Equatable {
    let name: String
    let addressText: String
    let latitude: Double
    let longitude: Double

    var place: TravelPlace {
        TravelPlace(name: name, address: addressText, latitude: latitude, longitude: longitude)
    }
}

enum TravelPlaceSearch {
    static func geocodeAddress(_ address: String, name: String) async -> TravelPlace? {
        do {
            guard let placemark = try await CLGeocoder().geocodeAddressString(address).first,
                  let coordinate = placemark.location?.coordinate else {
                return nil
            }
            return TravelPlace(
                name: name,
                address: address,
                latitude: coordinate.latitude,
                longitude: coordinate.longitude
            )
        } catch {
            return nil
        }
    }

    static func suggestions(matching query: String, regionHint: String? = nil) async -> [TravelPlace] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return [] }

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = regionHint.map { "\($0) \(trimmed)" } ?? trimmed
        request.resultTypes = [.address, .pointOfInterest]

        do {
            let response = try await MKLocalSearch(request: request).start()
            return response.mapItems.compactMap { item in
                guard let coordinate = item.placemark.location?.coordinate else { return nil }
                let name = item.name
                    ?? item.placemark.name
                    ?? trimmed
                let address = [
                    item.placemark.locality,
                    item.placemark.subLocality,
                    item.placemark.thoroughfare,
                    item.placemark.subThoroughfare,
                ]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: "")
                return TravelPlace(
                    name: name,
                    address: address.isEmpty ? name : address,
                    latitude: coordinate.latitude,
                    longitude: coordinate.longitude
                )
            }
        } catch {
            return []
        }
    }

    static func resolve(text: String, regionHint: String? = nil) async -> TravelPlace? {
        await suggestions(matching: text, regionHint: regionHint).first
    }
}
