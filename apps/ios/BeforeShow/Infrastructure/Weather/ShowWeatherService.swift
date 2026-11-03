import Foundation
import CoreLocation
import WeatherKit

protocol ShowWeatherServiceProtocol: AnyObject, Sendable {
    @MainActor
    func fetchWeather(for show: Show) async throws -> ShowWeatherDTO
    func cachedWeather(for showID: UUID) -> ShowWeatherDTO?
}

private final class ShowWeatherCacheBox: @unchecked Sendable {
    let dto: ShowWeatherDTO
    let expiresAt: Date

    init(dto: ShowWeatherDTO, ttlSeconds: TimeInterval = 1800) {
        self.dto = dto
        self.expiresAt = Date().addingTimeInterval(ttlSeconds)
    }

    var isExpired: Bool {
        Date() > expiresAt
    }
}

final class LiveShowWeatherService: ShowWeatherServiceProtocol, @unchecked Sendable {
    static let shared = LiveShowWeatherService()

    private let cache = NSCache<NSString, ShowWeatherCacheBox>()
    private let geocoder = CLGeocoder()
    private let policy = ShowWeatherAtmospherePolicy()

    init() {}

    func cachedWeather(for showID: UUID) -> ShowWeatherDTO? {
        guard let box = cache.object(forKey: showID.uuidString as NSString), !box.isExpired else {
            return nil
        }
        return box.dto
    }

    @MainActor
    func fetchWeather(for show: Show) async throws -> ShowWeatherDTO {
        if let cached = cachedWeather(for: show.id) {
            return cached
        }

        do {
        // 1. 地理编码场地地址或城市
        let city = show.city
        let venueName = show.venueName
        let venueAddress = show.venueAddress
        let location = try await resolveLocation(city: city, venueName: venueName, venueAddress: venueAddress)

        // 2. WeatherKit 数据获取
        let weather = try await WeatherService.shared.weather(for: location)
        let current = weather.currentWeather

        // 3. 映射气温与状况
        let tempCelsius = Int(round(current.temperature.converted(to: .celsius).value))
        let condition = mapCondition(from: current.condition)
        let conditionDesc = current.condition.description

        // 4. 落日时刻与最高/最低温
        let todayForecast = weather.dailyForecast.first
        let highCelsius = todayForecast.map { Int(round($0.highTemperature.converted(to: .celsius).value)) } ?? tempCelsius
        let lowCelsius = todayForecast.map { Int(round($0.lowTemperature.converted(to: .celsius).value)) } ?? tempCelsius
        let sunsetTime = todayForecast?.sun.sunset
        let precipitation = todayForecast?.precipitationChance ?? 0.0
        let uv = current.uvIndex.value
        let feelsLike = Int(round(current.apparentTemperature.converted(to: .celsius).value))
        let wind = "\(current.wind.compassDirection.description) \(Int(round(current.wind.speed.converted(to: .metersPerSecond).value))) 级"

        // 5. 时段预报截取（演出开场前后时段）
        let hourly = weather.hourlyForecast.prefix(8).map { hourWeather in
            ShowWeatherHourlyDTO(
                time: hourWeather.date,
                temperatureCelsius: Int(round(hourWeather.temperature.converted(to: .celsius).value)),
                condition: mapCondition(from: hourWeather.condition)
            )
        }

        // 6. Policy 计算天幕氛围与装备清单
        let tone = policy.resolveTone(condition: condition, now: Date(), sunsetTime: sunsetTime, temperatureCelsius: tempCelsius)
        let packing = policy.generatePackingList(
            condition: condition,
            precipitationProbability: precipitation,
            uvIndex: uv,
            lowCelsius: lowCelsius,
            highCelsius: highCelsius
        )

        let summary = generateSummary(conditionDesc: conditionDesc, sunsetTime: sunsetTime, high: highCelsius, low: lowCelsius)

        let dto = ShowWeatherDTO(
            showID: show.id,
            fetchedAt: Date(),
            temperatureCelsius: tempCelsius,
            highCelsius: highCelsius,
            lowCelsius: lowCelsius,
            condition: condition,
            conditionDescription: conditionDesc,
            summaryCallout: summary,
            hourly: Array(hourly),
            precipitationProbability: precipitation,
            sunsetTime: sunsetTime,
            uvIndex: uv,
            feelsLikeCelsius: feelsLike,
            windDescription: wind,
            packingList: packing,
            tone: tone
        )

        cache.setObject(ShowWeatherCacheBox(dto: dto), forKey: show.id.uuidString as NSString)
        return dto
        } catch {
            #if DEBUG
            let fallback = makeFallbackWeather(for: show)
            cache.setObject(ShowWeatherCacheBox(dto: fallback), forKey: show.id.uuidString as NSString)
            return fallback
            #else
            throw error
            #endif
        }
    }

    private func resolveLocation(city: String?, venueName: String?, venueAddress: String?) async throws -> CLLocation {
        let queryParts = [city, venueName, venueAddress].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard !queryParts.isEmpty else {
            throw CLError(.geocodeFoundNoResult)
        }
        let query = queryParts.joined(separator: " ")
        let placemarks = try await geocoder.geocodeAddressString(query)
        guard let location = placemarks.first?.location else {
            throw CLError(.geocodeFoundNoResult)
        }
        return location
    }

    private func mapCondition(from weatherCondition: WeatherKit.WeatherCondition) -> ShowWeatherCondition {
        switch weatherCondition {
        case .clear: return .clear
        case .mostlyClear, .partlyCloudy: return .partlyCloudy
        case .cloudy, .mostlyCloudy: return .cloudy
        case .rain, .drizzle: return .rain
        case .heavyRain, .isolatedThunderstorms, .thunderstorms: return .heavyRain
        case .windy, .breezy: return .windy
        default: return .clear
        }
    }

    private func generateSummary(conditionDesc: String, sunsetTime: Date?, high: Int, low: Int) -> String {
        var text = BSLocalization.format("未来 24 小时气温 %1$lld°~%2$lld°，气候较适宜观演。", Int64(low), Int64(high))
        if let sunset = sunsetTime {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm"
            text += BSLocalization.format(" 预计 %@ 迎来最佳海滨日落晚霞。", formatter.string(from: sunset))
        }
        return text
    }

    private func makeFallbackWeather(for show: Show) -> ShowWeatherDTO {
        let calendar = Calendar.current
        let targetSunset = calendar.date(bySettingHour: 18, minute: 34, second: 0, of: show.date) ?? Date().addingTimeInterval(14400)
        let tone = policy.resolveTone(condition: .clear, now: Date(), sunsetTime: targetSunset, temperatureCelsius: 24)
        let packing = policy.generatePackingList(
            condition: .clear,
            precipitationProbability: 0.05,
            uvIndex: 6,
            lowCelsius: 20,
            highCelsius: 28
        )
        return ShowWeatherDTO(
            showID: show.id,
            fetchedAt: Date(),
            temperatureCelsius: 24,
            highCelsius: 28,
            lowCelsius: 20,
            condition: .clear,
            conditionDescription: BSLocalization.text("晴空晚霞"),
            summaryCallout: BSLocalization.text("未来 24 小时全天适宜观演。预计 18:34 将迎来最佳海滨日落晚霞，散场后海风渐大建议备一件轻薄外套。"),
            hourly: [
                ShowWeatherHourlyDTO(time: calendar.date(bySettingHour: 15, minute: 0, second: 0, of: show.date) ?? Date(), temperatureCelsius: 27, condition: .clear, milestoneLabel: BSLocalization.text("排队入场")),
                ShowWeatherHourlyDTO(time: calendar.date(bySettingHour: 17, minute: 0, second: 0, of: show.date) ?? Date(), temperatureCelsius: 28, condition: .partlyCloudy, milestoneLabel: BSLocalization.text("日落前夕")),
                ShowWeatherHourlyDTO(time: calendar.date(bySettingHour: 18, minute: 30, second: 0, of: show.date) ?? Date(), temperatureCelsius: 24, condition: .sunset, milestoneLabel: BSLocalization.text("黄金日落")),
                ShowWeatherHourlyDTO(time: calendar.date(bySettingHour: 20, minute: 0, second: 0, of: show.date) ?? Date(), temperatureCelsius: 22, condition: .coldNight, milestoneLabel: BSLocalization.text("主舞台开演")),
                ShowWeatherHourlyDTO(time: calendar.date(bySettingHour: 22, minute: 30, second: 0, of: show.date) ?? Date(), temperatureCelsius: 20, condition: .coldNight, milestoneLabel: BSLocalization.text("散场海风"))
            ],
            precipitationProbability: 0.05,
            sunsetTime: targetSunset,
            uvIndex: 6,
            feelsLikeCelsius: 24,
            windDescription: BSLocalization.text("东南风 3 级"),
            packingList: packing,
            tone: tone
        )
    }
}

final class MockShowWeatherService: ShowWeatherServiceProtocol, @unchecked Sendable {
    var stubbedWeather: ShowWeatherDTO?
    private var cache: [UUID: ShowWeatherDTO] = [:]

    init(stubbedWeather: ShowWeatherDTO? = nil) {
        self.stubbedWeather = stubbedWeather
    }

    func cachedWeather(for showID: UUID) -> ShowWeatherDTO? {
        stubbedWeather ?? cache[showID]
    }

    @MainActor
    func fetchWeather(for show: Show) async throws -> ShowWeatherDTO {
        if let stubbedWeather {
            return stubbedWeather
        }
        let generated = ShowWeatherDTO(
            showID: show.id,
            temperatureCelsius: 26,
            highCelsius: 28,
            lowCelsius: 20,
            condition: .clear,
            conditionDescription: "晴空晚霞",
            summaryCallout: "未来 24 小时全天适宜观演。预计 18:34 将迎来最佳海滨日落晚霞，散场后海风渐大建议备一件轻薄外套。",
            hourly: [
                ShowWeatherHourlyDTO(time: Date(), temperatureCelsius: 27, condition: .clear, milestoneLabel: "排队入场"),
                ShowWeatherHourlyDTO(time: Date().addingTimeInterval(7200), temperatureCelsius: 28, condition: .partlyCloudy, milestoneLabel: "刺猬乐队"),
                ShowWeatherHourlyDTO(time: Date().addingTimeInterval(14400), temperatureCelsius: 24, condition: .sunset, milestoneLabel: "黄金日落"),
                ShowWeatherHourlyDTO(time: Date().addingTimeInterval(21600), temperatureCelsius: 22, condition: .coldNight, milestoneLabel: "痛仰大合唱"),
                ShowWeatherHourlyDTO(time: Date().addingTimeInterval(28800), temperatureCelsius: 20, condition: .coldNight, milestoneLabel: "散场海风")
            ],
            precipitationProbability: 0.05,
            sunsetTime: Date().addingTimeInterval(14400),
            uvIndex: 6,
            feelsLikeCelsius: 24,
            windDescription: "东南风 3 级",
            packingList: [
                ShowWeatherPackingItemDTO(id: "sunglasses", emoji: "🕶️", title: "墨镜与遮阳帽", subtitle: "海滩紫外线 6 级 · 白天沙滩反光强烈"),
                ShowWeatherPackingItemDTO(id: "jacket", emoji: "🧥", title: "防风轻便外套", subtitle: "夜间 22:30 散场海风大 · 温度降至 20°C"),
                ShowWeatherPackingItemDTO(id: "water", emoji: "💧", title: "环保便携水杯", subtitle: "现场官方补水点支持免费续水 · 防暴晒脱水"),
                ShowWeatherPackingItemDTO(id: "repellent", emoji: "🧴", title: "驱蚊喷雾 / 湿纸巾", subtitle: "海滨草地入夜蚊虫活跃 · 便携打理沙尘")
            ],
            tone: .sunsetGold
        )
        cache[show.id] = generated
        return generated
    }
}
