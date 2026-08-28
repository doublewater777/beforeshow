import XCTest
import UIKit
import SwiftUI
@testable import BeforeShow

final class ShowCoverLifecycleTests: XCTestCase {
    @MainActor
    func testLocalCoverDisplaysReplacementForSameShowAndUpdatedURL() async throws {
        let fixture = try makeCoverReplacementFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }

        try await assertCoverReplacement(
            show: fixture.show,
            firstSource: .local(fixture.firstURL),
            replacementSource: .local(fixture.replacementURL)
        )
    }

    @MainActor
    func testRemoteCoverDisplaysReplacementForSameShowAndUpdatedURL() async throws {
        let fixture = try makeCoverReplacementFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }

        try await assertCoverReplacement(
            show: fixture.show,
            firstSource: .remote(fixture.firstURL),
            replacementSource: .remote(fixture.replacementURL)
        )
    }

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

    // MARK: - ShowCoverImageCache memory/disk/network split

    func testMemoryImageReturnsNilForUnknownURL() {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ShowCoverImageCacheMemHit-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let cache = ShowCoverImageCache(directoryURL: directory, fetchData: { _ in nil })
        let url = URL(string: "https://example.com/never-loaded.jpg")!

        XCTAssertNil(cache.memoryImage(for: url))
    }

    func testMemoryImageReturnsCachedImageAfterAsyncLoad() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ShowCoverImageCacheMemHit-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let sourceURL = URL(string: "https://example.com/cover.jpg")!
        let sourceImage = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4)).image { context in
            UIColor.systemPink.setFill()
            context.fill(CGRect(origin: .zero, size: CGSize(width: 4, height: 4)))
        }
        let sourceData = try XCTUnwrap(sourceImage.jpegData(compressionQuality: 0.9))

        let cache = ShowCoverImageCache(
            directoryURL: directory,
            fetchData: { _ in sourceData }
        )

        // Cold start: no memory hit.
        XCTAssertNil(cache.memoryImage(for: sourceURL))

        // Async load populates the in-memory cache.
        let loaded = await cache.image(from: sourceURL)
        XCTAssertNotNil(loaded)

        // Subsequent sync lookup hits memory and does not invoke the network.
        let syncHit = cache.memoryImage(for: sourceURL)
        XCTAssertNotNil(syncHit)
    }

    func testImageLoadsFromWidgetCacheWhenDiskAndNetworkMiss() async throws {
        let widgetContainer = FileManager.default.temporaryDirectory
            .appendingPathComponent("WidgetCoverFallbackTests-\(UUID().uuidString)", isDirectory: true)
        let diskDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ShowCoverFallbackTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: widgetContainer, withIntermediateDirectories: true)
        defer {
            WidgetSnapshotStore.overrideContainerURL = nil
            try? FileManager.default.removeItem(at: widgetContainer)
            try? FileManager.default.removeItem(at: diskDirectory)
        }
        WidgetSnapshotStore.overrideContainerURL = widgetContainer

        let sourceURL = URL(string: "https://example.com/widget-fallback.jpg")!
        let source = sourceURL.absoluteString
        let cachedImageData = try XCTUnwrap(makeSolidImage(color: .green).jpegData(compressionQuality: 1))
        let cachedCoverURL = widgetContainer.appendingPathComponent(WidgetCoverCache.filename(for: source))
        let markerURL = cachedCoverURL.appendingPathExtension("source")
        try cachedImageData.write(to: cachedCoverURL)
        try source.write(to: markerURL, atomically: true, encoding: .utf8)

        XCTAssertNotNil(WidgetCoverCache.cachedCoverPath(matching: source))

        let cache = ShowCoverImageCache(directoryURL: diskDirectory, fetchData: { _ in nil })
        let image = await cache.image(from: sourceURL)

        XCTAssertNotNil(image)
    }

    @MainActor
    private func waitForRenderedColor(_ expected: UIColor, in view: UIView) async -> Bool {
        let deadline = Date().addingTimeInterval(2)
        repeat {
            view.layoutIfNeeded()
            if let actual = renderedCenterColor(in: view), colorsMatch(actual, expected) {
                return true
            }
            try? await Task.sleep(nanoseconds: 50_000_000)
        } while Date() < deadline
        return false
    }

    @MainActor
    private func assertCoverReplacement(
        show: Show,
        firstSource: FootprintCoverSource,
        replacementSource: FootprintCoverSource
    ) async throws {
        let firstCover = FootprintCover(
            showID: show.id,
            source: firstSource,
            badge: .memory,
            ordinal: 1,
            variant: 0
        )
        let replacementCover = FootprintCover(
            showID: show.id,
            source: replacementSource,
            badge: .memory,
            ordinal: 1,
            variant: 0
        )

        let windowScene = try XCTUnwrap(
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .first
        )
        let window = UIWindow(windowScene: windowScene)
        window.frame = CGRect(x: 0, y: 0, width: 80, height: 80)
        let host = UIHostingController(
            rootView: FootprintResolvedCoverImage(show: show, cover: firstCover)
        )
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.frame = window.bounds
        host.view.layoutIfNeeded()
        defer { window.isHidden = true }

        let firstRendered = await waitForRenderedColor(.red, in: host.view)
        XCTAssertTrue(firstRendered)

        host.rootView = FootprintResolvedCoverImage(show: show, cover: replacementCover)
        let replacementRendered = await waitForRenderedColor(.blue, in: host.view)
        XCTAssertTrue(replacementRendered)
    }

    private func makeCoverReplacementFixture() throws -> (
        directory: URL,
        firstURL: URL,
        replacementURL: URL,
        show: Show
    ) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FootprintCoverViewTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let firstURL = directory.appendingPathComponent("first.png")
        let replacementURL = directory.appendingPathComponent("replacement.png")
        try XCTUnwrap(makeSolidImage(color: .red).pngData()).write(to: firstURL)
        try XCTUnwrap(makeSolidImage(color: .blue).pngData()).write(to: replacementURL)

        let show = try Show(
            name: "封面替换现场",
            date: Date(timeIntervalSince1970: 1_800_000_000),
            startTime: Date(timeIntervalSince1970: 1_800_000_000)
        )
        return (directory, firstURL, replacementURL, show)
    }

    @MainActor
    private func renderedCenterColor(in view: UIView) -> UIColor? {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(bounds: view.bounds, format: format).image { context in
            view.layer.render(in: context.cgContext)
        }
        guard let cgImage = image.cgImage,
              let data = cgImage.dataProvider?.data,
              let bytes = CFDataGetBytePtr(data) else {
            return nil
        }
        let bytesPerPixel = cgImage.bitsPerPixel / 8
        let x = max(0, min(cgImage.width - 1, cgImage.width / 2))
        let y = max(0, min(cgImage.height - 1, cgImage.height / 2))
        let offset = y * cgImage.bytesPerRow + x * bytesPerPixel
        return UIColor(
            red: CGFloat(bytes[offset + 2]) / 255,
            green: CGFloat(bytes[offset + 1]) / 255,
            blue: CGFloat(bytes[offset]) / 255,
            alpha: CGFloat(bytes[offset + 3]) / 255
        )
    }

    private func colorsMatch(_ lhs: UIColor, _ rhs: UIColor) -> Bool {
        var lhsRed: CGFloat = 0
        var lhsGreen: CGFloat = 0
        var lhsBlue: CGFloat = 0
        var lhsAlpha: CGFloat = 0
        var rhsRed: CGFloat = 0
        var rhsGreen: CGFloat = 0
        var rhsBlue: CGFloat = 0
        var rhsAlpha: CGFloat = 0
        guard lhs.getRed(&lhsRed, green: &lhsGreen, blue: &lhsBlue, alpha: &lhsAlpha),
              rhs.getRed(&rhsRed, green: &rhsGreen, blue: &rhsBlue, alpha: &rhsAlpha) else {
            return false
        }
        return abs(lhsRed - rhsRed) < 0.03
            && abs(lhsGreen - rhsGreen) < 0.03
            && abs(lhsBlue - rhsBlue) < 0.03
            && abs(lhsAlpha - rhsAlpha) < 0.03
    }

    private func makeSolidImage(color: UIColor) -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image { context in
            color.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }
    }
}
