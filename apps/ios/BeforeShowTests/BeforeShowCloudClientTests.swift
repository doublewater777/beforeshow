import XCTest
@testable import BeforeShow

final class BeforeShowCloudClientTests: XCTestCase {
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
            client.url(path: "generate").absoluteString,
            "https://beforeshow-d2g0gv0zz4cc249dc-1312569550.ap-shanghai.app.tcloudbase.com/generate"
        )
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

        let data = try await client.postJSON(path: "generate", body: Body(hello: "world"))
        XCTAssertEqual(String(data: data, encoding: .utf8), #"{"ok":true}"#)

        let request = try await session.lastRequest()
        XCTAssertEqual(request?.url?.absoluteString, "https://example.com/generate")
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
            _ = try await client.postJSON(path: "generate", body: Body(hello: "x"))
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
}
