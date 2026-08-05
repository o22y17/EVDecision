import Foundation
struct ChargingRecommendation: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let arrivalBattery: Int
    let reserveBattery: Int
    let incrementalTimeCostMinutes: Int
    let destination: SelectedPlace?

    static let mock = ChargingRecommendation(title: "Do NOT Charge", arrivalBattery: 24, reserveBattery: 20, incrementalTimeCostMinutes: 18, destination: nil)
}
