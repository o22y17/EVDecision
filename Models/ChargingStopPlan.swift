import Foundation

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
