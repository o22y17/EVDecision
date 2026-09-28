import Foundation

struct ItineraryStop: Hashable {
    let station: ChargingStation
    let unit: ChargingUnit
    let arrivalBattery: Int
    let chargeTo: Int
    let chargingMinutes: Int
    let incomingLeg: RouteLegData
}

struct ChargingItinerary: Hashable {
    let stops: [ItineraryStop]
    let arrivalBattery: Int
    let route: RouteData
    let additionalDistanceKilometers: Double
    let extraTravelMinutes: Int
}

struct ChargingStopPlan: Hashable {
    let station: ChargingStation
    let unit: ChargingUnit
    let distanceOffRouteKilometers: Double
    let arrivalBattery: Int
    let chargeFrom: Int
    let chargeTo: Int
    let chargingMinutes: Int
    let arrivalBatteryAtDestination: Int
    let extraTravelMinutes: Int
}
