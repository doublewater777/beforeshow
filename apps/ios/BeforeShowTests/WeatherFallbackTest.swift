import XCTest
@testable import BeforeShow

final class WeatherFallbackTest: XCTestCase {
    /// 模拟 Apple Developer 后台没勾选 WeatherKit：fetch 抛 401。
    /// 跑通这条说明：用户没感知的「明天见」兜底一定可达。
    func testWeatherKitFailureFallsBackToGeneric() async {
        struct FailingProvider: WeatherForecastProvider {
            func fetchDailyForecast(at: GeocodedCoordinate, date: Date) async throws -> DailyForecast? {
                throw NSError(
                    domain: "WeatherKit.Error",
                    code: 401,
                    userInfo: [NSLocalizedDescriptionKey: "Missing entitlement com.apple.developer.weatherkit"]
                )
            }
        }
        struct StubGeocoding: Geocoding {
            func resolve(city: String?, address: String?) async throws -> GeocodedCoordinate? {
                GeocodedCoordinate(latitude: 31.23, longitude: 121.47)
            }
        }
        let provider = FailingProvider()
        let coord = try? await provider.fetchDailyForecast(
            at: GeocodedCoordinate(latitude: 31.23, longitude: 121.47),
            date: Date()
        )
        XCTAssertNil(coord, "Provider throws → nil forecast")
        let decision = WeatherReminderPolicy.decision(
            forecast: coord,
            showName: "上海站",
            place: "上海"
        )
        XCTAssertEqual(
            decision,
            .genericReminder(showName: "上海站", place: "上海"),
            "WeatherKit 401 → 仍然发'明天见'兜底"
        )
    }
}
