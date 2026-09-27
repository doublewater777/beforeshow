import Foundation
import UIKit

struct FeedbackDiagnostics: Equatable {
    let appVersion: String
    let osVersion: String
}

struct FeedbackDraft: Equatable {
    var message: String
}

struct FeedbackPayload: Equatable {
    let message: String
    let diagnostics: FeedbackDiagnostics
}

enum FeedbackValidationError: Error, Equatable {
    case emptyMessage
}

struct FeedbackPayloadBuilder {
    var diagnosticsProvider: () -> FeedbackDiagnostics

    init(diagnosticsProvider: @escaping () -> FeedbackDiagnostics = {
        FeedbackDiagnostics(
            appVersion: AppVersionInformation.current.marketingVersion,
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString
        )
    }) {
        self.diagnosticsProvider = diagnosticsProvider
    }

    init(appVersion: AppVersionInformation, osVersion: String) {
        self.init {
            FeedbackDiagnostics(appVersion: appVersion.marketingVersion, osVersion: osVersion)
        }
    }

    func build(from draft: FeedbackDraft) throws -> FeedbackPayload {
        let trimmedMessage = draft.message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedMessage.isEmpty else {
            throw FeedbackValidationError.emptyMessage
        }

        return FeedbackPayload(
            message: trimmedMessage,
            diagnostics: diagnosticsProvider()
        )
    }
}

struct FeedbackShareTextBuilder {
    func build(from payload: FeedbackPayload) -> String {
        payload.message + "\n\n——\n\n" +
            BSLocalization.format(
                "App 版本：%@\n系统版本：%@",
                payload.diagnostics.appVersion,
                payload.diagnostics.osVersion
            )
    }
}

/// 真实反馈渠道：`mailto:` 邮件收件人。RELEASE/DEBUG 共用同一地址。
/// `mailto:` 是系统 URL scheme，不需要 `LSApplicationQueriesSchemes` 声明。
enum FeedbackDestination {
    /// 反馈收件邮箱。
    static let address = "return_panyang@163.com"

    static func mailtoURL(prefilledBody: String) -> URL? {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = address
        components.queryItems = [
            URLQueryItem(name: "subject", value: BSLocalization.text("开场前 · 意见反馈")),
            URLQueryItem(name: "body", value: prefilledBody)
        ]
        return components.url
    }
}

/// 调起邮件 app 的薄包装。`@Environment(\.openURL)` 不提供 completion，
/// 改用 UIKit 的 `UIApplication.shared.open(_:options:completionHandler:)` 才能区分
/// "用户接受了跳转" / "未配邮件账户被系统拒绝"。
@MainActor
enum FeedbackMailOpener {
    static func open(url: URL) async -> Bool {
        await withCheckedContinuation { continuation in
            UIApplication.shared.open(url, options: [:]) { accepted in
                continuation.resume(returning: accepted)
            }
        }
    }
}
