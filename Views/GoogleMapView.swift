import GoogleMaps
import SwiftUI

struct GoogleMapView: UIViewRepresentable {
    let place: SelectedPlace

    func makeUIView(context: Context) -> GMSMapView {
        let mapView = GMSMapView(frame: .zero)
        mapView.settings.compassButton = true
        mapView.settings.myLocationButton = false
        return mapView
    }

    func updateUIView(_ mapView: GMSMapView, context: Context) {
        let coordinate = CLLocationCoordinate2D(latitude: place.latitude, longitude: place.longitude)
        mapView.camera = GMSCameraPosition.camera(withTarget: coordinate, zoom: 13)
        mapView.clear()
        let marker = GMSMarker(position: coordinate)
        marker.title = place.name
        marker.map = mapView
    }
}
