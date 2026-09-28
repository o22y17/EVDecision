import Foundation

enum ChargeDecision: String, Hashable {
    case chargeNow = "Charge Now"
    case dontCharge = "Don't Charge"
}

#if DEBUG
extension ChargingRecommendation {
    static var itineraryPreview: ChargingRecommendation {
        let route = RouteData(distanceKilometers: 700, durationMinutes: 420, providerName: "Sample", timestamp: Date())
        let stops = (1...2).map { index -> ItineraryStop in
            let unit = ChargingUnit(id: "sample-unit-\(index)", stationID: "sample-\(index)", connectorType: "CCS", maximumPowerKW: 150, status: .unknown, lastUpdated: nil, dataConfidence: .low)
            let station = ChargingStation(id: "sample-\(index)", name: "Sample charging stop \(index)", operatorName: "Example operator", latitude: 0, longitude: 0, lastUpdated: nil, source: .manualFallback, dataConfidence: .low, units: [unit])
            return ItineraryStop(station: station, unit: unit, arrivalBattery: 26, chargeTo: 80, chargingMinutes: 21, incomingLeg: RouteLegData(distanceKilometers: index == 1 ? 200 : 300, durationMinutes: index == 1 ? 120 : 180))
        }
        let plan = ChargingItinerary(stops: stops, arrivalBattery: 44, route: route, additionalDistanceKilometers: 10, extraTravelMinutes: 55)
        return ChargingRecommendation(decision: .chargeNow, arrivalBattery: 0, reserveBattery: 20, incrementalTimeCostMinutes: 55, destination: SelectedPlace(name: "Bodrum · sample", latitude: 0, longitude: 0), explanation: "Sample only", confidence: .low, routeData: route, usedLiveRouteData: false, chargingStop: nil, routeIssue: nil, itinerary: plan)
    }
}
#endif

enum DecisionConfidence: String, Hashable {
    case low = "Low"
    case medium = "Medium"
    case high = "High"
}

struct ChargingRecommendation: Identifiable, Hashable {
    let id = UUID()
    let decision: ChargeDecision
    let arrivalBattery: Int
    let reserveBattery: Int
    let incrementalTimeCostMinutes: Int
    let destination: SelectedPlace?
    let explanation: String
    let confidence: DecisionConfidence
    let routeData: RouteData?
    let usedLiveRouteData: Bool
    let chargingStop: ChargingStopPlan?
    let routeIssue: String?
    var itinerary: ChargingItinerary? = nil

    var title: String { decision.rawValue }
}
