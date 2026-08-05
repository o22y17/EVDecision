import XCTest
@testable import EVDecision

final class DecisionEngineTests: XCTestCase {
    private let engine = DecisionEngineV1()

    func testSampleScenariosProduceExpectedDecisions() {
        for scenario in DecisionEngineV1.sampleScenarios {
            XCTAssertEqual(engine.recommendation(for: scenario.input).decision, scenario.expectedDecision, scenario.name)
        }
    }

    func testCityDrivePreservesReserveWithHighConfidence() {
        let recommendation = engine.recommendation(for: DecisionEngineV1.sampleScenarios[0].input)
        XCTAssertEqual(recommendation.arrivalBattery, 52)
        XCTAssertEqual(recommendation.confidence, .high)
        XCTAssertEqual(recommendation.decision, .dontCharge)
    }

    func testBorderlineBatteryChargesToProtectReserve() {
        let recommendation = engine.recommendation(for: DecisionEngineV1.sampleScenarios[1].input)
        XCTAssertEqual(recommendation.arrivalBattery, 20)
        XCTAssertEqual(recommendation.confidence, .low)
        XCTAssertEqual(recommendation.decision, .chargeNow)
    }

    func testLongTripRequiresACharge() {
        let recommendation = engine.recommendation(for: DecisionEngineV1.sampleScenarios[2].input)
        XCTAssertEqual(recommendation.arrivalBattery, 15)
        XCTAssertEqual(recommendation.decision, .chargeNow)
    }
}
