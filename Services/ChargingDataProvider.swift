import Foundation

protocol ChargingDataProvider {
    var source: ChargingDataSource { get }
    @MainActor func searchStations(near latitude: Double, longitude: Double, radiusKilometers: Double) async -> ChargingProviderResult
    @MainActor func searchStations(in corridor: RouteCorridor) async -> ChargingProviderResult
}
