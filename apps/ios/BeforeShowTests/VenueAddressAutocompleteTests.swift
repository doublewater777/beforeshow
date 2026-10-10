import MapKit
import XCTest
@testable import BeforeShow

final class VenueAddressAutocompleteTests: XCTestCase {
    func testAddressSuggestionFillTextPrefersCompleteStreetAddress() {
        let suggestion = AddressSuggestion(
            id: "1",
            name: "MAO Livehouse",
            address: "杭州市上城区中山南路77号",
            district: "浙江省杭州市上城区"
        )

        XCTAssertEqual(suggestion.fillText, "杭州市上城区中山南路77号")
    }

    func testAddressSuggestionFillTextCombinesDistrictAndStreet() {
        let suggestion = AddressSuggestion(
            id: "2",
            name: "MAO Livehouse",
            address: "中山南路77号",
            district: "浙江省杭州市上城区"
        )

        XCTAssertEqual(suggestion.fillText, "浙江省杭州市上城区中山南路77号")
    }

    func testMapKitAddressFormatterUsesStreetAndDistrict() {
        let formatted = MapKitAddressFormatter.displayAddress(
            name: "MAO Livehouse",
            address: "中山南路77号",
            district: "浙江省杭州市上城区"
        )

        XCTAssertEqual(formatted, "浙江省杭州市上城区中山南路77号")
    }

    func testMapItemAddressKeepsFullAddressInsteadOfShortLabel() throws {
        let address = try XCTUnwrap(MKAddress(
            fullAddress: "1 Apple Park Way, Cupertino, CA 95014",
            shortAddress: "Apple Park"
        ))
        let mapItem = MKMapItem(
            location: CLLocation(latitude: 37.3349, longitude: -122.0090),
            address: address
        )
        mapItem.name = "Apple Park"

        XCTAssertEqual(
            MapKitAddressFormatter.displayAddress(for: mapItem),
            "1 Apple Park Way, Cupertino, CA 95014"
        )
    }

    func testVenueAddressSearchPolicyRejectsStaleOrCanceledResults() {
        XCTAssertTrue(
            VenueAddressSearchPolicy.shouldApplyResults(
                revision: 2,
                currentRevision: 2,
                taskIsCancelled: false
            )
        )
        XCTAssertFalse(
            VenueAddressSearchPolicy.shouldApplyResults(
                revision: 1,
                currentRevision: 2,
                taskIsCancelled: false
            )
        )
        XCTAssertFalse(
            VenueAddressSearchPolicy.shouldApplyResults(
                revision: 2,
                currentRevision: 2,
                taskIsCancelled: true
            )
        )
    }
}
