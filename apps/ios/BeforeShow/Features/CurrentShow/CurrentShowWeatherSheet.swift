import SwiftUI
import WeatherKit

struct CurrentShowWeatherSheet: View {
    let show: Show
    let venueName: String?
    let city: String?

    @State private var weather: ShowWeatherDTO?
    @State private var weatherAttribution: WeatherAttribution?
    @State private var isLoading: Bool = false
    @State private var errorMessage: String? = nil
    @State private var packedItemIDs: Set<String> = []
    @Environment(\.dismiss) private var dismiss

    init(
        show: Show,
        initialWeather: ShowWeatherDTO? = nil,
        venueName: String? = nil,
        city: String? = nil
    ) {
        self.show = show
        self._weather = State(initialValue: initialWeather)
        self.venueName = venueName ?? show.venueName
        self.city = city ?? show.city
    }

    private var eventTimeZone: TimeZone {
        weather?.timeZoneIdentifier.flatMap(TimeZone.init(identifier:))
            ?? show.timingFields.eventCalendar(fallback: .current).timeZone
    }

    private var storageKey: String {
        "beforeshow.weather.packed_items.\(show.id.uuidString)"
    }

    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 26) {
                    if let weather {
                        summary(weather)
                        timeline(weather)
                        metrics(weather)
                        checklist(weather)
                        attributionFooter
                    } else if isLoading {
                        loadingPlaceholder
                    } else if let errorMessage {
                        errorPlaceholder(errorMessage)
                    } else {
                        loadingPlaceholder
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .background(alignment: .top) { toneWash }
            .background(BSColor.surface.ignoresSafeArea())
            .navigationTitle(BSLocalization.text("现场天气"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                BSChromeToolbarCloseButton(
                    accessibilityLabel: BSLocalization.text("关闭"),
                    placement: .topBarTrailing
                ) {
                    dismiss()
                }
            }
            .task {
                weatherAttribution = try? await WeatherService.shared.attribution
            }
            .task {
                loadPackedItems()
                if weather == nil {
                    await loadWeather()
                }
            }
        }
        .presentationDetents([.fraction(0.88), .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(BSColor.surface)
        .preferredColorScheme(.dark)
    }

    /// The evening's weather tints the top of the sheet, the way it tints the 当前 page.
    @ViewBuilder
    private var toneWash: some View {
        if let weather, weather.tone != .neutral {
            LinearGradient(colors: [weather.tone.primaryTint.opacity(0.16), .clear], startPoint: .top, endPoint: .bottom)
                .frame(height: 320)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
    }

    // MARK: - Summary

    private func summary(_ weather: ShowWeatherDTO) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(venueOrCityText, systemImage: "mappin")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(BSColor.textSecondary)
                .lineLimit(1)
            HStack(alignment: .firstTextBaseline, spacing: 14) {
                Text(verbatim: "\(weather.temperatureCelsius)°")
                    .font(.system(size: 64, weight: .light, design: .rounded))
                    .foregroundStyle(BSColor.textPrimary)
                VStack(alignment: .leading, spacing: 4) {
                    Label(weather.conditionDescription, systemImage: weather.condition.systemSymbolName)
                        .symbolRenderingMode(.hierarchical)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(BSColor.textPrimary)
                    Text(weather.forecastTime.map { BSLocalization.format("%@ 预报", formatHour($0)) } ?? BSLocalization.text("当天最高气温"))
                        .font(.system(size: 12))
                        .foregroundStyle(BSColor.textSecondary)
                }
            }
            Text(headline(weather))
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(BSColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// One sentence: will it rain while you're there, and how cold it will feel.
    private func headline(_ weather: ShowWeatherDTO) -> String {
        let chance = weather.showPeriodPrecipitationProbability ?? weather.precipitationProbability
        let rain: String
        switch chance {
        case 0.4...: rain = BSLocalization.text("演出时段可能下雨")
        case 0.2..<0.4: rain = BSLocalization.text("演出时段有零星降水可能")
        default: rain = BSLocalization.text("演出时段大概率不下雨")
        }
        return BSLocalization.format("%1$@ · 体感 %2$lld°", rain, Int64(weather.feelsLikeCelsius))
    }

    private var venueOrCityText: String {
        if let venueName = venueName, !venueName.isEmpty {
            if let city = city, !city.isEmpty {
                return "\(venueName) · \(city)"
            }
            return venueName
        }
        return city ?? BSLocalization.text("现场天气")
    }

    // MARK: - Show timeline

    /// The hours around the show in one strip, the show itself marked as a band from 开场 to 散场.
    private func timeline(_ weather: ShowWeatherDTO) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle(BSLocalization.text("演出时段"))
            if weather.hourly.isEmpty {
                Text(BSLocalization.text("暂无演出时段预报"))
                    .font(.system(size: 13))
                    .foregroundStyle(BSColor.textSecondary)
            } else {
                let band = showBand(weather.hourly)
                let fits = weather.hourly.count <= 7
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 0) {
                        ForEach(Array(weather.hourly.enumerated()), id: \.element.id) { index, hour in
                            hourColumn(hour, inShow: band.contains(index), weather: weather)
                                .frame(width: fits ? nil : 56)
                                .frame(maxWidth: fits ? .infinity : nil)
                        }
                    }
                    .padding(.vertical, 10)
                    .background(alignment: .leading) { bandBackground(band, count: weather.hourly.count, tint: weather.tone.primaryTint, fits: fits) }
                    .containerRelativeFrame(.horizontal) { width, _ in fits ? width : max(width, CGFloat(weather.hourly.count) * 56) }
                }
                .scrollDisabled(fits)
            }
        }
    }

    private func hourColumn(_ hour: ShowWeatherHourlyDTO, inShow: Bool, weather: ShowWeatherDTO) -> some View {
        VStack(spacing: 8) {
            Text(hour.milestoneLabel ?? " ")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(weather.tone.primaryTint)
                .lineLimit(1)
                .fixedSize()
            Text(formatHour(hour.time))
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .foregroundStyle(inShow ? BSColor.textPrimary : BSColor.textSecondary)
            Image(systemName: hour.condition.systemSymbolName)
                .symbolRenderingMode(.multicolor)
                .font(.system(size: 18))
                .frame(height: 22)
            Text(verbatim: "\(hour.temperatureCelsius)°")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(inShow ? BSColor.textPrimary : BSColor.textSecondary)
        }
    }

    /// Hours from 开场 to 散场 (to the last hour when the forecast stops before the show ends).
    private func showBand(_ hours: [ShowWeatherHourlyDTO]) -> ClosedRange<Int> {
        let start = hours.firstIndex { $0.milestoneLabel == BSLocalization.text("开场") } ?? 0
        let end = hours.lastIndex { $0.milestoneLabel == BSLocalization.text("散场") } ?? hours.count - 1
        return start...max(start, end)
    }

    private func bandBackground(_ band: ClosedRange<Int>, count: Int, tint: Color, fits: Bool) -> some View {
        GeometryReader { proxy in
            let column = fits ? proxy.size.width / CGFloat(max(count, 1)) : 56
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(tint.opacity(0.12))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(tint.opacity(0.25), lineWidth: 0.5))
                .frame(width: column * CGFloat(band.count))
                .offset(x: column * CGFloat(band.lowerBound))
        }
    }

    // MARK: - Key numbers

    private func metrics(_ weather: ShowWeatherDTO) -> some View {
        var items: [(String, String)] = [
            (BSLocalization.text("演出时段降水"), "\(Int(((weather.showPeriodPrecipitationProbability ?? weather.precipitationProbability) * 100).rounded()))%"),
            (BSLocalization.text("体感"), "\(weather.feelsLikeCelsius)°")
        ]
        if weather.sunsetTime != nil { items.append((BSLocalization.text("日落"), sunsetTimeString(weather))) }
        // UV only matters for a show in daylight; an evening show leaves it out.
        if weather.uvIndex >= 3 { items.append((BSLocalization.text("紫外线指数"), "\(weather.uvIndex)")) }
        items.append((BSLocalization.text("风速"), weather.windDescription))
        return HStack(alignment: .top, spacing: 8) {
            ForEach(Array(items.prefix(4).enumerated()), id: \.offset) { _, item in
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.0)
                        .font(.system(size: 11))
                        .foregroundStyle(BSColor.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text(item.1)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(BSColor.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.vertical, 14)
        .overlay(alignment: .top) { Rectangle().fill(BSColor.border).frame(height: 0.5) }
        .overlay(alignment: .bottom) { Rectangle().fill(BSColor.border).frame(height: 0.5) }
    }

    // MARK: - Packing checklist

    private func checklist(_ weather: ShowWeatherDTO) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle(BSLocalization.text("出门前记得带"))
            VStack(spacing: 0) {
                ForEach(Array(weather.packingList.enumerated()), id: \.element.id) { index, item in
                    packingItemRow(item)
                    if index < weather.packingList.count - 1 {
                        Rectangle().fill(BSColor.border).frame(height: 0.5).padding(.leading, 58)
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(BSColor.surfaceElevated)
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(BSColor.borderProminent, lineWidth: 0.5))
            )
        }
    }

    private func packingItemRow(_ item: ShowWeatherPackingItemDTO) -> some View {
        let isPacked = packedItemIDs.contains(item.id)
        return Button {
            togglePackedItem(item.id)
        } label: {
            HStack(spacing: 12) {
                packingIcon(item)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(Color.white.opacity(0.07)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(isPacked ? BSColor.textSecondary : BSColor.textPrimary)
                        .strikethrough(isPacked, color: BSColor.textSecondary)
                    Text(item.subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(BSColor.textSecondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Image(systemName: isPacked ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(isPacked ? BSColor.textPrimary : BSColor.textSecondary.opacity(0.6))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// One symbol per item so similar items (rain gear, a jacket) don't share an icon.
    @ViewBuilder
    private func packingIcon(_ item: ShowWeatherPackingItemDTO) -> some View {
        if let symbol = Self.packingSymbols[item.id] {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(BSColor.textPrimary)
        } else {
            Text(item.emoji).font(.system(size: 16))
        }
    }

    private static let packingSymbols: [String: String] = [
        "rainwear": "umbrella.fill",
        "sunglasses": "sunglasses.fill",
        "jacket": "thermometer.low",
        "light_pack": "backpack.fill",
        "water_bottle": "waterbottle.fill",
        "wipes": "hands.and.sparkles.fill"
    ]

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(BSColor.textPrimary.opacity(0.85))
    }

    private func formatHour(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = eventTimeZone
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    private func sunsetTimeString(_ weather: ShowWeatherDTO) -> String {
        guard let sunset = weather.sunsetTime else {
            return "--:--"
        }
        return formatHour(sunset)
    }

    private var attributionFooter: some View {
        HStack(spacing: 6) {
            Text(BSLocalization.text("数据来源："))
            if let attribution = weatherAttribution {
                AsyncImage(url: attribution.combinedMarkDarkURL) { image in
                    image.resizable().scaledToFit()
                } placeholder: {
                    appleWeatherLabel
                }
                .frame(width: 82, height: 18, alignment: .leading)
            } else {
                appleWeatherLabel
            }
            Spacer(minLength: 8)
            Link(
                BSLocalization.text("法律补充"),
                destination: weatherAttribution?.legalPageURL
                    ?? URL(string: "https://developer.apple.com/weatherkit/data-source-attribution/")!
            )
        }
        .font(.system(size: 11))
        .foregroundStyle(BSColor.textSecondary)
        .padding(.vertical, 8)
    }

    private var appleWeatherLabel: some View {
        HStack(spacing: 3) {
            Image(systemName: "apple.logo")
            Text(BSLocalization.text("天气"))
        }
    }

    // MARK: - Loading & Error States

    private var loadingPlaceholder: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
                .tint(Color.white.opacity(0.8))
            Text(BSLocalization.text("正在查看演出当天的天气…"))
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.7))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 80)
    }

    private func errorPlaceholder(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "cloud.sun.rain.fill")
                .font(.system(size: 40))
                .foregroundStyle(Color.white.opacity(0.4))

            Text(message)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.8))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            Button {
                Task { await loadWeather() }
            } label: {
                Text(BSLocalization.text("重试"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                    .background(
                        Capsule()
                            .fill(Color.white.opacity(0.15))
                    )
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    private func loadWeather() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        do {
            let fetched = try await LiveShowWeatherService.shared.fetchWeather(for: show)
            weather = fetched
        } catch {
            errorMessage = (error as? ShowWeatherError)?.localizedDescription
                ?? BSLocalization.text("暂时无法获取天气，请稍后重试")
        }
        isLoading = false
    }

    private func loadPackedItems() {
        if let stored = UserDefaults.standard.stringArray(forKey: storageKey) {
            packedItemIDs = Set(stored)
        }
    }

    private func togglePackedItem(_ id: String) {
        withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
            if packedItemIDs.contains(id) {
                packedItemIDs.remove(id)
            } else {
                packedItemIDs.insert(id)
            }
            UserDefaults.standard.set(Array(packedItemIDs), forKey: storageKey)
        }
    }
}
