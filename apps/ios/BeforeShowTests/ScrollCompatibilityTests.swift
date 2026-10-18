import SwiftUI
import UIKit
import XCTest
@testable import BeforeShow

@MainActor
final class ScrollCompatibilityTests: XCTestCase {
    func testNestedScrollsReportTheirOwnOffsetsAndReturnToTimelinePosition() async throws {
        let vertical = BSScrollController()
        let horizontal = BSScrollController()
        var verticalOffset: CGFloat = 0
        var horizontalOffset: CGFloat = 0
        let root = ScrollView(.horizontal) {
            VStack(spacing: 0) {
                Text("Stages").frame(height: 40)
                ScrollView(.vertical) {
                    Color.clear.frame(width: 1_200, height: 2_000)
                        .background(BSScrollObservation(enclosing: true, controller: vertical) {
                            verticalOffset = $0.y
                        })
                }
                .frame(width: 1_200, height: 300)
            }
            .background(BSScrollObservation(enclosing: true, controller: horizontal) {
                horizontalOffset = $0.x
            })
        }
        let host = UIHostingController(rootView: root)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 500))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        host.view.layoutIfNeeded()
        try await waitUntil { vertical.scrollView != nil && horizontal.scrollView != nil }
        XCTAssertFalse(vertical.scrollView === horizontal.scrollView)

        vertical.scrollTo(y: 700)
        try await waitUntil { abs(verticalOffset - 700) < 1 }
        XCTAssertEqual(horizontalOffset, 0, accuracy: 1)
        horizontal.scrollView?.setContentOffset(CGPoint(x: 200, y: 0), animated: false)
        try await waitUntil { abs(horizontalOffset - 200) < 1 }
        XCTAssertEqual(verticalOffset, 700, accuracy: 1)

        vertical.scrollTo(y: -100)
        try await waitUntil { abs(verticalOffset) < 1 }
    }
}
