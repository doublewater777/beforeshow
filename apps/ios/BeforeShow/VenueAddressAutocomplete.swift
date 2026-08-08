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

/// 场馆选择：一个输入框填场馆名（name），选到场地后把地址（address）作为只读说明展示在下方，
/// 形态类似地图 pin 的 name + address。地址由自动补全填写，不单独输入。
struct BSVenueField: View {
    @Binding var venueName: String
    @Binding var venueAddress: String
    var city: String = ""
    var isRecognized = false
    var provider: any AddressSuggestionProviding = MapKitAddressSuggestionProvider()

    @State private var suggestions: [AddressSuggestion] = []
    @State private var isSearching = false
    @State private var searchMessage: String?
    @State private var searchTask: Task<Void, Never>?
    @FocusState private var isFocused: Bool

    private var trimmedCity: String {
        city.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedName: String {
        venueName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedAddress: String {
        venueAddress.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("场馆")
                .font(BSFont.caption)
                .foregroundColor(BSColor.textTertiary)

            TextField("上海体育场", text: $venueName, axis: .vertical)
                .lineLimit(1...3)
                .textInputAutocapitalization(.never)
                .bsInputField()
                .focused($isFocused)
                .accessibilityLabel("场馆")
                .overlay {
                    if isRecognized {
                        RoundedRectangle(cornerRadius: BSRadius.md)
                            .stroke(BSColor.Accent.prepare.opacity(0.30), lineWidth: 1)
                    }
                }
                .onChange(of: venueName) { _, newValue in
                    scheduleSearch(for: newValue)
                }
                .onChange(of: isFocused) { _, focused in
                    if focused {
                        // 聚焦不预取：没有独立已知名字来源，输入时自然触发补全。
                    } else {
                        searchTask?.cancel()
                    }
                }

            if !trimmedAddress.isEmpty {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "mappin.and.ellipse")
                        .font(.system(size: 11, weight: .semibold))
                    Text(venueAddress)
                        .lineLimit(2)
                }
                .font(.system(size: 12))
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
            searchMessage = suggestions.isEmpty ? "没找到匹配地址。" : nil
        } catch {
            suggestions = []
            searchMessage = "暂时没查到地址，请稍后再试。"
        }
    }

    private func applySuggestion(_ suggestion: AddressSuggestion) {
        venueName = suggestion.name
        venueAddress = suggestion.fillText
        suggestions = []
        searchMessage = nil
        isFocused = false
    }
}
