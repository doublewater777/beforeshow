import XCTest
import UIKit
@testable import BeforeShow

final class ShowCoverLifecycleTests: XCTestCase {
    func testRemoteCoverSurvivesImageCacheRecreationWithoutNetwork() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ShowCoverImageCacheTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let sourceURL = URL(string: "https://example.com/cover.jpg")!
        let sourceImage = UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2)).image { context in
            UIColor.orange.setFill()
            context.fill(CGRect(origin: .zero, size: CGSize(width: 2, height: 2)))
        }
        let sourceData = try XCTUnwrap(sourceImage.jpegData(compressionQuality: 0.9))

        let firstProcess = ShowCoverImageCache(
            directoryURL: directory,
            fetchData: { _ in sourceData }
        )
        let firstImage = await firstProcess.image(from: sourceURL)
        XCTAssertNotNil(firstImage)

        let coldLaunch = ShowCoverImageCache(
            directoryURL: directory,
            fetchData: { _ in nil }
        )
        let coldLaunchImage = await coldLaunch.image(from: sourceURL)
        XCTAssertNotNil(coldLaunchImage)
    }

    func testRegisterRemovesPreviousTempAndTracksNew() {
        var removed: [String] = []
        var lifecycle = ShowCoverLifecycle(remove: { removed.append($0) })

        lifecycle.register(previous: "", new: "old")
        lifecycle.register(previous: "old", new: "new")

        XCTAssertEqual(removed, ["old"])
    }

    func testRegisterLeavesUntrackedPreviousAlone() {
        var removed: [String] = []
        var lifecycle = ShowCoverLifecycle(remove: { removed.append($0) })

        // `previous` was never a temp (e.g. a persistent cover) -> not removed.
        lifecycle.register(previous: "persistent", new: "new")

        XCTAssertEqual(removed, [])
    }

    func testCancelRemovesAllTemps() {
        var removed: [String] = []
        var lifecycle = ShowCoverLifecycle(remove: { removed.append($0) })

        lifecycle.register(previous: "", new: "a")
        lifecycle.register(previous: "", new: "b")
        lifecycle.cancel()

        XCTAssertEqual(Set(removed), ["a", "b"])
    }

    func testFinalizeKeepsKeptURLAndDiscardsOtherTemps() {
        var removed: [String] = []
        var lifecycle = ShowCoverLifecycle(remove: { removed.append($0) })

        lifecycle.register(previous: "", new: "kept")
        lifecycle.register(previous: "", new: "discard")
        lifecycle.finalize(keeping: "kept")

        XCTAssertEqual(removed, ["discard"])
    }

    func testFinalizeWithNilKeptDiscardsAllTemps() {
        var removed: [String] = []
        var lifecycle = ShowCoverLifecycle(remove: { removed.append($0) })

        lifecycle.register(previous: "", new: "a")
        lifecycle.register(previous: "", new: "b")
        lifecycle.finalize(keeping: nil)

        XCTAssertEqual(Set(removed), ["a", "b"])
    }

    /// Edit flow: the original persistent cover is replaced by a temp import.
    /// The temp is kept; the replaced original is discarded.
    func testFinalizeDiscardsReplacedOriginalAndKeepsTemp() {
        var removed: [String] = []
        var lifecycle = ShowCoverLifecycle(remove: { removed.append($0) })

        let originalCoverURL = "original"
        lifecycle.register(previous: "", new: "temp")
        lifecycle.finalize(keeping: "temp", additionalDiscards: [originalCoverURL])

        XCTAssertEqual(Set(removed), ["original"])
    }

    /// Edit flow: original cover is kept (not replaced); only the unused temp is discarded.
    func testFinalizeKeepsOriginalAndDiscardsTemp() {
        var removed: [String] = []
        var lifecycle = ShowCoverLifecycle(remove: { removed.append($0) })

        let originalCoverURL = "original"
        lifecycle.register(previous: "", new: "temp")
        lifecycle.finalize(keeping: originalCoverURL, additionalDiscards: [originalCoverURL])

        XCTAssertEqual(Set(removed), ["temp"])
    }
}
