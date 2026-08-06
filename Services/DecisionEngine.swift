import Foundation

protocol DecisionEngine { func recommendation(for trip: TripInput) -> ChargingRecommendation }

struct DecisionScenario {
    let name: String
    let input: TripInput
    let expectedDecision: ChargeDecision
}

struct DecisionEngineV1: DecisionEngine {
    static let sampleScenarios: [DecisionScenario] = [
        DecisionScenario(name: "City drive", input: TripInput(batteryPercentage: 70, destination: SelectedPlace(name: "City", latitude: 1, longitude: 2), reserveBattery: 20, preferredChargeLimit: 80, routeData: nil), expectedDecision: .dontCharge),
        DecisionScenario(name: "Borderline battery", input: TripInput(batteryPercentage: 50, destination: SelectedPlace(name: "Borderline", latitude: 1, longitude: 2.01), reserveBattery: 20, preferredChargeLimit: 80, routeData: nil), expectedDecision: .chargeNow),
        DecisionScenario(name: "Long trip", input: TripInput(batteryPercentage: 70, destination: SelectedPlace(name: "Long trip", latitude: 1, longitude: 2.02), reserveBattery: 20, preferredChargeLimit: 80, routeData: nil), expectedDecision: .chargeNow)
    ]

    func recommendation(for trip: TripInput) -> ChargingRecommendation {
        let predictedArrival = predictedArrivalBattery(for: trip)
        let confidence = confidence(for: predictedArrival, reserveBattery: trip.reserveBattery, usesLiveRouteData: trip.routeData != nil)
        let decision: ChargeDecision = predictedArrival <= trip.reserveBattery + confidenceBuffer(for: confidence) ? .chargeNow : .dontCharge
        let itc = incrementalTimeCost(for: trip)
        return ChargingRecommendation(decision: decision, arrivalBattery: predictedArrival, reserveBattery: trip.reserveBattery, incrementalTimeCostMinutes: itc, destination: trip.destination, explanation: explanation(decision: decision, predictedArrival: predictedArrival, reserveBattery: trip.reserveBattery, preferredChargeLimit: trip.preferredChargeLimit, itc: itc, usingLiveRoute: trip.routeData != nil), confidence: confidence, routeData: trip.routeData, usedLiveRouteData: trip.routeData != nil, chargingStop: nil)
    }

    func predictedArrivalBattery(for trip: TripInput) -> Int {
        max(0, trip.batteryPercentage - estimatedRouteConsumption(for: trip))
    }

    func estimatedRouteConsumption(for destination: SelectedPlace?) -> Int {
        guard let destination else { return 30 }
        let signature = Int((abs(destination.latitude * 100) + abs(destination.longitude * 100)).rounded())
        switch signature % 3 {
        case 0: return 18
        case 1: return 30
        default: return 55
        }
    }

    func estimatedRouteConsumption(for trip: TripInput) -> Int {
        if let routeData = trip.routeData {
            return max(1, Int((routeData.distanceKilometers * 0.18).rounded(.up)))
        }
        return estimatedRouteConsumption(for: trip.destination)
    }

    func incrementalTimeCost(for trip: TripInput) -> Int {
        let chargeDelta = max(0, trip.preferredChargeLimit - trip.batteryPercentage)
        return max(8, Int((Double(chargeDelta) * 0.45).rounded()))
    }

    func confidence(for predictedArrival: Int, reserveBattery: Int) -> DecisionConfidence {
        confidence(for: predictedArrival, reserveBattery: reserveBattery, usesLiveRouteData: true)
    }

    func confidence(for predictedArrival: Int, reserveBattery: Int, usesLiveRouteData: Bool) -> DecisionConfidence {
        let margin = predictedArrival - reserveBattery
        let routeConfidence: DecisionConfidence
        if margin >= 15 { routeConfidence = .high }
        else if margin >= 5 { routeConfidence = .medium }
        else { routeConfidence = .low }
        guard !usesLiveRouteData else { return routeConfidence }
        return routeConfidence == .high ? .medium : .low
    }

    private func confidenceBuffer(for confidence: DecisionConfidence) -> Int {
        switch confidence {
        case .high: return 0
        case .medium: return 2
        case .low: return 5
        }
    }

    private func explanation(decision: ChargeDecision, predictedArrival: Int, reserveBattery: Int, preferredChargeLimit: Int, itc: Int, usingLiveRoute: Bool) -> String {
        let routeNote = usingLiveRoute ? " This uses your live route." : " This is a basic estimate because your live route was unavailable."
        let buffer = confidenceBuffer(for: confidence(for: predictedArrival, reserveBattery: reserveBattery, usesLiveRouteData: usingLiveRoute))
        switch decision {
        case .chargeNow:
            return "Predicted arrival is \(predictedArrival)%. The decision protects your \(reserveBattery)% reserve plus a \(buffer)-point confidence buffer. Charging toward \(preferredChargeLimit)% protects your arrival margin.\(routeNote)"
        case .dontCharge:
            return "Predicted arrival is \(predictedArrival)%, preserving your \(reserveBattery)% reserve. Charging now would add about \(itc) minutes.\(routeNote)"
        }
    }
}
