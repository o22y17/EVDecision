import CoreLocation
import Foundation

enum LocationServiceFailure: Error, Equatable, LocalizedError {
    case permissionDenied
    case unavailable
    var errorDescription: String? {
        switch self {
        case .permissionDenied: return "Location access is off. You can still get a basic estimate without it."
        case .unavailable: return "Your current location is unavailable. You can still get a basic estimate."
        }
    }
}

@MainActor
final class LocationService: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var authorizationStatus: CLAuthorizationStatus
    @Published private(set) var isLoading = false
    private let manager = CLLocationManager()
    private var authorizationContinuation: CheckedContinuation<Void, Error>?
    private var locationContinuation: CheckedContinuation<CLLocationCoordinate2D, Error>?

    override init() {
        authorizationStatus = manager.authorizationStatus
        super.init()
        manager.delegate = self
    }

    func currentCoordinate() async throws -> CLLocationCoordinate2D {
        guard CLLocationManager.locationServicesEnabled() else { throw LocationServiceFailure.unavailable }
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
            try await withCheckedThrowingContinuation { continuation in authorizationContinuation = continuation }
        }
        guard manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways else { throw LocationServiceFailure.permissionDenied }
        isLoading = true
        defer { isLoading = false }
        return try await withCheckedThrowingContinuation { continuation in
            locationContinuation = continuation
            manager.requestLocation()
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            authorizationStatus = status
            switch status {
            case .authorizedWhenInUse, .authorizedAlways:
                authorizationContinuation?.resume(); authorizationContinuation = nil
            case .denied, .restricted:
                authorizationContinuation?.resume(throwing: LocationServiceFailure.permissionDenied); authorizationContinuation = nil
            default: break
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let coordinate = locations.last?.coordinate else { return }
        Task { @MainActor in
            locationContinuation?.resume(returning: coordinate); locationContinuation = nil
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            locationContinuation?.resume(throwing: LocationServiceFailure.unavailable); locationContinuation = nil
        }
    }
}
