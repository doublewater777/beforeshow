import SwiftUI

struct CurrentShowWeatherSheet: View {
    let show: Show
    let venueName: String?
    let city: String?

    @State private var weather: ShowWeatherDTO?
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
        show.timingFields.eventCalendar(fallback: .current).timeZone
    }

    private var storageKey: String {
        "beforeshow.weather.packed_items.\(show.id.uuidString)"
    }

    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 20) {
                    if let weather {
                        heroCard(weather)
                        packingChecklistSection(weather)
                        if !weather.hourly.isEmpty {
                            hourlyMilestoneSection(weather)
                        }
                        weatherMetricsGrid(weather)
                    } else if isLoading {
                        loadingPlaceholder
                    } else if let errorMessage {
                        errorPlaceholder(errorMessage)
                    } else {
                        loadingPlaceholder
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 24)
            }
            .background(BSColor.surface.ignoresSafeArea())
            .navigationTitle(BSLocalization.text("现场天气与穿搭"))
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

    // MARK: - Hero Weather Card

    private func heroCard(_ weather: ShowWeatherDTO) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: weather.condition.systemSymbolName)
                            .foregroundStyle(weather.tone.primaryTint)
                            .font(.system(size: 15, weight: .semibold))

                        Text(verbatim: venueOrCityText)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.85))
                    }

                    Text(weather.conditionDescription)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.6))
                }

                Spacer()

                Text(verbatim: "\(weather.temperatureCelsius)°")
                    .font(.system(size: 60, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.white)
                    .lineLimit(1)
            }

            HStack(spacing: 12) {
                Label(
                    title: { Text(verbatim: "最高 \(weather.highCelsius)°") },
                    icon: { Image(systemName: "arrow.up") }
                )
                Label(
                    title: { Text(verbatim: "最低 \(weather.lowCelsius)°") },
                    icon: { Image(systemName: "arrow.down") }
                )
                Label(
                    title: { Text(verbatim: "体感 \(weather.feelsLikeCelsius)°") },
                    icon: { Image(systemName: "thermometer.medium") }
                )
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Color.white.opacity(0.75))

            if !weather.summaryCallout.isEmpty {
                Text(weather.summaryCallout)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(Color.white.opacity(0.9))
                    .lineSpacing(3)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.white.opacity(0.04))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
                            )
                    )
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(BSColor.surfaceElevated)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .strokeBorder(BSColor.borderProminent, lineWidth: 0.5)
                )
        )
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

    // MARK: - Packing Checklist Section (Prioritized)

    private func packingChecklistSection(_ weather: ShowWeatherDTO) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(BSLocalization.text("出门前记得带"))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.85))

            VStack(spacing: 8) {
                ForEach(weather.packingList) { item in
                    packingItemRow(item)
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
                Text(item.emoji)
                    .font(.system(size: 20))
                    .frame(width: 36, height: 36)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.white.opacity(0.08))
                    )

                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(isPacked ? Color.white.opacity(0.5) : Color.white)
                        .strikethrough(isPacked, color: Color.white.opacity(0.4))

                    Text(item.subtitle)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(Color.white.opacity(0.6))
                        .lineLimit(2)
                }

                Spacer()

                Image(systemName: isPacked ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(isPacked ? Color.white : Color.white.opacity(0.3))
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(BSColor.surfaceElevated.opacity(isPacked ? 0.6 : 1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(BSColor.borderProminent, lineWidth: 0.5)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Hourly Milestone Track

    private func hourlyMilestoneSection(_ weather: ShowWeatherDTO) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(BSLocalization.text("演出时段"))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.85))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(weather.hourly) { item in
                        hourlyItemView(item, weather: weather)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func hourlyItemView(_ item: ShowWeatherHourlyDTO, weather: ShowWeatherDTO) -> some View {
        VStack(spacing: 6) {
            Text(formatHour(item.time))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.55))

            if let milestone = item.milestoneLabel, !milestone.isEmpty {
                Text(milestone)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(weather.tone.primaryTint)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(weather.tone.primaryTint.opacity(0.15))
                    )
            } else {
                Spacer()
                    .frame(height: 16)
            }

            Image(systemName: item.condition.systemSymbolName)
                .font(.system(size: 18))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.white.opacity(0.9))

            Text(verbatim: "\(item.temperatureCelsius)°")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.white)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 10)
        .frame(minWidth: 68)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
                )
        )
    }

    private func formatHour(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = eventTimeZone
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    // MARK: - 2x2 Metric Grid

    private func weatherMetricsGrid(_ weather: ShowWeatherDTO) -> some View {
        let precipSubtitle: String = {
            if weather.precipitationProbability <= 0.20 {
                return BSLocalization.text("下雨可能性较小")
            } else if weather.precipitationProbability <= 0.60 {
                return BSLocalization.text("当天可能有降水")
            } else {
                return BSLocalization.text("当天降水概率较高")
            }
        }()

        return LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            metricTile(
                title: BSLocalization.text("当天降水概率"),
                value: "\(Int(weather.precipitationProbability * 100))%",
                subtitle: precipSubtitle,
                systemIcon: "umbrella.fill"
            )

            metricTile(
                title: BSLocalization.text("日落时间"),
                value: sunsetTimeString(weather),
                subtitle: BSLocalization.text("想看日落，可以提前留意舞台方向"),
                systemIcon: "sunset.fill"
            )

            metricTile(
                title: BSLocalization.text("紫外线指数"),
                value: "\(weather.uvIndex)",
                subtitle: weather.uvIndex >= 5 ? BSLocalization.text("白天日晒较强，注意防晒") : BSLocalization.text("紫外线较弱"),
                systemIcon: "sun.max.fill"
            )

            metricTile(
                title: BSLocalization.text("风速"),
                value: weather.windDescription,
                subtitle: BSLocalization.text("演出时段预报"),
                systemIcon: "wind"
            )
        }
    }

    private func metricTile(title: String, value: String, subtitle: String, systemIcon: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.55))
                Spacer()
                Image(systemName: systemIcon)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.white.opacity(0.4))
            }

            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(Color.white)

            Text(subtitle)
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(Color.white.opacity(0.65))
                .lineLimit(2)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
                )
        )
    }

    private func sunsetTimeString(_ weather: ShowWeatherDTO) -> String {
        guard let sunset = weather.sunsetTime else {
            return "--:--"
        }
        let formatter = DateFormatter()
        formatter.timeZone = eventTimeZone
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: sunset)
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
            errorMessage = error.localizedDescription
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
