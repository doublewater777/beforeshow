import SwiftUI

/// The sky behind the weather sheet, painted from the shown day's weather.
struct CurrentShowWeatherSky: View {
    let tone: WeatherAtmosphereTone?
    let condition: ShowWeatherCondition?

    var body: some View {
        LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()
            .animation(.easeInOut(duration: 0.4), value: colors)
    }

    private var colors: [Color] {
        switch tone {
        case .sunsetGold:
            [Color(red: 0.29, green: 0.26, blue: 0.58), Color(red: 0.78, green: 0.45, blue: 0.36)]
        case .rainBlue:
            [Color(red: 0.16, green: 0.33, blue: 0.52), Color(red: 0.11, green: 0.22, blue: 0.38)]
        case .coldNightIndigo:
            [Color(red: 0.11, green: 0.13, blue: 0.40), Color(red: 0.27, green: 0.19, blue: 0.50)]
        case .neutral, nil:
            switch condition {
            case .clear, .partlyCloudy, .sunset:
                [Color(red: 0.16, green: 0.42, blue: 0.80), Color(red: 0.36, green: 0.62, blue: 0.90)]
            default:
                [Color(red: 0.22, green: 0.35, blue: 0.56), Color(red: 0.30, green: 0.36, blue: 0.58)]
            }
        }
    }
}

/// A translucent module over the sky, letting its color through.
struct CurrentShowWeatherCard<Header: View, Content: View>: View {
    @ViewBuilder let header: Header
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            Rectangle().fill(Color.white.opacity(0.18)).frame(height: 0.5)
            content
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct CurrentShowWeatherCardLabel: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Color.white.opacity(0.7))
            .lineLimit(1)
    }
}

// MARK: - Hero

/// The big number and what it is, in one row.
struct CurrentShowWeatherHero: View {
    let place: String
    let weather: ShowWeatherDTO
    /// Which moment the big number is: 现在, 开场 20:00, …
    let anchor: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Label(place, systemImage: "mappin")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.8))
                .lineLimit(1)
            HStack(alignment: .center, spacing: 16) {
                Text(verbatim: "\(weather.temperatureCelsius)°")
                    .font(.system(size: 76, weight: .thin))
                    .fixedSize()
                VStack(alignment: .leading, spacing: 4) {
                    Label {
                        Text(verbatim: "\(anchor) · \(weather.conditionDescription)")
                    } icon: {
                        Image(systemName: weather.condition.systemSymbolName).symbolRenderingMode(.multicolor)
                    }
                    .font(.system(size: 18, weight: .semibold))
                    Text(BSLocalization.format("最高 %1$lld° 最低 %2$lld°", Int64(weather.highCelsius), Int64(weather.lowCelsius)))
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.85))
                }
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            }
        }
        .foregroundStyle(Color.white)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Days

/// One chip per day of a multi-day show; the sheet follows the selected one.
struct CurrentShowWeatherDayChips: View {
    let days: [ShowWeatherDay]
    @Binding var selected: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(Array(days.enumerated()), id: \.element.id) { offset, day in
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { selected = offset }
                } label: {
                    chip(day, isSelected: offset == selected)
                }
                .buttonStyle(.plain)
            }
        }
        .sensoryFeedback(.selection, trigger: selected)
    }

    private func chip(_ day: ShowWeatherDay, isSelected: Bool) -> some View {
        HStack(spacing: 6) {
            Text(verbatim: "Day \(day.index)")
                .font(.system(size: 13, weight: .bold))
            Image(systemName: day.weather?.condition.systemSymbolName ?? "ellipsis")
                .symbolRenderingMode(.multicolor)
                .font(.system(size: 14))
            Text(day.weather.map { "\($0.highCelsius)°/\($0.lowCelsius)°" } ?? "—")
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .foregroundStyle(Color.white.opacity(isSelected ? 1 : 0.75))
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity)
        .background(Capsule().fill(Color.white.opacity(isSelected ? 0.28 : 0.12)))
    }
}

// MARK: - Hourly

/// The show day hour by hour, the show itself a lighter band from 开场 to 散场.
struct CurrentShowWeatherHourlyCard: View {
    let weather: ShowWeatherDTO
    let summary: String
    let showStart: Date
    let showEnd: Date
    let timeZone: TimeZone

    private let columnWidth: CGFloat = 50

    var body: some View {
        CurrentShowWeatherCard {
            Text(summary)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.white)
        } content: {
            if weather.hourly.isEmpty {
                Text(BSLocalization.text("暂无演出时段预报"))
                    .font(.system(size: 13))
                    .foregroundStyle(Color.white.opacity(0.7))
            } else {
                strip
            }
        }
    }

    private var strip: some View {
        let hours = weather.hourly.map(\.time)
        let band = ShowWeatherDays.showBand(hours: hours, start: showStart, end: showEnd) ?? 0...(hours.count - 1)
        let now = Date()
        let nowIndex = weather.forecastTime.flatMap { time in
            ShowWeatherDays.anchor(forecastTime: time, now: now, showStart: showStart) == .now ? hours.firstIndex(of: time) : nil
        } ?? ShowWeatherDays.currentIndex(hours: hours, now: now)
        // The whole day is there to scroll back to; it opens on now at the venue, otherwise just before doors.
        let lead = weather.hourly[ShowWeatherDays.leadIndex(hours: hours, band: band, now: now)].id
        return ScrollViewReader { reader in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(Array(weather.hourly.enumerated()), id: \.element.id) { index, hour in
                        column(hour, isNow: index == nowIndex)
                            .frame(width: columnWidth)
                            .id(hour.id)
                    }
                }
                .padding(.vertical, 6)
                .background(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.white.opacity(0.14))
                        .frame(width: columnWidth * CGFloat(band.count))
                        .offset(x: columnWidth * CGFloat(band.lowerBound))
                }
            }
            .onAppear { reader.scrollTo(lead, anchor: .leading) }
            .onChange(of: lead) { _, newLead in reader.scrollTo(newLead, anchor: .leading) }
        }
    }

    private func column(_ hour: ShowWeatherHourlyDTO, isNow: Bool) -> some View {
        VStack(spacing: 6) {
            Text(hour.milestoneLabel ?? " ")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(BSColor.Accent.warm)
                .fixedSize()
            Text(isNow ? BSLocalization.text("现在") : hourText(hour.time))
                .font(.system(size: 13, weight: isNow ? .bold : .medium))
                .lineLimit(1)
                .fixedSize()
            Image(systemName: hour.condition.systemSymbolName)
                .symbolRenderingMode(.multicolor)
                .font(.system(size: 18))
                .frame(height: 22)
            Text(verbatim: "\(hour.temperatureCelsius)°")
                .font(.system(size: 17, weight: .semibold))
        }
        .foregroundStyle(Color.white)
    }

    private func hourText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = timeZone
        formatter.setLocalizedDateFormatFromTemplate("j")
        return formatter.string(from: date)
    }
}

// MARK: - Metrics

/// The key numbers in one row, each in its own color.
struct CurrentShowWeatherMetricsRow: View {
    struct Metric: Identifiable {
        let title: String
        let systemImage: String
        let tint: Color
        let value: String
        let footnote: String?
        var id: String { title }
    }

    let metrics: [Metric]

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(metrics) { metric in
                VStack(alignment: .leading, spacing: 4) {
                    Label(metric.title, systemImage: metric.systemImage)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(metric.tint)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text(metric.value)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Color.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text(metric.footnote ?? " ")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.75))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
