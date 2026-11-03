import Foundation
import SwiftUI

public enum ShowWeatherCondition: String, Codable, Sendable, CaseIterable {
    case clear
    case sunset
    case partlyCloudy
    case cloudy
    case rain
    case heavyRain
    case coldNight
    case windy

    public var systemSymbolName: String {
        switch self {
        case .clear: return "sun.max.fill"
        case .sunset: return "sunset.fill"
        case .partlyCloudy: return "cloud.sun.fill"
        case .cloudy: return "cloud.fill"
        case .rain: return "cloud.rain.fill"
        case .heavyRain: return "cloud.heavyrain.fill"
        case .coldNight: return "moon.stars.fill"
        case .windy: return "wind"
        }
    }
}

public enum WeatherAtmosphereTone: String, Codable, Sendable, CaseIterable {
    case sunsetGold
    case rainBlue
    case coldNightIndigo
    case neutral

    public var primaryTint: Color {
        switch self {
        case .sunsetGold:
            return Color(red: 255/255, green: 180/255, blue: 90/255)
        case .rainBlue:
            return Color(red: 100/255, green: 170/255, blue: 255/255)
        case .coldNightIndigo:
            return Color(red: 160/255, green: 180/255, blue: 255/255)
        case .neutral:
            return Color.white.opacity(0.85)
        }
    }
}

public struct ShowWeatherHourlyDTO: Codable, Sendable, Identifiable, Equatable {
    public var id: String { "\(time.timeIntervalSince1970)" }
    public let time: Date
    public let temperatureCelsius: Int
    public let condition: ShowWeatherCondition
    public let milestoneLabel: String?

    public init(
        time: Date,
        temperatureCelsius: Int,
        condition: ShowWeatherCondition,
        milestoneLabel: String? = nil
    ) {
        self.time = time
        self.temperatureCelsius = temperatureCelsius
        self.condition = condition
        self.milestoneLabel = milestoneLabel
    }
}

public struct ShowWeatherPackingItemDTO: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public let emoji: String
    public let title: String
    public let subtitle: String

    public init(id: String, emoji: String, title: String, subtitle: String) {
        self.id = id
        self.emoji = emoji
        self.title = title
        self.subtitle = subtitle
    }
}

public struct ShowWeatherDTO: Codable, Sendable, Equatable {
    public let showID: UUID
    public let fetchedAt: Date
    public let temperatureCelsius: Int
    public let highCelsius: Int
    public let lowCelsius: Int
    public let condition: ShowWeatherCondition
    public let conditionDescription: String
    public let summaryCallout: String
    public let hourly: [ShowWeatherHourlyDTO]
    public let precipitationProbability: Double
    public let sunsetTime: Date?
    public let uvIndex: Int
    public let feelsLikeCelsius: Int
    public let windDescription: String
    public let packingList: [ShowWeatherPackingItemDTO]
    public let tone: WeatherAtmosphereTone

    public init(
        showID: UUID,
        fetchedAt: Date = Date(),
        temperatureCelsius: Int,
        highCelsius: Int,
        lowCelsius: Int,
        condition: ShowWeatherCondition,
        conditionDescription: String,
        summaryCallout: String,
        hourly: [ShowWeatherHourlyDTO],
        precipitationProbability: Double,
        sunsetTime: Date?,
        uvIndex: Int,
        feelsLikeCelsius: Int,
        windDescription: String,
        packingList: [ShowWeatherPackingItemDTO],
        tone: WeatherAtmosphereTone
    ) {
        self.showID = showID
        self.fetchedAt = fetchedAt
        self.temperatureCelsius = temperatureCelsius
        self.highCelsius = highCelsius
        self.lowCelsius = lowCelsius
        self.condition = condition
        self.conditionDescription = conditionDescription
        self.summaryCallout = summaryCallout
        self.hourly = hourly
        self.precipitationProbability = precipitationProbability
        self.sunsetTime = sunsetTime
        self.uvIndex = uvIndex
        self.feelsLikeCelsius = feelsLikeCelsius
        self.windDescription = windDescription
        self.packingList = packingList
        self.tone = tone
    }
}
