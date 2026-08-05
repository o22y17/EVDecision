import GooglePlaces
import SwiftUI

struct GooglePlaceAutocompleteView: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    let onPlaceSelected: (SelectedPlace) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIViewController(context: Context) -> GMSAutocompleteViewController {
        let controller = GMSAutocompleteViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: GMSAutocompleteViewController, context: Context) {}

    final class Coordinator: NSObject, GMSAutocompleteViewControllerDelegate {
        private let parent: GooglePlaceAutocompleteView

        init(parent: GooglePlaceAutocompleteView) {
            self.parent = parent
        }

        func viewController(_ viewController: GMSAutocompleteViewController, didAutocompleteWith place: GMSPlace) {
            parent.onPlaceSelected(
                SelectedPlace(
                    name: place.name ?? place.formattedAddress ?? "Selected place",
                    latitude: place.coordinate.latitude,
                    longitude: place.coordinate.longitude
                )
            )
            parent.isPresented = false
        }

        func viewController(_ viewController: GMSAutocompleteViewController, didFailAutocompleteWithError error: Error) {
            parent.isPresented = false
        }

        func wasCancelled(_ viewController: GMSAutocompleteViewController) {
            parent.isPresented = false
        }
    }
}
