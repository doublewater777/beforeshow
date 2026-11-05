import Foundation

struct ShowWeatherAtmospherePolicy: Sendable {
    init() {}

    /// 根据天气状况、落日时刻与气温计算天幕氛围基调
    func resolveTone(
        condition: ShowWeatherCondition,
        now: Date = Date(),
        sunsetTime: Date? = nil,
        temperatureCelsius: Int = 22
    ) -> WeatherAtmosphereTone {
        switch condition {
        case .rain, .heavyRain:
            return .rainBlue
        case .sunset:
            return .sunsetGold
        case .coldNight:
            return .coldNightIndigo
        case .clear, .partlyCloudy:
            if let sunset = sunsetTime {
                let interval = abs(now.timeIntervalSince(sunset))
                if interval <= 90 * 60 {
                    return .sunsetGold
                }
            }
            let hour = Calendar.current.component(.hour, from: now)
            if (hour >= 19 || hour < 6) && temperatureCelsius <= 16 {
                return .coldNightIndigo
            }
            return .neutral
        case .cloudy, .windy:
            return .neutral
        }
    }

    func weatherCalendar(timing: ShowTimingFields, locationTimeZone: TimeZone?, fallback: Calendar) throws -> Calendar {
        let identifiers = [timing.sessionTimeZoneIdentifier, timing.timeZoneIdentifier].compactMap { $0 }
        let explicitTimeZone = identifiers.compactMap(TimeZone.init(identifier:)).first
            ?? timing.timeZoneSecondsFromGMT.flatMap(TimeZone.init(secondsFromGMT:))
        guard let timeZone = explicitTimeZone ?? locationTimeZone else {
            throw ShowWeatherError.timeZoneUnavailable
        }
        var calendar = fallback
        calendar.timeZone = timeZone
        return calendar
    }

    /// 场地观演环境识别分类
    enum VenueEnvironment: Sendable, Equatable {
        case indoor
        case outdoor
        case unspecified
    }

    /// 结合场馆名称、地址与演出名称，更精确地推断观演环境（室内、露天或未明确）
    static func resolveVenueEnvironment(name: String, venueName: String?, venueAddress: String?) -> VenueEnvironment {
        let venue = "\(venueName ?? "") \(venueAddress ?? "")".lowercased()
        let eventName = name.lowercased()

        let indoorVenueKeywords = ["livehouse", "live house", "liveshop", "剧场", "剧院", "室内", "club", "bar", "演艺中心", "展馆", "大剧院", "音乐厅"]
        let outdoorVenueKeywords = ["公园", "露天", "海滩", "海滨", "沙滩", "草地", "营地", "户外", "体育场", "stadium"]

        let hasIndoorVenue = indoorVenueKeywords.contains(where: { venue.contains($0) })
        let hasOutdoorVenue = outdoorVenueKeywords.contains(where: { venue.contains($0) })

        if hasIndoorVenue && !hasOutdoorVenue {
            return .indoor
        }
        if hasOutdoorVenue && !hasIndoorVenue {
            return .outdoor
        }

        let outdoorEventKeywords = ["露天", "户外"]
        if outdoorEventKeywords.contains(where: { eventName.contains($0) }) && !hasIndoorVenue {
            return .outdoor
        }
        let indoorEventKeywords = ["室内", "livehouse", "剧场"]
        if indoorEventKeywords.contains(where: { eventName.contains($0) }) && !hasOutdoorVenue {
            return .indoor
        }
        return .unspecified
    }

    /// 场地室内/露天属性启发式判断
    static func isLikelyOutdoorVenue(name: String, venueName: String?, venueAddress: String?) -> Bool {
        resolveVenueEnvironment(name: name, venueName: venueName, venueAddress: venueAddress) != .indoor
    }

    /// 根据现场气象指标生成针对性观演行装建议清单
    func generatePackingList(
        condition: ShowWeatherCondition,
        precipitationProbability: Double,
        uvIndex: Int,
        lowCelsius: Int,
        highCelsius: Int,
        dispersalCelsius: Int? = nil,
        dispersalFeelsLike: Int? = nil,
        venueEnvironment: VenueEnvironment? = nil,
        isOutdoor: Bool? = nil
    ) -> [ShowWeatherPackingItemDTO] {
        let env: VenueEnvironment = {
            if let explicitEnv = venueEnvironment {
                return explicitEnv
            }
            if let outdoorBool = isOutdoor {
                return outdoorBool ? .outdoor : .indoor
            }
            return .unspecified
        }()
        var items: [ShowWeatherPackingItemDTO] = []

        // 1. 雨天携带雨具（露天/未明确场景重点提示雨衣，室内提示便携雨伞）
        if precipitationProbability >= 0.25 || condition == .rain || condition == .heavyRain {
            items.append(
                ShowWeatherPackingItemDTO(
                    id: "rainwear",
                    emoji: "🧥",
                    title: env == .outdoor ? BSLocalization.text("雨衣") : BSLocalization.text("雨具"),
                    subtitle: env == .outdoor ? BSLocalization.text("出行及演出时段可能有降水，记得带雨衣") : BSLocalization.text("出行及演出时段可能有降水，建议准备雨具")
                )
            )
        }

        // 2. 强紫外线防晒（仅明确户外演出提示）
        if uvIndex >= 5 && env == .outdoor {
            items.append(
                ShowWeatherPackingItemDTO(
                    id: "sunglasses",
                    emoji: "🕶️",
                    title: BSLocalization.text("墨镜、防晒帽"),
                    subtitle: BSLocalization.text("白天日晒较强，注意防晒")
                )
            )
        }

        // 3. 散场夜温与昼夜温差加衣（区分体感与实际气温，避免错误语义与过度推断）
        let needsJacket: Bool
        let jacketSubtitle: String
        if let feelsLike = dispersalFeelsLike, feelsLike <= 19 {
            needsJacket = true
            jacketSubtitle = BSLocalization.format("散场预计体感约 %1$lld°C，带件薄外套更稳妥", Int64(feelsLike))
        } else if dispersalFeelsLike == nil, let dispersal = dispersalCelsius, dispersal <= 19 {
            needsJacket = true
            jacketSubtitle = BSLocalization.format("散场预计约 %1$lld°C，带件薄外套更稳妥", Int64(dispersal))
        } else if dispersalFeelsLike == nil && dispersalCelsius == nil && highCelsius - lowCelsius >= 6 {
            needsJacket = true
            jacketSubtitle = BSLocalization.text("昼夜温差较大，建议带件薄外套")
        } else {
            needsJacket = false
            jacketSubtitle = ""
        }

        if needsJacket {
            items.append(
                ShowWeatherPackingItemDTO(
                    id: "jacket",
                    emoji: "🧥",
                    title: BSLocalization.text("薄外套"),
                    subtitle: jacketSubtitle
                )
            )
        }

        // 4. 室内轻装观演提示（仅明确室内场馆提示，不承诺场馆存包服务）
        if env == .indoor {
            items.append(
                ShowWeatherPackingItemDTO(
                    id: "light_pack",
                    emoji: "🎒",
                    title: BSLocalization.text("轻装观演"),
                    subtitle: BSLocalization.text("少带非必要随身物品，大件行李请提前确认场馆存放规定")
                )
            )
        }

        // 5. 便携补水（提示以场馆规定为准）
        items.append(
            ShowWeatherPackingItemDTO(
                id: "water_bottle",
                emoji: "💧",
                title: BSLocalization.text("及时补水"),
                subtitle: BSLocalization.text("如需携带水杯，请先确认场馆规定")
            )
        )

        // 6. 露天长时间观演湿巾清洁（仅明确户外演出提示）
        if env == .outdoor {
            items.append(
                ShowWeatherPackingItemDTO(
                    id: "wipes",
                    emoji: "🧻",
                    title: BSLocalization.text("便携湿巾"),
                    subtitle: BSLocalization.text("长时间观演，带包湿巾更方便")
                )
            )
        }

        return items
    }

    /// 在给定的日/时段预报中，针对特定演出日期和时间窗口进行精准预报解析
    func resolveForecast(
        for showID: UUID,
        showDate: Date,
        showStartTime: Date,
        showEndTime: Date,
        calendar: Calendar,
        dailyForecasts: [RawDayForecast],
        hourlyForecasts: [RawHourForecast],
        venueEnvironment: VenueEnvironment? = nil,
        isOutdoor: Bool? = nil,
        now: Date = Date()
    ) throws -> ShowWeatherDTO {
        let env = venueEnvironment ?? (isOutdoor.map { $0 ? .outdoor : .indoor } ?? .unspecified)
        // 1. 查找演出所在日期的日预报
        guard let dayForecast = dailyForecasts.first(where: {
            calendar.isDate($0.date, inSameDayAs: showDate)
        }) else {
            throw ShowWeatherError.forecastUnavailable
        }

        // 2. 筛选演出时段的小时预报（开场前 2 小时到散场后 1 小时）
        let windowStart = showStartTime.addingTimeInterval(-2 * 3600)
        let windowEnd = max(showEndTime.addingTimeInterval(3600), showStartTime.addingTimeInterval(4 * 3600))
        let relevantHours = hourlyForecasts.filter { $0.date >= windowStart && $0.date <= windowEnd }
        let selectedHours: [RawHourForecast]
        if !relevantHours.isEmpty {
            selectedHours = Array(relevantHours.prefix(8))
        } else {
            // 没有覆盖演出时段的小时预报时，不拿无关时段冒充演出时段，降级为空列表
            selectedHours = []
        }

        // 3. 选择代表性时刻的气温与状况
        let representativeHour: RawHourForecast?
        if !selectedHours.isEmpty {
            if calendar.isDate(now, inSameDayAs: showDate) && now >= windowStart {
                representativeHour = selectedHours.min(by: {
                    abs($0.date.timeIntervalSince(now)) < abs($1.date.timeIntervalSince(now))
                })
            } else {
                representativeHour = selectedHours.min(by: {
                    abs($0.date.timeIntervalSince(showStartTime)) < abs($1.date.timeIntervalSince(showStartTime))
                })
            }
        } else {
            representativeHour = nil
        }

        let temperature = representativeHour?.temperatureCelsius ?? dayForecast.highCelsius
        let condition = representativeHour?.condition ?? dayForecast.condition
        let conditionDesc = representativeHour?.conditionDescription ?? dayForecast.conditionDescription
        let feelsLike = representativeHour?.apparentTemperatureCelsius ?? temperature
        let uv = representativeHour?.uvIndex ?? dayForecast.uvIndex
        let wind = representativeHour.map { "\($0.windDirectionDescription) \($0.windSpeedMps) m/s" } ?? "--"

        let hourlyDTOs = selectedHours.map { hour in
            ShowWeatherHourlyDTO(
                time: hour.date,
                temperatureCelsius: hour.temperatureCelsius,
                condition: hour.condition,
                milestoneLabel: self.milestoneLabel(for: hour.date, startTime: showStartTime, endTime: showEndTime, sunsetTime: dayForecast.sunsetTime, calendar: calendar)
            )
        }

        let toneNow = calendar.isDate(now, inSameDayAs: showDate) ? now : showStartTime
        let tone = resolveTone(
            condition: condition,
            now: toneNow,
            sunsetTime: dayForecast.sunsetTime,
            temperatureCelsius: temperature
        )

        let dispersalHour = hourlyForecasts.filter { abs($0.date.timeIntervalSince(showEndTime)) <= 1800 }.min(by: {
            abs($0.date.timeIntervalSince(showEndTime)) < abs($1.date.timeIntervalSince(showEndTime))
        })
        let dispersalCelsius = dispersalHour?.temperatureCelsius
        let dispersalFeelsLike = dispersalHour?.apparentTemperatureCelsius

        let showPeriodRain = relevantHours.compactMap(\.precipitationChance).max()
        let packingCondition: ShowWeatherCondition = relevantHours.contains { $0.condition == .rain || $0.condition == .heavyRain } ? .rain : .clear
        let packing = generatePackingList(
            condition: packingCondition,
            precipitationProbability: showPeriodRain ?? 0,
            uvIndex: uv,
            lowCelsius: dayForecast.lowCelsius,
            highCelsius: dayForecast.highCelsius,
            dispersalCelsius: dispersalCelsius,
            dispersalFeelsLike: dispersalFeelsLike,
            venueEnvironment: env
        )

        let summary = generateSummary(
            conditionDesc: conditionDesc,
            sunsetTime: dayForecast.sunsetTime,
            high: dayForecast.highCelsius,
            low: dayForecast.lowCelsius,
            timeZone: calendar.timeZone
        )

        return ShowWeatherDTO(
            showID: showID,
            fetchedAt: now,
            timeZoneIdentifier: calendar.timeZone.identifier,
            forecastTime: representativeHour?.date,
            temperatureCelsius: temperature,
            highCelsius: dayForecast.highCelsius,
            lowCelsius: dayForecast.lowCelsius,
            condition: condition,
            conditionDescription: conditionDesc,
            summaryCallout: summary,
            hourly: hourlyDTOs,
            precipitationProbability: dayForecast.precipitationChance,
            showPeriodPrecipitationProbability: showPeriodRain,
            sunsetTime: dayForecast.sunsetTime,
            uvIndex: uv,
            feelsLikeCelsius: feelsLike,
            windDescription: wind,
            packingList: packing,
            tone: tone
        )
    }

    private func milestoneLabel(
        for hourDate: Date,
        startTime: Date,
        endTime: Date,
        sunsetTime: Date?,
        calendar: Calendar
    ) -> String? {
        if abs(hourDate.timeIntervalSince(startTime)) <= 1800 {
            return BSLocalization.text("开场")
        }
        if let sunset = sunsetTime, abs(hourDate.timeIntervalSince(sunset)) <= 1800 {
            return BSLocalization.text("日落")
        }
        if abs(hourDate.timeIntervalSince(endTime)) <= 1800 {
            return BSLocalization.text("散场")
        }
        return nil
    }

    func generateSummary(
        conditionDesc: String,
        sunsetTime: Date?,
        high: Int,
        low: Int,
        timeZone: TimeZone = .current
    ) -> String {
        let text: String
        if let sunset = sunsetTime {
            let formatter = DateFormatter()
            formatter.timeZone = timeZone
            formatter.dateFormat = "HH:mm"
            text = BSLocalization.format("演出当天预计 %1$lld°~%2$lld°。预计 %3$@ 日落，想看日落可提前留意舞台方向。", Int64(low), Int64(high), formatter.string(from: sunset))
        } else {
            text = BSLocalization.format("演出当天预计 %1$lld°~%2$lld°。", Int64(low), Int64(high))
        }
        return text
    }

    /// 在当天演出列表中寻找跨越或最临近日落时刻的演出 (如果有的话)
    func findSunsetPerformance(
        in performances: [TimetablePerformance],
        sunsetTime: Date
    ) -> TimetablePerformance? {
        // 1. 优先寻找正在落日时段演出的乐队 (startsAt <= sunsetTime && endsAt >= sunsetTime)
        let playingDuringSunset = performances.filter {
            $0.startsAt <= sunsetTime && $0.endsAt >= sunsetTime
        }
        if let interested = playingDuringSunset.first(where: { $0.isInterested }) {
            return interested
        }
        if let first = playingDuringSunset.first {
            return first
        }

        // 2. 其次寻找在日落前后 30 分钟内开演的乐队
        let nearSunset = performances.filter {
            abs($0.startsAt.timeIntervalSince(sunsetTime)) <= 1800 && $0.endsAt > sunsetTime
        }
        if let interested = nearSunset.first(where: { $0.isInterested }) {
            return interested
        }
        return nearSunset.min(by: {
            abs($0.startsAt.timeIntervalSince(sunsetTime)) < abs($1.startsAt.timeIntervalSince(sunsetTime))
        })
    }
}
