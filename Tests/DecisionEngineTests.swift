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
        let input = trip(battery: 20, destination: place(latitude: 1, longitude: 2.02))
        XCTAssertEqual(engine.predictedArrivalBattery(for: input), 0)
    }

    func testConfidenceThresholds() {
        XCTAssertEqual(engine.confidence(for: 35, reserveBattery: 20), .high)
        XCTAssertEqual(engine.confidence(for: 25, reserveBattery: 20), .medium)
        XCTAssertEqual(engine.confidence(for: 24, reserveBattery: 20), .low)
    }

    func testDecisionUsesConservativeEqualityAtReservePlusBuffer() {
        let input = trip(battery: 38, destination: place(latitude: 1, longitude: 2))
        let result = engine.recommendation(for: input)
        XCTAssertEqual(result.arrivalBattery, 20)
        XCTAssertEqual(result.decision, .chargeNow)
    }

    func testPreferredChargeLimitOnlyChangesITC() {
        let destination = place(latitude: 1, longitude: 2)
        let lowerLimit = trip(battery: 60, destination: destination, preferredLimit: 70)
        let higherLimit = trip(battery: 60, destination: destination, preferredLimit: 90)
        let lowerResult = engine.recommendation(for: lowerLimit)
        let higherResult = engine.recommendation(for: higherLimit)

        XCTAssertEqual(lowerResult.arrivalBattery, higherResult.arrivalBattery)
        XCTAssertEqual(lowerResult.decision, higherResult.decision)
        XCTAssertEqual(lowerResult.incrementalTimeCostMinutes, 8)
        XCTAssertEqual(higherResult.incrementalTimeCostMinutes, 14)
    }

    func testITCUsesEightMinuteMinimum() {
        XCTAssertEqual(engine.incrementalTimeCost(for: trip(battery: 85, preferredLimit: 80)), 8)
    }

    func testChargeNowExplanationIncludesReserveAndLimit() {
        let result = engine.recommendation(for: trip(battery: 50, destination: place(latitude: 1, longitude: 2.01)))
        XCTAssertEqual(result.decision, .chargeNow)
        XCTAssertTrue(result.explanation.contains("20%"))
        XCTAssertTrue(result.explanation.contains("80%"))
    }

    func testDontChargeExplanationIncludesTimeCost() {
        let result = engine.recommendation(for: trip(battery: 70, destination: place(latitude: 1, longitude: 2)))
        XCTAssertEqual(result.decision, .dontCharge)
        XCTAssertTrue(result.explanation.contains("minutes"))
    }

    private func trip(battery: Int, destination: SelectedPlace? = nil, reserve: Int = 20, preferredLimit: Int = 80) -> TripInput {
        TripInput(batteryPercentage: battery, destination: destination, reserveBattery: reserve, preferredChargeLimit: preferredLimit)
    }

    private func place(latitude: Double, longitude: Double) -> SelectedPlace {
        SelectedPlace(name: "Test destination", latitude: latitude, longitude: longitude)
    }
}
