import Foundation
import XCTest
import SwiftData
@testable import BeforeShow

@MainActor
final class ListeningDiscDetailTapPolicyTests: XCTestCase {
    func testDetailTapRequiresStableSeatedDisc() {
        XCTAssertTrue(
            ListeningDiscDetailTapPolicy.canOpen(
                position: .seated,
                isAutomatic: false,
                isReturning: false,
                isCabinetDragging: false,
                lidIsStable: true,
                partsAreMoving: false
            )
        )
        XCTAssertFalse(
            ListeningDiscDetailTapPolicy.canOpen(
                position: .removed,
                isAutomatic: false,
                isReturning: false,
                isCabinetDragging: false,
                lidIsStable: true,
                partsAreMoving: false
            )
        )
        XCTAssertFalse(
            ListeningDiscDetailTapPolicy.canOpen(
                position: .seated,
                isAutomatic: true,
                isReturning: false,
                isCabinetDragging: false,
                lidIsStable: true,
                partsAreMoving: false
            )
        )
        XCTAssertFalse(
            ListeningDiscDetailTapPolicy.canOpen(
                position: .seated,
                isAutomatic: false,
                isReturning: false,
                isCabinetDragging: false,
                lidIsStable: false,
                partsAreMoving: false
            )
        )
        XCTAssertFalse(
            ListeningDiscDetailTapPolicy.canOpen(
                position: .seated,
                isAutomatic: false,
                isReturning: false,
                isCabinetDragging: false,
                lidIsStable: true,
                partsAreMoving: true
            )
        )
    }

    func testDetailTapUsesEightPointMovementLimitAndProjectedDiscEllipse() {
        XCTAssertTrue(ListeningDiscDetailTapPolicy.isIntentionalTap(CGSize(width: 6, height: 5)))
        XCTAssertFalse(ListeningDiscDetailTapPolicy.isIntentionalTap(CGSize(width: 8, height: 1)))

        let center = CGPoint(x: 100, y: 80)
        let size = CGSize(width: 120, height: 60)
        XCTAssertTrue(ListeningDiscDetailTapPolicy.contains(center, center: center, size: size))
        XCTAssertTrue(
            ListeningDiscDetailTapPolicy.contains(
                CGPoint(x: 167, y: 80),
                center: center,
                size: size
            ),
            "The CD hit area should include the agreed eight-point tolerance"
        )
        XCTAssertFalse(
            ListeningDiscDetailTapPolicy.contains(
                CGPoint(x: 169, y: 80),
                center: center,
                size: size
            )
        )
    }
}
