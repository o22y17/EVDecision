import XCTest
@testable import EVDecision

final class DecisionEngineTests: XCTestCase {
    private let engine = DecisionEngineV1()

    func testSampleScenariosProduceExpectedDecisions() {
        for scenario in DecisionEngineV1.sampleScenarios {
            XCTAssertEqual(engine.recommendation(for: scenario.input).decision, scenario.expectedDecision, scenario.name)
        }
    }

    func testRouteConsumptionBandsAndMissingDestination() {
        XCTAssertEqual(engine.estimatedRouteConsumption(for: nil), 30)
        XCTAssertEqual(engine.estimatedRouteConsumption(for: place(latitude: 1, longitude: 2)), 18)
        XCTAssertEqual(engine.estimatedRouteConsumption(for: place(latitude: 1, longitude: 2.01)), 30)
        XCTAssertEqual(engine.estimatedRouteConsumption(for: place(latitude: 1, longitude: 2.02)), 55)
    }

    func testPredictedArrivalClampsAtZero() {
        XCTAssertEqual(engine.predictedArrivalBattery(for: trip(battery: 20, destination: place(latitude: 1, longitude: 2.02))), 0)
    }

    func testConfidenceThresholds() {
        XCTAssertEqual(engine.confidence(for: 35, reserveBattery: 20), .high)
        XCTAssertEqual(engine.confidence(for: 25, reserveBattery: 20), .medium)
        XCTAssertEqual(engine.confidence(for: 24, reserveBattery: 20), .low)
    }

    func testDecisionUsesConservativeEqualityAtReservePlusBuffer() {
        let result = engine.recommendation(for: trip(battery: 38, destination: place(latitude: 1, longitude: 2)))
        XCTAssertEqual(result.arrivalBattery, 20)
        XCTAssertEqual(result.decision, .chargeNow)
    }

    func testPreferredChargeLimitOnlyChangesITC() {
        let destination = place(latitude: 1, longitude: 2)
        let lowerResult = engine.recommendation(for: trip(battery: 60, destination: destination, preferredLimit: 70))
        let higherResult = engine.recommendation(for: trip(battery: 60, destination: destination, preferredLimit: 90))
        XCTAssertEqual(lowerResult.arrivalBattery, higherResult.arrivalBattery)
        XCTAssertEqual(lowerResult.decision, higherResult.decision)
        XCTAssertEqual(lowerResult.incrementalTimeCostMinutes, 8)
        XCTAssertEqual(higherResult.incrementalTimeCostMinutes, 14)
    }

    func testITCUsesEightMinuteMinimum() {
        XCTAssertEqual(engine.incrementalTimeCost(for: trip(battery: 85, preferredLimit: 80)), 8)
    }

    func testLiveRouteDataDrivesConsumptionAndRecommendationMetadata() {
        let route = RouteData(distanceKilometers: 100, durationMinutes: 90, providerName: "Google Routes", timestamp: Date())
        let result = engine.recommendation(for: trip(battery: 50, destination: place(latitude: 1, longitude: 2), routeData: route))
        XCTAssertEqual(result.arrivalBattery, 32)
        XCTAssertTrue(result.usedLiveRouteData)
        XCTAssertEqual(result.routeData, route)
    }

    func testRouteServiceFailureFallsBackToExistingEstimate() {
        let result = engine.recommendation(for: trip(battery: 70, destination: place(latitude: 1, longitude: 2), routeData: nil))
        XCTAssertEqual(result.arrivalBattery, 52)
        XCTAssertFalse(result.usedLiveRouteData)
        XCTAssertTrue(result.explanation.contains("basic estimate"))
    }

    func testFallbackLowersConfidence() {
        XCTAssertEqual(engine.confidence(for: 40, reserveBattery: 20, usesLiveRouteData: true), .high)
        XCTAssertEqual(engine.confidence(for: 40, reserveBattery: 20, usesLiveRouteData: false), .medium)
        XCTAssertEqual(engine.confidence(for: 25, reserveBattery: 20, usesLiveRouteData: false), .low)
    }

    func testLocationUnavailableHasHumanReadableFallbackMessage() {
        XCTAssertTrue((LocationServiceFailure.unavailable.errorDescription ?? "").contains("basic estimate"))
        XCTAssertTrue((LocationServiceFailure.permissionDenied.errorDescription ?? "").contains("Location access"))
    }

    private func trip(battery: Int, destination: SelectedPlace? = nil, reserve: Int = 20, preferredLimit: Int = 80, routeData: RouteData? = nil) -> TripInput {
        TripInput(batteryPercentage: battery, destination: destination, reserveBattery: reserve, preferredChargeLimit: preferredLimit, routeData: routeData)
    }

    private func place(latitude: Double, longitude: Double) -> SelectedPlace {
        SelectedPlace(name: "Test destination", latitude: latitude, longitude: longitude)
    }
}
