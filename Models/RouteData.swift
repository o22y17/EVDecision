import Foundation

struct RouteData: Hashable {
    let distanceKilometers: Double
    let durationMinutes: Int
    let providerName: String
    let timestamp: Date
}

enum RouteLookupResult: Equatable {
    case success(RouteData)
    case failure(RouteServiceFailure)
}

enum RouteServiceFailure: Error, Equatable, LocalizedError {
    case apiKeyUnavailable
    case networkUnavailable
    case noRouteFound
    case invalidResponse
    case timedOut

    var errorDescription: String? {
        switch self {
        case .apiKeyUnavailable: "Route setup is incomplete. You can still get a basic recommendation."
        case .networkUnavailable: "We couldn’t get a route right now. Using a basic estimate instead."
        case .noRouteFound: "We couldn’t find a driving route. Using a basic estimate instead."
        case .invalidResponse: "Route details weren’t available. Using a basic estimate instead."
        case .timedOut: "Route lookup took too long. Using a basic estimate instead."
        }
    }
}
