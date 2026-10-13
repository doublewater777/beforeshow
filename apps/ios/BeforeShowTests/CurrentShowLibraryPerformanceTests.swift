import Foundation
import SwiftData
import SwiftUI
import UIKit
import XCTest
@testable import BeforeShow

private final class LibraryCoverProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var paths: Set<String> = []

    static var requestedPaths: Set<String> {
        lock.withLock { paths }
    }

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "library-performance.test"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else { return }
        Self.lock.withLock { _ = Self.paths.insert(url.path) }
        client?.urlProtocol(self, didReceive: URLResponse(url: url, mimeType: "image/png", expectedContentLength: 0, textEncodingName: nil), cacheStoragePolicy: .notAllowed)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@MainActor
final class CurrentShowLibraryPerformanceTests: XCTestCase {
    func testLargeLibraryDefersOffscreenCoversAndLoadsThemAfterScrolling() async throws {
        try await verifyLargeLibrary(layout: .list)
    }

    func testLargeCoverGridDefersOffscreenCoversAndLoadsThemAfterScrolling() async throws {
        try await verifyLargeLibrary(layout: .covers)
    }

    private func verifyLargeLibrary(layout: CurrentShowLibraryLayout) async throws {
        URLProtocol.registerClass(LibraryCoverProtocol.self)
        defer { URLProtocol.unregisterClass(LibraryCoverProtocol.self) }
        let defaults = UserDefaults.standard
        let previousLayout = defaults.object(forKey: CurrentShowLibraryLayout.storageKey)
        defaults.set(layout.rawValue, forKey: CurrentShowLibraryLayout.storageKey)
        defer { defaults.set(previousLayout, forKey: CurrentShowLibraryLayout.storageKey) }
        let container = try ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let prefix = "/\(UUID().uuidString)"
        let start = Date().addingTimeInterval(86400 * 30)
        var lastShow: Show?
        for index in 0..<150 {
            let date = start.addingTimeInterval(Double(index) * 86400)
            let show = try Show(
                name: "Library Show \(index)", date: date, startTime: date,
                coverImageURL: "https://library-performance.test\(prefix)/\(index)"
            )
            container.mainContext.insert(show)
            lastShow = show
        }
        try container.mainContext.save()
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previousWindow = scene.keyWindow
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 393, height: 700)
        let host = UIHostingController(rootView: NavigationStack {
            CurrentShowLibraryManagementView()
        }.modelContainer(container))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
            previousWindow?.makeKey()
        }
        host.view.layoutIfNeeded()
        try await Task.sleep(for: .seconds(1))
        let initial = LibraryCoverProtocol.requestedPaths.filter { $0.hasPrefix(prefix) }
        print("Library \(layout.rawValue) initial cover requests: \(initial.count) of 150")
        XCTAssertTrue(initial.contains("\(prefix)/0"))
        XCTAssertLessThan(initial.count, 75, "Opening the library must defer offscreen cover work")
        XCTAssertFalse(initial.contains("\(prefix)/149"))
        func scrollViews(in view: UIView) -> [UIScrollView] {
            ((view as? UIScrollView).map { [$0] } ?? [])
                + view.subviews.flatMap { scrollViews(in: $0) }
        }
        let scroll = try XCTUnwrap(scrollViews(in: host.view).first { $0.contentSize.height > $0.bounds.height + 500 })
        // Lazy layouts refine their content extent as rows enter the viewport.
        for _ in 0..<8 {
            scroll.setContentOffset(CGPoint(x: 0, y: scroll.contentSize.height - scroll.bounds.height), animated: false)
            try await Task.sleep(for: .milliseconds(150))
            if LibraryCoverProtocol.requestedPaths.contains("\(prefix)/149") { break }
        }
        XCTAssertTrue(LibraryCoverProtocol.requestedPaths.contains("\(prefix)/149"), "Scrolling must load the final show cover")
        try XCTUnwrap(lastShow).coverImageURL = "https://library-performance.test\(prefix)/updated"
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertTrue(LibraryCoverProtocol.requestedPaths.contains("\(prefix)/updated"), "Visible rows must observe cover edits")
    }
}
