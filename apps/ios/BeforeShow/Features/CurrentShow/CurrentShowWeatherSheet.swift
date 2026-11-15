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
    /// Every day of a multi-day show; a single-day show has one.
    @State private var days: [ShowWeatherDay] = []
    @State private var selectedDay = 0
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

    /// The venue's time zone, as the forecast found it.
    private var eventTimeZone: TimeZone {
        shownWeather?.timeZoneIdentifier.flatMap(TimeZone.init(identifier:))
            ?? days.first?.timeZone
            ?? show.timingFields.eventCalendar(fallback: .current).timeZone
    }

    /// When the shown day's show plays.
    private var showWindow: (start: Date, end: Date) {
        if days.indices.contains(selectedDay) { return (days[selectedDay].start, days[selectedDay].end) }
        let timing = show.timingFields
        let slot = ShowWeatherDays.slots(timing: timing, calendar: timing.eventCalendar(fallback: .current))[0]
        return (slot.start, slot.end)
    }

    private var storageKey: String {
        "beforeshow.weather.packed_items.\(show.id.uuidString)"
    }

    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 10) {
                    if isMultiDay {
                        CurrentShowWeatherDayChips(days: days, selected: $selectedDay)
                    }
                    if let weather = shownWeather {
                        CurrentShowWeatherHero(place: venueOrCityText, weather: weather, anchor: anchorText(weather))
                        CurrentShowWeatherHourlyCard(
                            weather: weather,
                            summary: headline(weather),
                            showStart: showWindow.start,
                            showEnd: showWindow.end,
                            timeZone: eventTimeZone
                        )
                        CurrentShowWeatherMetricsRow(metrics: metrics(weather))
                        checklist
                        attributionFooter
                    } else if isMultiDay {
                        Text(BSLocalization.text("这一天的预报还没出，通常提前 10 天发布"))
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.8))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 48)
                        if !packingItems.isEmpty { checklist }
                        attributionFooter
                    } else if isLoading {
                        loadingPlaceholder
                    } else if let errorMessage {
                        errorPlaceholder(errorMessage)
                    } else {
                        loadingPlaceholder
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
            .navigationTitle(BSLocalization.text("现场天气"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
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
                await loadWeather()
            }
        }
        .presentationDetents([.fraction(0.88), .large])
        .presentationDragIndicator(.visible)
        .presentationBackground { CurrentShowWeatherSky(tone: shownWeather?.tone, condition: shownWeather?.condition) }
        .preferredColorScheme(.dark)
    }

    private var isMultiDay: Bool { days.count > 1 }

    /// The selected day's forecast once the days are in, the forecast the sheet opened with until then.
    private var shownWeather: ShowWeatherDTO? {
        days.indices.contains(selectedDay) ? days[selectedDay].weather : weather
    }

    private var packingItems: [ShowWeatherPackingItemDTO] {
        days.isEmpty ? weather?.packingList ?? [] : ShowWeatherDays.packingList(for: days)
    }

    // MARK: - Sections

    private var venueOrCityText: String {
        let parts = [venueName, city].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? BSLocalization.text("现场天气") : parts.joined(separator: " · ")
    }

    /// Which moment the big number is, in the timeline's own words.
    private func anchorText(_ weather: ShowWeatherDTO) -> String {
        guard let time = weather.forecastTime else { return BSLocalization.text("当天最高气温") }
        switch ShowWeatherDays.anchor(forecastTime: time, now: Date(), showStart: showWindow.start) {
        case .now: return BSLocalization.text("现在")
        case .showStart: return BSLocalization.format("开场 %@", formatHour(showWindow.start))
        case .hour: return formatHour(time)
        }
    }

    /// One sentence: will it rain while you're there.
    private func headline(_ weather: ShowWeatherDTO) -> String {
        switch weather.showPeriodPrecipitationProbability ?? weather.precipitationProbability {
        case 0.4...: return BSLocalization.text("演出时段可能下雨")
        case 0.2..<0.4: return BSLocalization.text("演出时段有零星降水可能")
        default: return BSLocalization.text("演出时段大概率不下雨")
        }
    }

    private func metrics(_ weather: ShowWeatherDTO) -> [CurrentShowWeatherMetricsRow.Metric] {
        let rain = Int(((weather.showPeriodPrecipitationProbability ?? weather.precipitationProbability) * 100).rounded())
        // "东北 3 m/s": the speed is the number, the direction its footnote.
        let wind = weather.windDescription.split(separator: " ", maxSplits: 1).map(String.init)
        // UV only matters for a show in daylight; when it does, it takes sunset's place.
        let light: CurrentShowWeatherMetricsRow.Metric = weather.uvIndex >= 3
            ? .init(title: BSLocalization.text("紫外线"), systemImage: "sun.max.fill", tint: BSColor.Accent.warm,
                    value: "\(weather.uvIndex)", footnote: anchorText(weather))
            : .init(title: BSLocalization.text("日落"), systemImage: "sunset.fill", tint: BSColor.Accent.warm,
                    value: weather.sunsetTime.map(formatHour) ?? "--:--", footnote: nil)
        return [
            .init(title: BSLocalization.text("降水"), systemImage: "umbrella.fill", tint: BSColor.Accent.info,
                  value: "\(rain)%", footnote: BSLocalization.text("演出时段")),
            .init(title: BSLocalization.text("体感"), systemImage: "thermometer.medium", tint: BSColor.Accent.danger,
                  value: "\(weather.feelsLikeCelsius)°", footnote: anchorText(weather)),
            light,
            .init(title: BSLocalization.text("风速"), systemImage: "wind", tint: BSColor.Accent.prepare,
                  value: wind.count == 2 ? wind[1] : weather.windDescription, footnote: wind.count == 2 ? wind[0] : nil)
        ]
    }

    // MARK: - Packing checklist

    /// What to pack: for a multi-day show, one list for the whole trip.
    private var checklist: some View {
        let items = packingItems
        return CurrentShowWeatherCard {
            CurrentShowWeatherCardLabel(
                title: isMultiDay ? BSLocalization.text("这几天记得带") : BSLocalization.text("出门前记得带"),
                systemImage: "checklist"
            )
        } content: {
            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    packingItemRow(item)
                    if index < items.count - 1 {
                        Rectangle().fill(Color.white.opacity(0.12)).frame(height: 0.5).padding(.leading, 40)
                    }
                }
            }
        }
    }

    private func packingItemRow(_ item: ShowWeatherPackingItemDTO) -> some View {
        let isPacked = packedItemIDs.contains(item.id)
        return Button {
            togglePackedItem(item.id)
        } label: {
            HStack(spacing: 12) {
                packingIcon(item)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Color.white.opacity(0.1)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(isPacked ? Color.white.opacity(0.6) : Color.white)
                        .strikethrough(isPacked, color: Color.white.opacity(0.6))
                    Text(item.subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.white.opacity(0.7))
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Image(systemName: isPacked ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(isPacked ? Color.white : Color.white.opacity(0.4))
            }
            .padding(.vertical, 7)
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
                .foregroundStyle(Color.white)
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

    private func formatHour(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = eventTimeZone
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
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
        .foregroundStyle(Color.white.opacity(0.6))
        .padding(.horizontal, 4)
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
            let fetched = try await LiveShowWeatherService.shared.fetchWeatherDays(for: show)
            days = ShowWeatherDays.remaining(fetched, now: Date())
            selectedDay = 0
            if fetched.allSatisfy({ $0.weather == nil }) {
                throw ShowWeatherError.forecastUnavailable
            }
        } catch {
            // Keep the forecast the sheet opened with; only an empty sheet shows the error.
            if weather == nil {
                errorMessage = (error as? ShowWeatherError)?.localizedDescription
                    ?? BSLocalization.text("暂时无法获取天气，请稍后重试")
            }
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
