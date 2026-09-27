import Foundation

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

enum FeedbackSubmissionError: Error, Equatable {
    case networkFailure
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

        guard let response = try? JSONDecoder().decode(Response.self, from: data),
              response.ok else {
            throw FeedbackSubmissionError.rejected
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
    }
}
