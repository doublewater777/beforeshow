import Foundation

public struct ShowWeatherAtmospherePolicy: Sendable {
    public init() {}

    /// 根据天气状况、落日时刻与气温计算天幕氛围基调 (方案 1 空间物理分层底层天幕)
    public func resolveTone(
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
            // 若临假日落前后 1.5 小时内，自然呈现落日晚霞金色
            if let sunset = sunsetTime {
                let interval = abs(now.timeIntervalSince(sunset))
                if interval <= 90 * 60 {
                    return .sunsetGold
                }
            }
            // 若夜间且气温较低，呈现晴冷寒夜天幕
            let hour = Calendar.current.component(.hour, from: now)
            if (hour >= 19 || hour < 6) && temperatureCelsius <= 16 {
                return .coldNightIndigo
            }
            return .neutral
        case .cloudy, .windy:
            return .neutral
        }
    }

    /// 根据现场气象指标生成针对性观演行装建议清单
    public func generatePackingList(
        condition: ShowWeatherCondition,
        precipitationProbability: Double,
        uvIndex: Int,
        lowCelsius: Int,
        highCelsius: Int,
        isOutdoor: Bool = true
    ) -> [ShowWeatherPackingItemDTO] {
        var items: [ShowWeatherPackingItemDTO] = []

        // 1. 雨天防泥泞
        if precipitationProbability >= 0.25 || condition == .rain || condition == .heavyRain {
            items.append(
                ShowWeatherPackingItemDTO(
                    id: "rainwear",
                    emoji: "🧥",
                    title: BSLocalization.text("雨衣与防水鞋"),
                    subtitle: BSLocalization.text("现场有阵雨可能 · 草地易泥泞别穿浅色鞋")
                )
            )
        }

        // 2. 强紫外线防晒
        if uvIndex >= 5 && isOutdoor {
            items.append(
                ShowWeatherPackingItemDTO(
                    id: "sunglasses",
                    emoji: "🕶️",
                    title: BSLocalization.text("墨镜与遮阳帽"),
                    subtitle: BSLocalization.text("紫外线偏强 · 露天反光强烈保护双眼")
                )
            )
        }

        // 3. 散场夜风 / 昼夜温差加衣
        if (highCelsius - lowCelsius >= 6) || lowCelsius <= 20 {
            items.append(
                ShowWeatherPackingItemDTO(
                    id: "jacket",
                    emoji: "🧥",
                    title: BSLocalization.text("防风轻便外套"),
                    subtitle: BSLocalization.text("夜间散场海风较凉 · 温度下降明显")
                )
            )
        }

        // 4. 便携补水
        items.append(
            ShowWeatherPackingItemDTO(
                id: "water_bottle",
                emoji: "💧",
                title: BSLocalization.text("环保便携水杯"),
                subtitle: BSLocalization.text("官方补水点支持免费续水 · 防暴晒脱水")
            )
        )

        // 5. 露天防蚊防尘
        if isOutdoor {
            items.append(
                ShowWeatherPackingItemDTO(
                    id: "repellent",
                    emoji: "🧴",
                    title: BSLocalization.text("驱蚊喷雾与湿巾"),
                    subtitle: BSLocalization.text("草地入夜蚊虫活跃 · 便携打理沙尘")
                )
            )
        }

        return items
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
            abs($0.startsAt.timeIntervalSince(sunsetTime)) <= 1800
        }
        if let interested = nearSunset.first(where: { $0.isInterested }) {
            return interested
        }
        return nearSunset.min(by: {
            abs($0.startsAt.timeIntervalSince(sunsetTime)) < abs($1.startsAt.timeIntervalSince(sunsetTime))
        })
    }
}
