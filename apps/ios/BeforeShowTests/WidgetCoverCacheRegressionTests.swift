import Foundation
import XCTest
@testable import BeforeShow

final class WidgetCoverCacheRegressionTests: XCTestCase {
    private var tempDirectory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("widget-cover-cache-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        WidgetSnapshotStore.overrideContainerURL = tempDirectory
    }

    override func tearDownWithError() throws {
        WidgetSnapshotStore.overrideContainerURL = nil
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        try super.tearDownWithError()
    }

    func testPruneWithoutCurrentSourceDeletesAllHashedCovers() throws {
        let cachedFiles = [
            "cover-old.jpg",
            "cover-old-la.jpg",
            "cover-old.jpg.source",
        ]
        for filename in cachedFiles {
            try Data("cached".utf8).write(to: tempDirectory.appendingPathComponent(filename))
        }
        let unrelated = tempDirectory.appendingPathComponent("current-show.json")
        try Data("snapshot".utf8).write(to: unrelated)

        WidgetCoverCache.pruneCovers(except: nil)

        for filename in cachedFiles {
            XCTAssertFalse(
                FileManager.default.fileExists(
                    atPath: tempDirectory.appendingPathComponent(filename).path
                ),
                "expected \(filename) to be removed"
            )
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: unrelated.path))
    }

    func testRefreshWithoutSourceDeletesAllHashedCovers() async throws {
        let cachedFiles = [
            "cover-extension.jpg",
            "cover-extension-la.jpg",
            "cover-extension.jpg.source",
        ]
        let directory = try XCTUnwrap(tempDirectory)
        for filename in cachedFiles {
            try Data("cached".utf8).write(to: directory.appendingPathComponent(filename))
        }

        // Widget provider 的无快照路径只调用 refresh(nil),也必须完成完整清理。
        await WidgetCoverCache.refresh(for: nil)

        for filename in cachedFiles {
            XCTAssertFalse(
                FileManager.default.fileExists(
                    atPath: directory.appendingPathComponent(filename).path
                ),
                "expected \(filename) to be removed"
            )
        }
    }

    func testPruneKeepsOnlyCurrentSourceCoverFiles() throws {
        let currentSource = "https://cdn.example.com/current.jpg"
        let previousSource = "https://cdn.example.com/previous.jpg"
        let currentFiles = [
            WidgetCoverCache.filename(for: currentSource),
            WidgetCoverCache.liveActivityFilename(for: currentSource),
            WidgetCoverCache.filename(for: currentSource) + ".source",
        ]
        let previousFiles = [
            WidgetCoverCache.filename(for: previousSource),
            WidgetCoverCache.liveActivityFilename(for: previousSource),
            WidgetCoverCache.filename(for: previousSource) + ".source",
        ]

        for filename in currentFiles + previousFiles {
            try Data("cached".utf8).write(to: tempDirectory.appendingPathComponent(filename))
        }

        WidgetCoverCache.pruneCovers(except: currentSource)

        for filename in currentFiles {
            XCTAssertTrue(
                FileManager.default.fileExists(
                    atPath: tempDirectory.appendingPathComponent(filename).path
                ),
                "expected \(filename) to be kept"
            )
        }
        for filename in previousFiles {
            XCTAssertFalse(
                FileManager.default.fileExists(
                    atPath: tempDirectory.appendingPathComponent(filename).path
                ),
                "expected \(filename) to be removed"
            )
        }
    }
}
