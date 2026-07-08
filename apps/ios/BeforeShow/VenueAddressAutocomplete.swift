import CoreLocation
import MapKit
import SwiftUI

struct AddressSuggestion: Identifiable, Equatable {
    let id: String
    let name: String
    let address: String
    let district: String

    var subtitle: String {
        let parts = [district, address]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return parts.joined(separator: " · ")
    }

    var fillText: String {
        MapKitAddressFormatter.displayAddress(
            name: name,
            address: address,
            district: district
        )
    }
}

enum AddressSuggestionError: Error, Equatable {
    case providerUnavailable
}

@MainActor
protocol AddressSuggestionProviding: Sendable {
    func suggestions(for query: String, city: String?) async throws -> [AddressSuggestion]
}

enum MapKitAddressFormatter {
    static func displayAddress(name: String, address: String, district: String) -> String {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAddress = address.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDistrict = district.trimmingCharacters(in: .whitespacesAndNewlines)

        if !trimmedAddress.isEmpty {
            if trimmedAddress.contains("市") || trimmedAddress.contains("区") || trimmedAddress.contains("县") {
                return trimmedAddress
            }
            if !trimmedDistrict.isEmpty {
                return "\(trimmedDistrict)\(trimmedAddress)"
            }
            if !trimmedName.isEmpty, !trimmedAddress.contains(trimmedName) {
                return "\(trimmedName) \(trimmedAddress)"
            }
            return trimmedAddress
        }

        if !trimmedDistrict.isEmpty {
            return trimmedName.isEmpty ? trimmedDistrict : "\(trimmedName) \(trimmedDistrict)"
        }

        return trimmedName
    }

    static func displayAddress(for mapItem: MKMapItem) -> String {
        let placemark = mapItem.placemark
        let name = mapItem.name ?? placemark.name ?? ""
        let district = [placemark.administrativeArea, placemark.locality, placemark.subLocality]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined()
        let street = [placemark.thoroughfare, placemark.subThoroughfare]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined()
        return displayAddress(name: name, address: street, district: district)
    }
}

struct MapKitAddressSuggestionProvider: AddressSuggestionProviding {
    func suggestions(for query: String, city: String?) async throws -> [AddressSuggestion] {
        let keywords = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard keywords.count >= 2 else { return [] }

        let request = MKLocalSearch.Request()
        if let city = city?.trimmingCharacters(in: .whitespacesAndNewlines),
           !city.isEmpty,
           !keywords.contains(city) {
            request.naturalLanguageQuery = "\(city) \(keywords)"
        } else {
            request.naturalLanguageQuery = keywords
        }
        request.resultTypes = [.address, .pointOfInterest]

        let response = try await MKLocalSearch(request: request).start()
        var seen = Set<String>()
        return response.mapItems
            .compactMap(AddressSuggestion.init(mapItem:))
            .filter { suggestion in
                guard suggestion.fillText.count >= 2 else { return false }
                return seen.insert(suggestion.fillText).inserted
            }
            .prefix(6)
            .map { $0 }
    }
}

private extension AddressSuggestion {
    init?(mapItem: MKMapItem) {
        let placemark = mapItem.placemark
        let name = (mapItem.name ?? placemark.name ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let district = [placemark.administrativeArea, placemark.locality, placemark.subLocality]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined()
        let street = [placemark.thoroughfare, placemark.subThoroughfare]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined()

        guard !name.isEmpty || !district.isEmpty || !street.isEmpty else {
            return nil
        }

        let identifier = [
            name,
            district,
            street,
            "\(placemark.coordinate.latitude)",
            "\(placemark.coordinate.longitude)"
        ].joined(separator: "|")

        self.init(
            id: identifier,
            name: name.isEmpty ? district : name,
            address: street,
            district: district
        )
    }
}

struct BSAddressSuggestionField: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    var city: String = ""
    var seedKeyword: String = ""
    var helperText: String?
    var provider: any AddressSuggestionProviding = MapKitAddressSuggestionProvider()

    @State private var suggestions: [AddressSuggestion] = []
    @State private var isSearching = false
    @State private var searchMessage: String?
    @State private var searchTask: Task<Void, Never>?
    @State private var mapPinCoordinate: CLLocationCoordinate2D?
    @FocusState private var isFocused: Bool

    private var trimmedSeedKeyword: String {
        seedKeyword.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedCity: String {
        city.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canLookupBySeed: Bool {
        !trimmedSeedKeyword.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(BSFont.caption)
                .foregroundColor(BSColor.textTertiary)

            TextField(placeholder, text: $text, axis: .vertical)
                .lineLimit(1...3)
                .textInputAutocapitalization(.never)
                .bsInputField()
                .focused($isFocused)
                .accessibilityLabel(label)
                .onChange(of: text) { _, newValue in
                    scheduleSearch(for: newValue)
                }
                .onChange(of: isFocused) { _, focused in
                    if focused {
                        maybePrefetchSeedSuggestions()
                    } else {
                        searchTask?.cancel()
                    }
                }

            BSInlineAddressMap(
                city: trimmedCity,
                seedKeyword: trimmedSeedKeyword,
                pinCoordinate: $mapPinCoordinate,
                addressText: text
            ) { picked in
                text = picked
                suggestions = []
                searchMessage = nil
                isFocused = false
            }

            if canLookupBySeed, text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Button {
                    Task { await lookupSeedSuggestions() }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 12, weight: .semibold))
                        Text(seedLookupTitle)
                            .font(BSFont.caption)
                    }
                    .foregroundColor(BSColor.Accent.travel)
                }
                .buttonStyle(.plain)
            }

            if let helperText, !helperText.isEmpty {
                Text(helperText)
                    .font(BSFont.caption)
                    .foregroundColor(BSColor.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if isSearching {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("正在用地图查找地址…")
                        .font(BSFont.caption)
                        .foregroundColor(BSColor.textTertiary)
                }
            } else if let searchMessage {
                Text(searchMessage)
                    .font(BSFont.caption)
                    .foregroundColor(BSColor.textTertiary)
            }

            if !suggestions.isEmpty {
                VStack(spacing: 0) {
                    ForEach(suggestions) { suggestion in
                        Button {
                            applySuggestion(suggestion)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(suggestion.name)
                                    .font(BSFont.body)
                                    .foregroundColor(BSColor.textPrimary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                if !suggestion.subtitle.isEmpty {
                                    Text(suggestion.subtitle)
                                        .font(BSFont.caption)
                                        .foregroundColor(BSColor.textTertiary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                            .padding(.horizontal, BSSpacing.sm)
                            .padding(.vertical, 10)
                        }
                        .buttonStyle(.plain)

                        if suggestion.id != suggestions.last?.id {
                            Divider()
                                .overlay(BSColor.border)
                        }
                    }
                }
                .background(Color.white.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: BSRadius.md))
                .overlay(
                    RoundedRectangle(cornerRadius: BSRadius.md)
                        .stroke(BSColor.borderProminent, lineWidth: 1)
                )
            }
        }
    }

    private var seedLookupTitle: String {
        if trimmedCity.isEmpty {
            return "按场馆名查找"
        }
        return "在\(trimmedCity)按场馆名查找"
    }

    private func maybePrefetchSeedSuggestions() {
        guard text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              canLookupBySeed,
              suggestions.isEmpty,
              !isSearching else {
            return
        }
        Task { await lookupSeedSuggestions() }
    }

    private func lookupSeedSuggestions() async {
        await performSearch(query: trimmedSeedKeyword)
    }

    private func scheduleSearch(for query: String) {
        searchTask?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else {
            suggestions = []
            searchMessage = nil
            isSearching = false
            return
        }

        searchTask = Task {
            try? await Task.sleep(nanoseconds: 320_000_000)
            guard !Task.isCancelled else { return }
            await performSearch(query: trimmed)
        }
    }

    @MainActor
    private func performSearch(query: String) async {
        isSearching = true
        defer { isSearching = false }

        do {
            suggestions = try await provider.suggestions(
                for: query,
                city: trimmedCity.isEmpty ? nil : trimmedCity
            )
            searchMessage = suggestions.isEmpty ? "没找到匹配地址，可以点下面小地图选位置。" : nil
        } catch {
            suggestions = []
            searchMessage = "暂时没查到地址，请稍后再试或点下面小地图选位置。"
        }
    }

    private func applySuggestion(_ suggestion: AddressSuggestion) {
        text = suggestion.fillText
        suggestions = []
        searchMessage = nil
        isFocused = false
        Task { await syncMapPin(for: suggestion.fillText) }
    }

    @MainActor
    private func syncMapPin(for address: String) async {
        guard let coordinate = await MapLocationResolver.coordinate(for: address, city: trimmedCity) else {
            return
        }
        mapPinCoordinate = coordinate
    }
}

private struct BSInlineAddressMap: View {
    let city: String
    let seedKeyword: String
    @Binding var pinCoordinate: CLLocationCoordinate2D?
    let addressText: String
    let onAddressPicked: (String) -> Void

    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var isResolving = false
    @State private var statusMessage: String?

    private let mapHeight: CGFloat = 156

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            MapReader { proxy in
                ZStack(alignment: .bottomLeading) {
                    Map(position: $cameraPosition, interactionModes: [.pan, .zoom]) {
                        if let pinCoordinate {
                            Marker("选中位置", coordinate: pinCoordinate)
                                .tint(BSColor.Accent.travel)
                        }
                    }
                    .mapStyle(.standard(elevation: .flat))
                    .onTapGesture { location in
                        guard let coordinate = proxy.convert(location, from: .local) else { return }
                        pinCoordinate = coordinate
                        Task { await resolveAddress(for: coordinate) }
                    }

                    LinearGradient(
                        colors: [.clear, .black.opacity(0.55)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .allowsHitTesting(false)

                    HStack(spacing: 6) {
                        if isResolving {
                            ProgressView()
                                .controlSize(.small)
                                .tint(.white)
                        } else {
                            Image(systemName: "hand.tap.fill")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        Text(isResolving ? "正在解析地址…" : "点地图选位置，可拖动缩放")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(.white.opacity(0.92))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .padding(10)
                }
            }
            .frame(height: mapHeight)
            .clipShape(RoundedRectangle(cornerRadius: BSRadius.md))
            .overlay(
                RoundedRectangle(cornerRadius: BSRadius.md)
                    .stroke(BSColor.borderProminent, lineWidth: 1)
            )

            if let statusMessage {
                Text(statusMessage)
                    .font(BSFont.caption)
                    .foregroundColor(BSColor.textTertiary)
            }
        }
        .task(id: "\(city)|\(seedKeyword)") {
            await loadInitialRegion()
        }
        .task(id: addressText) {
            await syncPinFromAddressText()
        }
    }

    @MainActor
    private func loadInitialRegion() async {
        let query = [city, seedKeyword]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        guard !query.isEmpty else {
            cameraPosition = .region(Self.defaultRegion)
            return
        }

        guard let coordinate = await MapLocationResolver.coordinate(for: query, city: city) else {
            cameraPosition = .region(Self.defaultRegion)
            statusMessage = "没能定位到默认区域，请拖动地图选点。"
            return
        }

        pinCoordinate = pinCoordinate ?? coordinate
        cameraPosition = .region(Self.region(around: coordinate))
    }

    @MainActor
    private func syncPinFromAddressText() async {
        let trimmed = addressText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 4 else { return }
        guard let coordinate = await MapLocationResolver.coordinate(for: trimmed, city: city) else { return }
        pinCoordinate = coordinate
        cameraPosition = .region(Self.region(around: coordinate))
    }

    @MainActor
    private func resolveAddress(for coordinate: CLLocationCoordinate2D) async {
        isResolving = true
        statusMessage = nil
        defer { isResolving = false }

        guard let formatted = await MapLocationResolver.address(for: coordinate),
              !formatted.isEmpty else {
            statusMessage = "这里没解析出地址，请换个位置再试。"
            return
        }

        onAddressPicked(formatted)
        cameraPosition = .region(Self.region(around: coordinate))
    }

    private static var defaultRegion: MKCoordinateRegion {
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 30.25, longitude: 120.17),
            span: MKCoordinateSpan(latitudeDelta: 0.12, longitudeDelta: 0.12)
        )
    }

    private static func region(around coordinate: CLLocationCoordinate2D) -> MKCoordinateRegion {
        MKCoordinateRegion(
            center: coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.018, longitudeDelta: 0.018)
        )
    }
}

private enum MapLocationResolver {
    @MainActor
    static func coordinate(for query: String, city: String) async -> CLLocationCoordinate2D? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let request = MKLocalSearch.Request()
        if !city.isEmpty, !trimmed.contains(city) {
            request.naturalLanguageQuery = "\(city) \(trimmed)"
        } else {
            request.naturalLanguageQuery = trimmed
        }
        request.resultTypes = [.address, .pointOfInterest]

        do {
            let response = try await MKLocalSearch(request: request).start()
            return response.mapItems.first?.placemark.coordinate
        } catch {
            return nil
        }
    }

    @MainActor
    static func address(for coordinate: CLLocationCoordinate2D) async -> String? {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let geocoder = CLGeocoder()

        do {
            let placemarks = try await geocoder.reverseGeocodeLocation(location)
            guard let placemark = placemarks.first else { return nil }
            let mapItem = MKMapItem(placemark: MKPlacemark(placemark: placemark))
            let formatted = MapKitAddressFormatter.displayAddress(for: mapItem)
            return formatted.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : formatted
        } catch {
            return nil
        }
    }
}