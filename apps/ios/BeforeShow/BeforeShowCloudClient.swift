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
            session: session
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
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw BeforeShowCloudClientError.networkFailure
        }
        return data
    }
}
