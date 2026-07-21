import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// App-instance credentials for CloudBase functions (accountless).
struct BeforeShowAppCredentials: Equatable, Sendable {
    var appInstanceId: String
    var appSignature: String
}

enum BeforeShowCloudClientError: Error, Equatable {
    case invalidRootURL
    case networkFailure
    case streamFailure(String)
}

/// One Server-Sent Event from `/generate` when `stream: true`.
struct BeforeShowSSEEvent: Equatable, Sendable {
    var event: String
    var data: Data
}

/// Single CloudBase HTTP seam for iOS.
///
/// Owns root host, app credentials, and POST JSON transport.
/// Feature remotes (链接解析 / 歌单猜想 / 去程草稿) map domain payloads only.
///
/// Deletion test: without this client, baseURL + signature + HTTP envelope scatter
/// across CandidateSongsSession, AddShowFlowViews, and remote generation services.
struct BeforeShowCloudClient: Sendable {
    var rootURL: URL
    var credentials: BeforeShowAppCredentials
    var session: URLSessionProtocol
    /// Test seam for SSE; when set, used instead of live `URLSession.bytes`.
    var eventStreamOverride: (@Sendable (URLRequest) -> AsyncThrowingStream<BeforeShowSSEEvent, Error>)? = nil

    static let productionRootURL = URL(
        string: "https://beforeshow-d2g0gv0zz4cc249dc-1312569550.ap-shanghai.app.tcloudbase.com"
    )!

    static let productionAppSignature = "beforeshow-app-signature-v1"

    static func productionAppInstanceId() -> String {
        #if canImport(UIKit)
        UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
        #else
        UUID().uuidString
        #endif
    }

    static func production(session: URLSessionProtocol = URLSession.shared) -> BeforeShowCloudClient {
        BeforeShowCloudClient(
            rootURL: productionRootURL,
            credentials: BeforeShowAppCredentials(
                appInstanceId: productionAppInstanceId(),
                appSignature: productionAppSignature
            ),
            session: session,
            eventStreamOverride: nil
        )
    }

    func url(path: String) -> URL {
        let trimmed = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return rootURL.appendingPathComponent(trimmed)
    }

    /// POST JSON body; returns response body on HTTP 2xx.
    func postJSON(path: String, body: some Encodable) async throws -> Data {
        var request = URLRequest(url: url(path: path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 90
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw BeforeShowCloudClientError.networkFailure
        }
        return data
    }

    /// POST JSON and consume CloudBase `text/event-stream` (generate `stream: true`).
    func postEventStream(path: String, body: some Encodable) -> AsyncThrowingStream<BeforeShowSSEEvent, Error> {
        let requestURL = url(path: path)
        let encodedBody: Data
        do {
            encodedBody = try JSONEncoder().encode(body)
        } catch {
            return AsyncThrowingStream { $0.finish(throwing: error) }
        }

        var request = URLRequest(url: requestURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 90
        request.httpBody = encodedBody

        if let eventStreamOverride {
            return eventStreamOverride(request)
        }

        let streamRequest = request
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await Self.consumeLiveSSE(request: streamRequest, continuation: continuation)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    private static func consumeLiveSSE(
        request: URLRequest,
        continuation: AsyncThrowingStream<BeforeShowSSEEvent, Error>.Continuation
    ) async throws {
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw BeforeShowCloudClientError.networkFailure
        }

        var lineBuffer = Data()
        var eventName = "message"
        var dataLines: [String] = []

        func flushEvent() {
            guard !dataLines.isEmpty else {
                eventName = "message"
                return
            }
            let payload = dataLines.joined(separator: "\n")
            if let data = payload.data(using: .utf8) {
                continuation.yield(BeforeShowSSEEvent(event: eventName, data: data))
            }
            eventName = "message"
            dataLines = []
        }

        for try await byte in bytes {
            try Task.checkCancellation()
            lineBuffer.append(byte)
            while let newline = lineBuffer.firstIndex(of: 0x0A) {
                var lineData = lineBuffer.subdata(in: lineBuffer.startIndex..<newline)
                lineBuffer.removeSubrange(lineBuffer.startIndex...newline)
                if lineData.last == 0x0D {
                    lineData.removeLast()
                }
                let line = String(data: lineData, encoding: .utf8) ?? ""
                if line.isEmpty {
                    flushEvent()
                    continue
                }
                if line.hasPrefix(":") {
                    continue
                }
                if line.hasPrefix("event:") {
                    eventName = line.dropFirst(6).trimmingCharacters(in: .whitespaces)
                    continue
                }
                if line.hasPrefix("data:") {
                    dataLines.append(line.dropFirst(5).trimmingCharacters(in: .whitespaces))
                }
            }
        }
        flushEvent()
    }
}
