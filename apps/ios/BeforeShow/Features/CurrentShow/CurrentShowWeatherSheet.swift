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

    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 20) {
                    if let weather {
                        heroCard(weather)
                        hourlyMilestoneSection(weather)
                        weatherMetricsGrid(weather)
                        packingChecklistSection(weather)
                        bottomActionButton
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
            .task {
                if weather == nil {
                    await loadWeather()
                }
            }
            .background(Color(red: 22/255, green: 22/255, blue: 26/255).ignoresSafeArea())
            .navigationTitle(BSLocalization.text("现场微气候与穿搭"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Color.white.opacity(0.7))
                            .frame(width: 30, height: 30)
                            .background(Circle().fill(Color.white.opacity(0.1)))
                    }
                    .accessibilityLabel(BSLocalization.text("关闭"))
                }
            }
        }
        .presentationDetents([.fraction(0.88), .large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(28)
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
                .fill(Color.white.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .strokeBorder(Color.white.opacity(0.1), lineWidth: 0.5)
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

    // MARK: - Hourly Milestone Track

    private func hourlyMilestoneSection(_ weather: ShowWeatherDTO) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(BSLocalization.text("演出现场时刻气象"))
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
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    // MARK: - 2x2 Metric Grid

    private func weatherMetricsGrid(_ weather: ShowWeatherDTO) -> some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            metricTile(
                title: BSLocalization.text("降水概率"),
                value: "\(Int(weather.precipitationProbability * 100))%",
                subtitle: weather.precipitationProbability > 0.3 ? BSLocalization.text("建议携带雨衣") : BSLocalization.text("降水极小，无需担心泥泞"),
                systemIcon: "umbrella.fill"
            )

            metricTile(
                title: BSLocalization.text("日落时刻"),
                value: sunsetTimeString(weather),
                subtitle: BSLocalization.text("黄金日落晚霞"),
                systemIcon: "sunset.fill"
            )

            metricTile(
                title: BSLocalization.text("紫外线指数"),
                value: "\(weather.uvIndex)",
                subtitle: weather.uvIndex >= 5 ? BSLocalization.text("中高度 · 建议佩戴墨镜") : BSLocalization.text("温和紫外线"),
                systemIcon: "sun.max.fill"
            )

            metricTile(
                title: BSLocalization.text("现场风力"),
                value: weather.windDescription,
                subtitle: BSLocalization.text("入夜散场海风微凉"),
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
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: sunset)
    }

    // MARK: - Packing Checklist Section

    private func packingChecklistSection(_ weather: ShowWeatherDTO) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(BSLocalization.text("观演携带与穿搭建议"))
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
            withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                if isPacked {
                    packedItemIDs.remove(item.id)
                } else {
                    packedItemIDs.insert(item.id)
                }
            }
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
                    .fill(Color.white.opacity(isPacked ? 0.02 : 0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(Color.white.opacity(0.06), lineWidth: 0.5)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Bottom Action Button

    private var bottomActionButton: some View {
        Button(BSLocalization.text("已记下穿搭建议")) {
            dismiss()
        }
        .buttonStyle(BSPrimaryButtonStyle())
        .padding(.top, 4)
    }

    // MARK: - Loading & Error States

    private var loadingPlaceholder: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
                .tint(Color.white.opacity(0.8))
            Text(BSLocalization.text("正在获取现场天气…"))
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
}
