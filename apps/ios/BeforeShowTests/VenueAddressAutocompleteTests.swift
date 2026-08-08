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
