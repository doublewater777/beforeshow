import AppIntents
import Foundation

// MARK: - Listening Intent Bridge
// 跨进程/跨 target 意图代理。当小组件点击带有 AudioPlaybackIntent 的按键时，
// iOS 系统在主 App 进程中唤起 perform()，由 handler 接管真实音频播放控制。

@MainActor
public protocol ListeningIntentHandling: AnyObject {
    func togglePlayPause() async
}

public enum ListeningIntentBridge {
    @MainActor public static var handler: (any ListeningIntentHandling)?

    @MainActor
    public static func performTogglePlayPause() async {
        if let handler {
            await handler.togglePlayPause()
        }
    }
}

// MARK: - Audio Playback Intents

public struct ToggleListeningPlaybackIntent: AudioPlaybackIntent {
    public static let title: LocalizedStringResource = "播放或暂停"
    public static let description = IntentDescription("在小组件上直接控制听模块播放或暂停")

    public init() {}

    @MainActor
    public func perform() async throws -> some IntentResult {
        await ListeningIntentBridge.performTogglePlayPause()
        return .result()
    }
}
