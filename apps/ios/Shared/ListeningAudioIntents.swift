import AppIntents
import Foundation

// MARK: - Listening Intent Bridge
// 跨进程/跨 target 意图代理。小组件按钮带 AudioPlaybackIntent 时，
// 系统在主 App 进程里调用 perform()，由「听」模块执行明确的播放或暂停。

public enum ListeningWidgetCommand: String, Sendable {
    case play
    case pause
}

@MainActor
public protocol ListeningIntentHandling: AnyObject {
    func perform(_ command: ListeningWidgetCommand) async
}

public enum ListeningIntentBridge {
    @MainActor public static var handler: (any ListeningIntentHandling)?

    @MainActor
    public static func perform(_ command: ListeningWidgetCommand) async {
        if let handler {
            await handler.perform(command)
        }
    }
}

// MARK: - Audio Playback Intents

public struct PlayListeningIntent: AudioPlaybackIntent {
    public static let title: LocalizedStringResource = "播放"
    public static let description = IntentDescription("播放听模块当前的唱片")

    public init() {}

    @MainActor
    public func perform() async throws -> some IntentResult {
        await ListeningIntentBridge.perform(.play)
        return .result()
    }
}

public struct PauseListeningIntent: AudioPlaybackIntent {
    public static let title: LocalizedStringResource = "暂停"
    public static let description = IntentDescription("暂停听模块当前的播放")

    public init() {}

    @MainActor
    public func perform() async throws -> some IntentResult {
        await ListeningIntentBridge.perform(.pause)
        return .result()
    }
}
