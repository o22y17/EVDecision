import Foundation

enum ChargingAvailability: String, Codable, Hashable {
    case available, occupied, outOfService, unknown
}

enum ChargingDataSource: String, Codable, Hashable {
    case operatorAPI, openChargeMap, googlePlaces, manualFallback
}

enum ChargingDataConfidence: String, Codable, Hashable, Comparable {
    case low, medium, high

    private var rank: Int { switch self { case .low: 0; case .medium: 1; case .high: 2 } }
    static func < (lhs: ChargingDataConfidence, rhs: ChargingDataConfidence) -> Bool { lhs.rank < rhs.rank }
}

struct ChargingUnit: Identifiable, Codable, Hashable {
    let id: String
    let stationID: String
    let connectorType: String?
    let maximumPowerKW: Double?
    let status: ChargingAvailability
    let lastUpdated: Date?
    let dataConfidence: ChargingDataConfidence
}

struct ChargingStation: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let operatorName: String?
    let latitude: Double
    let longitude: Double
    let lastUpdated: Date?
    let source: ChargingDataSource
    let dataConfidence: ChargingDataConfidence
    let units: [ChargingUnit]
}

struct ChargingProviderResult: Hashable {
    let stations: [ChargingStation]
    let source: ChargingDataSource
    let timestamp: Date
    let errorDescription: String?
}

struct ChargingDataSnapshot: Hashable {
    let stations: [ChargingStation]
    let sources: [ChargingDataSource]
    let timestamp: Date
    let partialFailures: [String]
}
