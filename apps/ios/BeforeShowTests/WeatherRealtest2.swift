import XCTest
import WeatherKit
import CoreLocation
@testable import BeforeShow

/// 验证 simulator 端 `WeatherService.shared.weather(for:)` 真能跑通。
///
/// **当前状态（2026-08-26）**：skip。
///
/// 在 iPhone 17 simulator（iOS 26.5）上持续抛
/// `WeatherDaemon.WDSJWTAuthenticatorServiceListener.Errors Code=2`
/// 即便已：
/// - Apple Developer Portal → App ID `com.doublewaterapps.beforeshow` 勾选 WeatherKit
/// - `BeforeShow.Debug.entitlements` 加 `com.apple.developer.weatherkit: true`
/// - pbxproj Debug 配置加 `ENTITLEMENTS_ALLOWED = YES` + `ENTITLEMENTS_REQUIRED = YES`
///   （Xcode 15+ 默认 `ENTITLEMENTS_ALLOWED=NO` 会把 entitlement 剥掉）
/// - 编译出的 `BeforeShow.app-Simulated.xcent` 已含 `com.apple.developer.weatherkit = true`
/// - 装到 sim 的 app binary `strings` 能找到 `com.apple.developer.weatherkit`
///
/// `Code=2` = Apple 后台 JWT 签发服务对该 App ID 的 WeatherKit 能力未传播过来。
/// Apple 论坛多人反馈这种能力变更需要 30 分钟 ~ 几小时（实测等待 1 小时 + clean
/// reinstall 后仍 Code=2）。
///
/// **要解开此 skip**：
/// 1. 等更久（数小时或隔夜）后再跑本测试
/// 2. 或换真机测试（real device 有真实 provisioning profile，JWT 签发走真链路）
/// 3. 都不行则改用第三方天气 API（如 Open-Meteo）替代 WeatherKit
///
/// 同时 scheduler 的 `fetchAndDecide` 用 try-catch 把所有 WeatherKit 错误
/// 吞掉转 `forecast = nil`，simulator 走兜底分支永远发"明天见"，不会崩。
/// 真正的天气通知能力需要等 #1 或 #2 之一满足才能验证。
final class WeatherRealtest2: XCTestCase {
    func testWeatherKitAfterCapabilityEnabled() async throws {
        try XCTSkipIf(
            true,
            "Simulator WeatherKit 抛 WDSJWTAuthenticatorServiceListener Code=2 — Apple 后台能力传播未完成。真机或等更久后再验证。"
        )
    }
}
