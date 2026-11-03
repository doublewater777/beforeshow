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

    /// 场地室内/露天属性启发式判断
    static func isLikelyOutdoorVenue(name: String, venueName: String?, venueAddress: String?) -> Bool {
        let combined = "\(name) \(venueName ?? "") \(venueAddress ?? "")".lowercased()
        let indoorKeywords = ["livehouse", "live house", "liveshop", "剧场", "剧院", "室内", "空间", "厂房", "展馆", "体育馆", "演艺中心", "club", "bar"]
        let outdoorKeywords = ["音乐节", "公园", "露天", "海滩", "海滨", "沙滩", "草地", "营地", "户外", "体育场", "stadium", "fest"]
        if outdoorKeywords.contains(where: { combined.contains($0) }) {
            return true
        }
        if indoorKeywords.contains(where: { combined.contains($0) }) {
            return false
        }
        return true
    }

    /// 根据现场气象指标生成针对性观演行装建议清单
    func generatePackingList(
        condition: ShowWeatherCondition,
        precipitationProbability: Double,
        uvIndex: Int,
        lowCelsius: Int,
        highCelsius: Int,
        dispersalCelsius: Int? = nil,
        isOutdoor: Bool = true
    ) -> [ShowWeatherPackingItemDTO] {
        var items: [ShowWeatherPackingItemDTO] = []

        // 1. 雨天携带雨具
        if precipitationProbability >= 0.25 || condition == .rain || condition == .heavyRain {
            items.append(
                ShowWeatherPackingItemDTO(
                    id: "rainwear",
                    emoji: "🧥",
                    title: BSLocalization.text("雨衣与防水鞋"),
                    subtitle: BSLocalization.text("现场有降水可能 · 建议备好雨具与轻便防滑鞋")
                )
            )
        }

        // 2. 强紫外线防晒（仅户外演出）
        if uvIndex >= 5 && isOutdoor {
            items.append(
                ShowWeatherPackingItemDTO(
                    id: "sunglasses",
                    emoji: "🕶️",
                    title: BSLocalization.text("墨镜与遮阳帽"),
                    subtitle: BSLocalization.text("紫外线偏强 · 建议佩戴墨镜保护双眼")
                )
            )
        }

        // 3. 散场夜温与昼夜温差加衣
        let needsJacket: Bool
        let jacketSubtitle: String
        if let dispersal = dispersalCelsius, dispersal <= 19 {
            needsJacket = true
            jacketSubtitle = BSLocalization.format("深夜散场体感约 %1$lld°C 较凉 · 观演大汗易着凉，备一件外套", Int64(dispersal))
        } else if (highCelsius - lowCelsius >= 6) || lowCelsius <= 20 {
            needsJacket = true
            jacketSubtitle = BSLocalization.text("晚间散场气温走低 · 建议备一件保暖外套")
        } else {
            needsJacket = false
            jacketSubtitle = ""
        }

        if needsJacket {
            items.append(
                ShowWeatherPackingItemDTO(
                    id: "jacket",
                    emoji: "🧥",
                    title: BSLocalization.text("防风轻便外套"),
                    subtitle: jacketSubtitle
                )
            )
        }

        // 4. 室内轻装观演存包提示
        if !isOutdoor {
            items.append(
                ShowWeatherPackingItemDTO(
                    id: "light_pack",
                    emoji: "🎒",
                    title: BSLocalization.text("轻装轻便出行"),
                    subtitle: BSLocalization.text("室内站席体感温热 · 避免携带大包，提前存好行李")
                )
            )
        }

        // 5. 便携补水
        items.append(
            ShowWeatherPackingItemDTO(
                id: "water_bottle",
                emoji: "💧",
                title: BSLocalization.text("便携水杯"),
                subtitle: BSLocalization.text("适时补充水分 · 保持观演体力")
            )
        )

        // 6. 露天防蚊防尘（仅户外演出）
        if isOutdoor {
            items.append(
                ShowWeatherPackingItemDTO(
                    id: "repellent",
                    emoji: "🧴",
                    title: BSLocalization.text("驱蚊喷雾与湿巾"),
                    subtitle: BSLocalization.text("露天入夜蚊虫活跃 · 便携打理随身物品")
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
        isOutdoor: Bool = true,
        now: Date = Date()
    ) throws -> ShowWeatherDTO {
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
        let conditionDesc = dayForecast.conditionDescription
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

        let dispersalHour = selectedHours.min(by: {
            abs($0.date.timeIntervalSince(showEndTime)) < abs($1.date.timeIntervalSince(showEndTime))
        })
        let dispersalCelsius = dispersalHour?.temperatureCelsius

        let packing = generatePackingList(
            condition: condition,
            precipitationProbability: dayForecast.precipitationChance,
            uvIndex: uv,
            lowCelsius: dayForecast.lowCelsius,
            highCelsius: dayForecast.highCelsius,
            dispersalCelsius: dispersalCelsius,
            isOutdoor: isOutdoor
        )

        let summary = generateSummary(
            conditionDesc: conditionDesc,
            sunsetTime: dayForecast.sunsetTime,
            high: dayForecast.highCelsius,
            low: dayForecast.lowCelsius
        )

        return ShowWeatherDTO(
            showID: showID,
            fetchedAt: now,
            temperatureCelsius: temperature,
            highCelsius: dayForecast.highCelsius,
            lowCelsius: dayForecast.lowCelsius,
            condition: condition,
            conditionDescription: conditionDesc,
            summaryCallout: summary,
            hourly: hourlyDTOs,
            precipitationProbability: dayForecast.precipitationChance,
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
        low: Int
    ) -> String {
        var text = BSLocalization.format("演出日气温 %1$lld°~%2$lld°，气候较适宜观演。", Int64(low), Int64(high))
        if let sunset = sunsetTime {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm"
            text += BSLocalization.format(" 预计 %@ 迎来落日晚霞时段。", formatter.string(from: sunset))
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
