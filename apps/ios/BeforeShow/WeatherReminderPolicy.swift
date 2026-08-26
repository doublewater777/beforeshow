import Foundation

/// 天气通知政策：纯函数 + 阈值常量，零副作用，方便单测。
enum WeatherReminderPolicy {
    static let highTempThresholdC: Double = 32
    static let lowTempThresholdC: Double = 5
    /// 0–1 区间（不是百分比）。30% 降水概率触发。
    static let precipitationThreshold: Double = 0.3
    /// km/h。30 km/h 触发大风提醒。
    static let windSpeedThresholdKmh: Double = 30

    enum Decision: Equatable, Sendable {
        case severeAlert(showName: String, place: String)
        case rain(showName: String, place: String, precipitationChance: Int)
        case snow(showName: String, place: String, precipitationChance: Int)
        case heat(showName: String, place: String, highC: Int)
        case cold(showName: String, place: String, lowC: Int)
        case wind(showName: String, place: String, windKmh: Int)
        /// 天气数据全无时的兜底：原 .oneDayBefore 的「明天见」。
        case genericReminder(showName: String, place: String)

        var isWeatherAlert: Bool {
            switch self {
            case .genericReminder:
                return false
            case .severeAlert, .rain, .snow, .heat, .cold, .wind:
                return true
            }
        }
    }

    /// 阈值在调用方固定传入（默认常量），方便测试时覆盖。
    static func decision(
        forecast: DailyForecast?,
        showName: String,
        place: String,
        highThreshold: Double = highTempThresholdC,
        lowThreshold: Double = lowTempThresholdC,
        precipitationThreshold: Double = precipitationThreshold,
        windThreshold: Double = windSpeedThresholdKmh
    ) -> Decision? {
        guard let forecast, forecast != .unavailable else {
            return .genericReminder(showName: showName, place: place)
        }
        if forecast.condition == .thunderstorm {
            return .severeAlert(showName: showName, place: place)
        }
        if forecast.condition == .snow || forecast.condition == .sleet {
            return .snow(
                showName: showName,
                place: place,
                precipitationChance: Int((forecast.precipitationChance * 100).rounded())
            )
        }
        if forecast.precipitationChance >= precipitationThreshold || forecast.condition.isWet {
            return .rain(
                showName: showName,
                place: place,
                precipitationChance: Int((forecast.precipitationChance * 100).rounded())
            )
        }
        if let high = forecast.highCelsius, high >= highThreshold {
            return .heat(showName: showName, place: place, highC: Int(high.rounded()))
        }
        if let low = forecast.lowCelsius, low <= lowThreshold {
            return .cold(showName: showName, place: place, lowC: Int(low.rounded()))
        }
        if forecast.windSpeedKilometersPerHour >= windThreshold {
            return .wind(
                showName: showName,
                place: place,
                windKmh: Int(forecast.windSpeedKilometersPerHour.rounded())
            )
        }
        return nil
    }

    /// 把 Decision 翻译成本地化文案。
    static func copy(for decision: Decision) -> (titleKey: String, body: String) {
        switch decision {
        case .severeAlert(let showName, let place):
            let title = BSLocalization.text("weatherReminderTitleAlert")
            let body = BSLocalization.format("weatherReminderBodyAlert", showName, place.isEmpty ? "—" : place)
            return attributed(title, body)
        case .rain(let showName, let place, _):
            let title = BSLocalization.text("weatherReminderTitleRain")
            let body = BSLocalization.format(
                "weatherReminderBodyRain",
                showName,
                place.isEmpty ? "—" : place
            )
            return attributed(title, body)
        case .snow(let showName, let place, _):
            let title = BSLocalization.text("weatherReminderTitleSnow")
            let body = BSLocalization.format(
                "weatherReminderBodySnow",
                showName,
                place.isEmpty ? "—" : place
            )
            return attributed(title, body)
        case .heat(let showName, let place, let highC):
            let title = BSLocalization.text("weatherReminderTitleHot")
            let body = BSLocalization.format(
                "weatherReminderBodyHot",
                showName,
                place.isEmpty ? "—" : place,
                highC
            )
            return attributed(title, body)
        case .cold(let showName, let place, let lowC):
            let title = BSLocalization.text("weatherReminderTitleCold")
            let body = BSLocalization.format(
                "weatherReminderBodyCold",
                showName,
                place.isEmpty ? "—" : place,
                lowC
            )
            return attributed(title, body)
        case .wind(let showName, let place, _):
            let title = BSLocalization.text("weatherReminderTitleWindy")
            let body = BSLocalization.format(
                "weatherReminderBodyWindy",
                showName,
                place.isEmpty ? "—" : place
            )
            return attributed(title, body)
        case .genericReminder(let showName, let place):
            // 复用现有「明天见」标题 key：和原 .oneDayBefore 通知一致，三语种都映射好。
            let title = BSLocalization.text("明天见")
            let body = BSLocalization.format("weatherReminderTomorrowGeneric", place.isEmpty ? showName : place)
            return (title, body)
        }
    }

    private static func attributed(_ title: String, _ body: String) -> (String, String) {
        (title, body + "\n" + BSLocalization.text("weatherReminderAttribution"))
    }
}
