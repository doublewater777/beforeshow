import MapKit

extension MKMapItem {
    var bsCoordinate: CLLocationCoordinate2D {
        if #available(iOS 26, *) { return location.coordinate }
        return placemark.coordinate
    }

    var bsFullAddress: String? {
        if #available(iOS 26, *) {
            return addressRepresentations?.fullAddress(includingRegion: false, singleLine: true)
                ?? address?.fullAddress
        }
        return placemark.title
    }

    var bsCityName: String? {
        if #available(iOS 26, *) { return addressRepresentations?.cityName }
        return placemark.locality
    }
}
