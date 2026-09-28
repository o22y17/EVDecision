import CoreLocation
import Foundation

protocol RouteService {
    func route(from origin: CLLocationCoordinate2D, to destination: CLLocationCoordinate2D) async -> RouteLookupResult
}

struct GoogleRoutesService: RouteService {
    private let session: URLSession
    private let apiKey: String?

    init(session: URLSession = .shared, apiKey: String? = Bundle.main.object(forInfoDictionaryKey: "GoogleMapsAPIKey") as? String) {
        self.session = session
        self.apiKey = apiKey
    }

    func route(from origin: CLLocationCoordinate2D, to destination: CLLocationCoordinate2D) async -> RouteLookupResult {
        guard let apiKey,
              apiKey.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("AIza"),
              !apiKey.contains("$(") else { return .failure(.apiKeyUnavailable) }
        guard let url = URL(string: "https://routes.googleapis.com/directions/v2:computeRoutes") else { return .failure(.invalidResponse) }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 12
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "X-Goog-Api-Key")
        if let bundleIdentifier = Bundle.main.bundleIdentifier {
            request.setValue(bundleIdentifier, forHTTPHeaderField: "X-Ios-Bundle-Identifier")
        }
        request.setValue("routes.duration,routes.distanceMeters", forHTTPHeaderField: "X-Goog-FieldMask")
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "origin": waypoint(origin),
            "destination": waypoint(destination),
            "travelMode": "DRIVE",
            "routingPreference": "TRAFFIC_AWARE",
            "units": "METRIC"
        ])
        guard request.httpBody != nil else { return .failure(.invalidResponse) }

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else { return .failure(.invalidResponse) }
            guard httpResponse.statusCode == 200 else {
                switch httpResponse.statusCode {
                case 401, 403: return .failure(.accessDenied)
                case 404: return .failure(.noRouteFound)
                case 429: return .failure(.quotaExceeded)
                default: return .failure(.networkUnavailable)
                }
            }
            return decode(data)
        } catch let error as URLError where error.code == .timedOut {
            return .failure(.timedOut)
        } catch {
            return .failure(.networkUnavailable)
        }
    }

    private func waypoint(_ coordinate: CLLocationCoordinate2D) -> [String: Any] {
        ["location": ["latLng": ["latitude": coordinate.latitude, "longitude": coordinate.longitude]]]
    }

    private func decode(_ data: Data) -> RouteLookupResult {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let routes = object["routes"] as? [[String: Any]],
              let route = routes.first,
              let meters = route["distanceMeters"] as? Double ?? (route["distanceMeters"] as? Int).map(Double.init),
              let duration = route["duration"] as? String,
              let seconds = Double(duration.dropLast()) else { return .failure(.invalidResponse) }
        return .success(RouteData(distanceKilometers: meters / 1000, durationMinutes: max(1, Int((seconds / 60).rounded())), providerName: "Google Routes", timestamp: Date()))
    }
}
