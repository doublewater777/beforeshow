import Network
import UIKit
import XCTest
@testable import BeforeShow

final class WidgetArtworkPreparationTests: XCTestCase {
    func testAppCachedOriginalPreparesBothSharedSizesWithoutNetwork() async throws {
        let container = try makeContainer()
        defer { removeContainer(container) }
        let source = URL(string: "https://artwork.invalid/\(UUID()).jpg")!
        let diskCache = ShowCoverDiskCache.application
        diskCache.store(imageData(), for: source)
        defer {
            try? FileManager.default.removeItem(at: diskCache.directoryURL.appendingPathComponent(
                WidgetCoverCache.filename(for: source.absoluteString)
            ))
        }

        await WidgetArtworkPreparation.prepareCached(sources: [source.absoluteString])

        let widgetPath = try XCTUnwrap(WidgetCoverCache.cachedCoverPath(matching: source.absoluteString))
        let widget = try XCTUnwrap(UIImage(contentsOfFile: widgetPath)?.cgImage)
        let filename = try XCTUnwrap(WidgetCoverCache.freshLiveActivityCoverFilename(for: source.absoluteString))
        let live = try XCTUnwrap(UIImage(contentsOfFile: container.appendingPathComponent(filename).path)?.cgImage)
        XCTAssertEqual(max(widget.width, widget.height), 400)
        XCTAssertEqual(max(live.width, live.height), 120)
    }

    func testReadyArtworkIsPublishedWhileAnotherDownloadIsStillWaiting() async throws {
        let container = try makeContainer()
        defer { removeContainer(container) }
        let server = try await ArtworkHTTPServer(data: imageData())
        defer { server.stop() }
        let slow = server.url(path: "a-slow.jpg").absoluteString
        let fast = server.url(path: "z-fast.jpg").absoluteString
        let fastPublished = expectation(description: "fast image published before slow response")
        let slowPublished = expectation(description: "slow image published after release")
        let work = Task {
            await WidgetArtworkPreparation.refresh(sources: [slow, fast]) { source in
                if source == fast, WidgetCoverCache.cachedCoverPath(matching: fast) != nil,
                   WidgetCoverCache.cachedCoverPath(matching: slow) == nil {
                    fastPublished.fulfill()
                }
                if source == slow, WidgetCoverCache.cachedCoverPath(matching: slow) != nil {
                    slowPublished.fulfill()
                }
            }
        }
        await fulfillment(of: [fastPublished], timeout: 3)
        server.releaseSlowResponse()
        await fulfillment(of: [slowPublished], timeout: 3)
        await work.value
        XCTAssertNotNil(WidgetCoverCache.cachedCoverPath(matching: fast))
        XCTAssertNotNil(WidgetCoverCache.cachedCoverPath(matching: slow))
    }

    func testPruningCancelsOnlyObsoleteDownloadsBeforeTheyRestoreFiles() async throws {
        let container = try makeContainer()
        defer { removeContainer(container) }
        let started = expectation(description: "obsolete download started")
        let server = try await ArtworkHTTPServer(data: imageData(), slowStarted: started)
        defer { server.stop() }
        let retainedStarted = expectation(description: "retained download started")
        let retainedServer = try await ArtworkHTTPServer(data: imageData(), slowStarted: retainedStarted)
        defer { retainedServer.stop() }
        let source = server.url(path: "a-slow.jpg").absoluteString
        let retained = retainedServer.url(path: "a-slow.jpg").absoluteString
        let download = Task { await WidgetCoverCache.refresh(for: source) }
        let retainedDownload = Task { await WidgetCoverCache.refresh(for: retained) }
        await fulfillment(of: [started, retainedStarted], timeout: 3)

        // Listening can switch artwork after the show's retained set was captured.
        WidgetListeningStore.write(WidgetListeningSnapshot(
            showID: nil, showName: "测试现场", artistName: nil, discTitle: nil,
            trackTitle: nil, coverImageURL: retained, trackCount: nil,
            isPlaying: true, generatedAt: .now
        ))
        await WidgetCoverCache.pruneCovers(keeping: [])
        server.releaseSlowResponse()
        retainedServer.releaseSlowResponse()
        await download.value
        await retainedDownload.value

        XCTAssertNil(WidgetCoverCache.cachedCoverPath(matching: source))
        XCTAssertNil(WidgetCoverCache.freshLiveActivityCoverFilename(for: source))
        XCTAssertNotNil(WidgetCoverCache.cachedCoverPath(matching: retained))
        await WidgetCoverCache.refresh(for: nil)
        XCTAssertNotNil(WidgetCoverCache.cachedCoverPath(matching: retained), "a surface without artwork must not clear another surface's image")
    }

    private func makeContainer() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        WidgetSnapshotStore.overrideContainerURL = url
        return url
    }

    private func removeContainer(_ url: URL) {
        WidgetSnapshotStore.overrideContainerURL = nil
        try? FileManager.default.removeItem(at: url)
    }

    private func imageData() -> Data {
        UIGraphicsImageRenderer(size: CGSize(width: 600, height: 800)).jpegData(withCompressionQuality: 0.9) { context in
            UIColor.orange.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 600, height: 800))
        }
    }
}

/// A real HTTP response gate exercises concurrent downloads and shared cache writes.
private final class ArtworkHTTPServer: @unchecked Sendable {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "WidgetArtworkHTTPServer")
    private let data: Data
    private let slowStarted: XCTestExpectation?
    private var slowConnection: NWConnection?
    private var released = false
    private var connections: [NWConnection] = []

    init(data: Data, slowStarted: XCTestExpectation? = nil) async throws {
        self.data = data
        self.slowStarted = slowStarted
        listener = try NWListener(using: .tcp, on: .any)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            listener.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    self?.listener.stateUpdateHandler = nil
                    continuation.resume()
                case .failed(let error): continuation.resume(throwing: error)
                default: break
                }
            }
            listener.newConnectionHandler = { [weak self] connection in self?.receive(connection) }
            listener.start(queue: queue)
        }
    }

    func url(path: String) -> URL {
        URL(string: "http://127.0.0.1:\(listener.port!.rawValue)/\(path)")!
    }

    func releaseSlowResponse() {
        queue.async { [self] in
            released = true
            if let slowConnection { respond(slowConnection) }
        }
    }

    func stop() {
        queue.sync {
            listener.cancel()
            connections.forEach { $0.cancel() }
        }
    }

    private func receive(_ connection: NWConnection) {
        connections.append(connection)
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] bytes, _, _, _ in
            guard let self, let bytes else { return }
            if String(decoding: bytes, as: UTF8.self).contains("/a-slow.jpg"), !released {
                slowConnection = connection
                slowStarted?.fulfill()
            } else {
                respond(connection)
            }
        }
    }

    private func respond(_ connection: NWConnection) {
        var response = Data("HTTP/1.1 200 OK\r\nContent-Type: image/jpeg\r\nContent-Length: \(data.count)\r\nConnection: close\r\n\r\n".utf8)
        response.append(data)
        connection.send(content: response, completion: .contentProcessed { _ in connection.cancel() })
    }
}
