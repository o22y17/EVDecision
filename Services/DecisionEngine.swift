import Foundation
protocol DecisionEngine { func recommendation(for trip: TripInput) -> ChargingRecommendation }
struct MockDecisionEngine: DecisionEngine {
    func recommendation(for trip: TripInput) -> ChargingRecommendation {
        ChargingRecommendation(
            title: "Do NOT Charge",
            arrivalBattery: 24,
            reserveBattery: trip.reserveBattery,
            incrementalTimeCostMinutes: 18,
            destination: trip.destination
        )
    }
}
