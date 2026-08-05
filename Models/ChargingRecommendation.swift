import Foundation

enum ChargeDecision: String, Hashable {
    case chargeNow = "Charge Now"
    case dontCharge = "Don't Charge"
}

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

    var title: String { decision.rawValue }
}
