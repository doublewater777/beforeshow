import XCTest
@testable import BeforeShow

final class WeatherReminderPolicyTests: XCTestCase {
    private func forecast(
        high: Double? = 25,
        low: Double? = 15,
        precip: Double = 0,
        wind: Double = 10,
        condition: WeatherConditionKind = .clear
    ) -> DailyForecast {
        DailyForecast(
            highCelsius: high,
            lowCelsius: low,
            precipitationChance: precip,
            precipitationAmountMillimeters: 0,
            windSpeedKilometersPerHour: wind,
            condition: condition
        )
    }

    func testRainTriggersRainDecision() {
        let f = forecast(precip: 0.35, condition: .rain)
        let decision = WeatherReminderPolicy.decision(
            forecast: f,
            showName: "T1 决赛",
            place: "上海"
        )
        XCTAssertEqual(
            decision,
            .rain(showName: "T1 决赛", place: "上海", precipitationChance: 35)
        )
    }

    func testHighTempTriggersHeatDecision() {
        let f = forecast(high: 33, low: 24, precip: 0.1, wind: 10, condition: .clear)
        let decision = WeatherReminderPolicy.decision(
            forecast: f,
            showName: "夏日音乐节",
            place: "北京"
        )
        XCTAssertEqual(
            decision,
            .heat(showName: "夏日音乐节", place: "北京", highC: 33)
        )
    }

    func testLowTempTriggersColdDecision() {
        let f = forecast(high: 10, low: 3, precip: 0.1, wind: 10, condition: .clear)
        let decision = WeatherReminderPolicy.decision(
            forecast: f,
            showName: "冬季巡演",
            place: "哈尔滨"
        )
        XCTAssertEqual(
            decision,
            .cold(showName: "冬季巡演", place: "哈尔滨", lowC: 3)
        )
    }

    func testStrongWindTriggersWindDecision() {
        let f = forecast(high: 22, low: 14, precip: 0.05, wind: 35, condition: .cloudy)
        let decision = WeatherReminderPolicy.decision(
            forecast: f,
            showName: "海边演出",
            place: "厦门"
        )
        XCTAssertEqual(
            decision,
            .wind(showName: "海边演出", place: "厦门", windKmh: 35)
        )
    }

    func testThunderstormTriggersSevereAlert() {
        let f = forecast(high: 28, low: 22, precip: 0.8, wind: 20, condition: .thunderstorm)
        let decision = WeatherReminderPolicy.decision(
            forecast: f,
            showName: "Outdoor Show",
            place: "Tokyo"
        )
        XCTAssertEqual(
            decision,
            .severeAlert(showName: "Outdoor Show", place: "Tokyo")
        )
    }

    func testAllComfortableForecastReturnsNil() {
        let f = forecast(high: 25, low: 15, precip: 0.1, wind: 10, condition: .clear)
        let decision = WeatherReminderPolicy.decision(
            forecast: f,
            showName: "演出",
            place: "上海"
        )
        XCTAssertNil(decision)
    }

    func testNilForecastFallsBackToGeneric() {
        let decision = WeatherReminderPolicy.decision(
            forecast: nil,
            showName: "演出",
            place: "上海"
        )
        XCTAssertEqual(
            decision,
            .genericReminder(showName: "演出", place: "上海")
        )
    }

    func testBoundaryValuesDoTriggerInclusive() {
        // 边界含端点：32° / 5° / 30% / 30 km/h 都该触发
        let fHigh = forecast(high: 32, low: 5, precip: 0.3, wind: 30, condition: .clear)
        // 多个阈值都满足时按策略顺序：rain 优先
        let decision = WeatherReminderPolicy.decision(forecast: fHigh, showName: "s", place: "p")
        XCTAssertEqual(decision, .rain(showName: "s", place: "p", precipitationChance: 30))
    }

    func testBoundaryValuesJustBelowThresholdDoNotTrigger() {
        // 31.9° 高温不触发，5.1° 低温不触发
        let fHeat = forecast(high: 31.9, low: 15, precip: 0.1, wind: 10, condition: .clear)
        XCTAssertNil(WeatherReminderPolicy.decision(forecast: fHeat, showName: "s", place: "p"))
        let fCold = forecast(high: 10, low: 5.1, precip: 0.1, wind: 10, condition: .clear)
        XCTAssertNil(WeatherReminderPolicy.decision(forecast: fCold, showName: "s", place: "p"))
    }

    func testCustomThresholdsAreApplied() {
        let f = forecast(high: 33, low: 14, precip: 0.1, wind: 10, condition: .clear)
        // 自定义高温阈值 35°，33° 不再触发
        let decision = WeatherReminderPolicy.decision(
            forecast: f,
            showName: "s",
            place: "p",
            highThreshold: 35
        )
        XCTAssertNil(decision)
    }

    func testGenericCopyUsesShowNameWhenPlaceEmpty() {
        let decision: WeatherReminderPolicy.Decision = .genericReminder(showName: "我的演出", place: "")
        let (title, body) = WeatherReminderPolicy.copy(for: decision)
        XCTAssertFalse(title.isEmpty)
        XCTAssertFalse(body.isEmpty)
        XCTAssertTrue(body.contains("我的演出"))
    }

    func testGenericCopyUsesPlaceWhenProvided() {
        let decision: WeatherReminderPolicy.Decision = .genericReminder(showName: "我的演出", place: "上海")
        let (_, body) = WeatherReminderPolicy.copy(for: decision)
        XCTAssertTrue(body.contains("上海"))
    }
}
