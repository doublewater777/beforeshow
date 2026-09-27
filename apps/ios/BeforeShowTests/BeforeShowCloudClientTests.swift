import XCTest
@testable import BeforeShow

final class BeforeShowCloudClientTests: XCTestCase {
    @MainActor
    func testProductionConfigUsesSingleHostAndSignature() {
        let client = BeforeShowCloudClient.production(
            session: CapturingCloudURLSession(data: Data(), statusCode: 200)
        )
        XCTAssertEqual(
            client.rootURL.absoluteString,
            "https://beforeshow-d2g0gv0zz4cc249dc-1312569550.ap-shanghai.app.tcloudbase.com"
        )
        XCTAssertEqual(client.credentials.appSignature, "beforeshow-app-signature-v1")
        XCTAssertFalse(client.credentials.appInstanceId.isEmpty)
        XCTAssertEqual(
            client.url(path: "/parseShowLink").absoluteString,
            "https://beforeshow-d2g0gv0zz4cc249dc-1312569550.ap-shanghai.app.tcloudbase.com/parseShowLink"
        )
    }

    func testPostJSONPostsToPathAndReturnsBodyOnSuccess() async throws {
        let session = CapturingCloudURLSession(
            data: #"{"ok":true}"#.data(using: .utf8)!,
            statusCode: 200
        )
        let client = BeforeShowCloudClient(
            rootURL: URL(string: "https://example.com")!,
            credentials: BeforeShowAppCredentials(appInstanceId: "id", appSignature: "sig"),
            session: session
        )

        struct Body: Encodable {
            let hello: String
        }

        let data = try await client.postJSON(path: "parseShowLink", body: Body(hello: "world"))
        XCTAssertEqual(String(data: data, encoding: .utf8), #"{"ok":true}"#)

        let request = await session.lastRequest()
        XCTAssertEqual(request?.url?.absoluteString, "https://example.com/parseShowLink")
        XCTAssertEqual(request?.httpMethod, "POST")
        XCTAssertEqual(request?.value(forHTTPHeaderField: "Content-Type"), "application/json")
    }

    func testPostJSONThrowsOnNonSuccessStatus() async {
        let client = BeforeShowCloudClient(
            rootURL: URL(string: "https://example.com")!,
            credentials: BeforeShowAppCredentials(appInstanceId: "id", appSignature: "sig"),
            session: CapturingCloudURLSession(data: Data(), statusCode: 500)
        )

        struct Body: Encodable {
            let hello: String
        }

        do {
            _ = try await client.postJSON(path: "parseShowLink", body: Body(hello: "x"))
            XCTFail("expected networkFailure")
        } catch let error as BeforeShowCloudClientError {
            XCTAssertEqual(error, .networkFailure)
        } catch {
            XCTFail("unexpected \(error)")
        }
    }
}

private actor CapturingCloudURLSession: URLSessionProtocol {
    var data: Data
    var statusCode: Int
    private var last: URLRequest?

    init(data: Data, statusCode: Int) {
        self.data = data
        self.statusCode = statusCode
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        last = request
        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "https://example.com")!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
        return (data, response)
    }

    func lastRequest() -> URLRequest? { last }

    func testFeedbackSubmissionPostsOnlyMessageAndMinimalDiagnostics() async throws {
        let session = CapturingCloudURLSession(
            data: #"{"ok":true,"feedbackId":"feedback-id"}"#.data(using: .utf8)!,
            statusCode: 200
        )
        let client = BeforeShowCloudClient(
            rootURL: URL(string: "https://example.com")!,
            credentials: BeforeShowAppCredentials(
                appInstanceId: "instance-id",
                appSignature: "app-signature"
            ),
            session: session
        )
        let service = RemoteFeedbackSubmissionService(client: client)

        try await service.submit(FeedbackPayload(
            message: "希望这里更顺手",
            diagnostics: FeedbackDiagnostics(appVersion: "1.0", osVersion: "iOS 26.0")
        ))

        let capturedRequest = await session.lastRequest()
        let request = try XCTUnwrap(capturedRequest)
        XCTAssertEqual(request.url?.absoluteString, "https://example.com/submitFeedback")

        let bodyData = try XCTUnwrap(request.httpBody)
        let body = try XCTUnwrap(
            JSONSerialization.jsonObject(with: bodyData) as? [String: String]
        )
        XCTAssertEqual(
            Set(body.keys),
            Set(["appInstanceId", "appSignature", "message", "appVersion", "osVersion"])
        )
        XCTAssertEqual(body["appInstanceId"], "instance-id")
        XCTAssertEqual(body["appSignature"], "app-signature")
        XCTAssertEqual(body["message"], "希望这里更顺手")
        XCTAssertEqual(body["appVersion"], "1.0")
        XCTAssertEqual(body["osVersion"], "iOS 26.0")
    }

    func testFeedbackSubmissionRejectsBackendFailure() async {
        let session = CapturingCloudURLSession(
            data: #"{"ok":false,"error":{"code":"STORE_FAILED"}}"#.data(using: .utf8)!,
            statusCode: 200
        )
        let client = BeforeShowCloudClient(
            rootURL: URL(string: "https://example.com")!,
            credentials: BeforeShowAppCredentials(appInstanceId: "id", appSignature: "sig"),
            session: session
        )

        do {
            try await RemoteFeedbackSubmissionService(client: client).submit(FeedbackPayload(
                message: "设置页卡住",
                diagnostics: FeedbackDiagnostics(appVersion: "1.0", osVersion: "iOS 26.0")
            ))
            XCTFail("expected rejected")
        } catch let error as FeedbackSubmissionError {
            XCTAssertEqual(error, .rejected)
        } catch {
            XCTFail("unexpected \(error)")
        }
    }

}
