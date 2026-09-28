import CoreLocation
import Foundation

protocol RouteService {
    func route(from origin: CLLocationCoordinate2D, to destination: CLLocationCoordinate2D) async -> RouteLookupResult
}

protocol ItineraryRouteService: Sendable {
    func itineraryRoute(from origin: RoutePoint, to destination: RoutePoint, stops: [RoutePoint]) async -> RouteLookupResult
}

struct GoogleRoutesService: RouteService, ItineraryRouteService {
    private let session: URLSession
    private let apiKey: String?

    init(session: URLSession = .shared, apiKey: String? = Bundle.main.object(forInfoDictionaryKey: "GoogleMapsAPIKey") as? String) {
        self.session = session
        self.apiKey = apiKey
    }

    func route(from origin: CLLocationCoordinate2D, to destination: CLLocationCoordinate2D) async -> RouteLookupResult {
        await route(from: origin, to: destination, via: nil)
    }

    func route(from origin: CLLocationCoordinate2D, to destination: CLLocationCoordinate2D, via stop: CLLocationCoordinate2D?) async -> RouteLookupResult {
        await route(from: origin, to: destination, stops: stop.map { [$0] } ?? [])
    }

    func itineraryRoute(from origin: RoutePoint, to destination: RoutePoint, stops: [RoutePoint]) async -> RouteLookupResult {
        await route(from: CLLocationCoordinate2D(latitude: origin.latitude, longitude: origin.longitude), to: CLLocationCoordinate2D(latitude: destination.latitude, longitude: destination.longitude), stops: stops.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) })
    }

    private func route(from origin: CLLocationCoordinate2D, to destination: CLLocationCoordinate2D, stops: [CLLocationCoordinate2D]) async -> RouteLookupResult {
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
        request.setValue("routes.duration,routes.distanceMeters,routes.polyline.geoJsonLinestring,routes.legs.distanceMeters,routes.legs.duration", forHTTPHeaderField: "X-Goog-FieldMask")
        var body: [String: Any] = [
            "origin": waypoint(origin),
            "destination": waypoint(destination),
            "travelMode": "DRIVE",
            "routingPreference": "TRAFFIC_AWARE",
            "units": "METRIC",
            "polylineEncoding": "GEO_JSON_LINESTRING",
            "polylineQuality": "HIGH_QUALITY"
        ]
        if !stops.isEmpty { body["intermediates"] = stops.map(waypoint) }
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
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

    func decode(_ data: Data) -> RouteLookupResult {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let routes = object["routes"] as? [[String: Any]],
              let route = routes.first,
              let meters = route["distanceMeters"] as? Double ?? (route["distanceMeters"] as? Int).map(Double.init),
              let duration = route["duration"] as? String,
              duration.hasSuffix("s"), let seconds = Double(duration.dropLast()),
              meters.isFinite, meters >= 0, seconds.isFinite, seconds >= 0, seconds < 31_536_000 else { return .failure(.invalidResponse) }
        let geometry = (route["polyline"] as? [String: Any])?["geoJsonLinestring"] as? [String: Any]
        let coordinates = geometry?["coordinates"] as? [[Double]] ?? []
        let points = coordinates.compactMap { coordinate -> RoutePoint? in
            guard coordinate.count >= 2, (-180...180).contains(coordinate[0]), (-90...90).contains(coordinate[1]) else { return nil }
            return RoutePoint(latitude: coordinate[1], longitude: coordinate[0])
        }
        let validGeometry = geometry?["type"] as? String == "LineString" && points.count == coordinates.count && points.count >= 2
        let rawLegs = route["legs"] as? [[String: Any]] ?? []
        let legs = rawLegs.compactMap { leg -> RouteLegData? in
            guard let distance = leg["distanceMeters"] as? Double, distance.isFinite, distance >= 0,
                  let duration = leg["duration"] as? String, duration.hasSuffix("s"),
                  let seconds = Double(duration.dropLast()), seconds.isFinite, seconds >= 0, seconds < 31_536_000 else { return nil }
            return RouteLegData(distanceKilometers: distance / 1000, durationMinutes: Int((seconds / 60).rounded(.up)))
        }
        return .success(RouteData(distanceKilometers: meters / 1000, durationMinutes: max(1, Int((seconds / 60).rounded(.up))), providerName: "Google Routes", timestamp: Date(), polyline: validGeometry ? points : nil, legs: legs.count == rawLegs.count ? legs : []))
    }
}
