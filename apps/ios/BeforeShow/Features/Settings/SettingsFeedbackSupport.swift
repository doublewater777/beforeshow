import Foundation
import SwiftUI
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
    case messageTooLong
}

struct FeedbackPayloadBuilder {
    static let maximumMessageLength = 2_000

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

    static func messageLength(_ message: String) -> Int {
        message.unicodeScalars.count
    }

    func build(from draft: FeedbackDraft) throws -> FeedbackPayload {
        let trimmedMessage = draft.message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedMessage.isEmpty else {
            throw FeedbackValidationError.emptyMessage
        }
        guard Self.messageLength(draft.message) <= Self.maximumMessageLength else {
            throw FeedbackValidationError.messageTooLong
        }

        return FeedbackPayload(
            message: trimmedMessage,
            diagnostics: diagnosticsProvider()
        )
    }
}

enum FeedbackSubmissionError: Error, Equatable {
    case networkFailure
    case messageTooLong
    case rateLimited
    case rejected
}

struct RemoteFeedbackSubmissionService {
    var client: BeforeShowCloudClient

    func submit(_ payload: FeedbackPayload) async throws {
        let data: Data
        do {
            data = try await client.postJSON(
                path: "submitFeedback",
                body: RequestBody(
                    appInstanceId: client.credentials.appInstanceId,
                    appSignature: client.credentials.appSignature,
                    message: payload.message,
                    appVersion: payload.diagnostics.appVersion,
                    osVersion: payload.diagnostics.osVersion
                )
            )
        } catch {
            throw FeedbackSubmissionError.networkFailure
        }

        guard let response = try? JSONDecoder().decode(Response.self, from: data) else {
            throw FeedbackSubmissionError.rejected
        }
        guard response.ok else {
            switch response.error?.code {
            case "MESSAGE_TOO_LONG":
                throw FeedbackSubmissionError.messageTooLong
            case "RATE_LIMITED":
                throw FeedbackSubmissionError.rateLimited
            default:
                throw FeedbackSubmissionError.rejected
            }
        }
    }

    private struct RequestBody: Encodable {
        let appInstanceId: String
        let appSignature: String
        let message: String
        let appVersion: String
        let osVersion: String
    }

    private struct Response: Decodable {
        let ok: Bool
        let error: BackendError?
    }

    private struct BackendError: Decodable {
        let code: String
    }
}

enum FeedbackShakePresentationPolicy {
    static func shouldPresent(
        isAppReady: Bool,
        isFeedbackPresented: Bool,
        hasPresentedModal: Bool
    ) -> Bool {
        isAppReady && !isFeedbackPresented && !hasPresentedModal
    }
}

@MainActor
enum FeedbackShakePresentationState {
    static var hasPresentedModal: Bool {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }),
              let root = scene.windows.first(where: \.isKeyWindow)?.rootViewController else {
            return true
        }
        return root.presentedViewController != nil
    }
}

struct FeedbackShakeResponder: UIViewRepresentable {
    let isArmed: Bool
    let onShake: @MainActor () -> Void

    func makeUIView(context: Context) -> FeedbackShakeResponderView {
        let view = FeedbackShakeResponderView()
        view.onShake = onShake
        view.setArmed(isArmed)
        return view
    }

    func updateUIView(_ uiView: FeedbackShakeResponderView, context: Context) {
        uiView.onShake = onShake
        uiView.setArmed(isArmed)
    }
}

@MainActor
final class FeedbackShakeResponderView: UIView {
    var onShake: @MainActor () -> Void = {}
    private var isArmed = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        observeKeyboard()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        observeKeyboard()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override var canBecomeFirstResponder: Bool { isArmed }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        rearmIfNeeded()
    }

    override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        super.motionEnded(motion, with: event)
        guard isArmed, motion == .motionShake else { return }
        onShake()
    }

    func setArmed(_ armed: Bool) {
        guard isArmed != armed else { return }
        isArmed = armed
        if armed {
            rearmIfNeeded()
        } else if isFirstResponder {
            resignFirstResponder()
        }
    }

    private func observeKeyboard() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardDidHide),
            name: UIResponder.keyboardDidHideNotification,
            object: nil
        )
    }

    @objc
    private func keyboardDidHide() {
        rearmIfNeeded()
    }

    private func rearmIfNeeded() {
        guard isArmed, window != nil, !isFirstResponder else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isArmed, self.window != nil, !self.isFirstResponder else { return }
            self.becomeFirstResponder()
        }
    }
}
