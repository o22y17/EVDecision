import Foundation
protocol DecisionEngine { func recommendation(for trip: TripInput) -> ChargingRecommendation }
struct MockDecisionEngine: DecisionEngine { func recommendation(for trip: TripInput) -> ChargingRecommendation { .mock } }
