import XCTest
@testable import EVDecision

@MainActor
final class ChargingDataTests: XCTestCase {
    private func multiStopFixture() -> (RouteData, [ChargingStation], RoutePoint, RoutePoint) {
        let origin = RoutePoint(latitude: 41, longitude: 29), destination = RoutePoint(latitude: 41, longitude: 36)
        let route = RouteData(distanceKilometers: 700, durationMinutes: 420, providerName: "Fixture", timestamp: Date(), polyline: [origin, destination])
        let stations = [31.0, 34.0].enumerated().map { index, lon in
            station(id: "multi\(index)", source: .operatorAPI, latitude: 41, longitude: lon, updated: Date(), units: [unit(id: "dc\(index)", connector: "CCS", power: 150, updated: Date())])
        }
        return (route, stations, origin, destination)
    }

    func testMultiStopCandidateOrderAndChargeLimit() {
        let (route, stations, _, _) = multiStopFixture()
        let plans = RoadTripPlanner().candidateItineraries(stations: stations.reversed(), route: route, battery: 62, reserve: 20, preferredLimit: 80)
        XCTAssertEqual(plans.first?.map(\.id), stations.map(\.id))
        XCTAssertTrue(RoadTripPlanner().candidateItineraries(stations: stations, route: route, battery: 10, reserve: 20, preferredLimit: 80).isEmpty)
        XCTAssertTrue(RoadTripPlanner().candidateItineraries(stations: stations, route: route, battery: 62, reserve: 20, preferredLimit: 80, maximumStops: 1).isEmpty)
    }

    func testWholeItineraryEnergyAndIncompleteLegRejection() {
        let (baseline, stations, _, _) = multiStopFixture()
        var route = baseline
        route.legs = [200.0, 300.0, 200.0].map { RouteLegData(distanceKilometers: $0, durationMinutes: Int($0)) }
        let planner = RoadTripPlanner()
        let plan = planner.validatedItinerary(stations: stations, route: route, baseline: baseline, battery: 62, reserve: 20, preferredLimit: 80)
        XCTAssertEqual(plan?.stops.count, 2)
        XCTAssertEqual(plan?.stops.map(\.arrivalBattery), [26, 26])
        XCTAssertEqual(plan?.stops.map(\.chargeTo), [80, 80])
        XCTAssertEqual(plan?.arrivalBattery, 44)
        route.legs.removeLast()
        XCTAssertNil(planner.validatedItinerary(stations: stations, route: route, baseline: baseline, battery: 62, reserve: 20, preferredLimit: 80))
        route.legs.append(RouteLegData(distanceKilometers: 400, durationMinutes: 200))
        XCTAssertNil(planner.validatedItinerary(stations: stations, route: route, baseline: baseline, battery: 62, reserve: 20, preferredLimit: 80))
    }

    func testRouteFailureNeverReturnsPartialMultiStopPlan() async {
        let (route, stations, origin, destination) = multiStopFixture()
        let result = await RoadTripPlanner().verifiedItinerary(stations: stations, route: route, battery: 62, reserve: 20, preferredLimit: 80, origin: origin, destination: destination, service: FailedItineraryService())
        XCTAssertNil(result.itinerary)
        XCTAssertNotNil(result.message)
    }

    private struct FailedItineraryService: ItineraryRouteService {
        func itineraryRoute(from origin: RoutePoint, to destination: RoutePoint, stops: [RoutePoint]) async -> RouteLookupResult { .failure(.timedOut) }
    }

    func testNoChargeItineraryHasNoStationsOrExtraTime() {
        let now = Date()
        let route = RouteData(distanceKilometers: 10, durationMinutes: 15, providerName: "Fixture", timestamp: now, legs: [RouteLegData(distanceKilometers: 10, durationMinutes: 15)])
        let plan = RoadTripPlanner().validatedItinerary(stations: [], route: route, baseline: route, battery: 80, reserve: 20, preferredLimit: 80)
        XCTAssertEqual(plan?.stops.count, 0)
        XCTAssertEqual(plan?.arrivalBattery, 78)
        XCTAssertEqual(plan?.extraTravelMinutes, 0)
    }

    func testVerifiedMultiStopItineraryReturnsAllStops() async {
        let (baseline, stations, origin, destination) = multiStopFixture()
        var route = baseline
        route.legs = [200.0, 300.0, 200.0].map { RouteLegData(distanceKilometers: $0, durationMinutes: Int($0)) }
        let result = await RoadTripPlanner().verifiedItinerary(stations: stations, route: baseline, battery: 62, reserve: 20, preferredLimit: 80, origin: origin, destination: destination, service: SuccessfulItineraryService(route: route))
        XCTAssertEqual(result.itinerary?.stops.map(\.station.id), stations.map(\.id))
        XCTAssertEqual(result.itinerary?.arrivalBattery, 44)
    }

    private struct SuccessfulItineraryService: ItineraryRouteService {
        let route: RouteData
        func itineraryRoute(from origin: RoutePoint, to destination: RoutePoint, stops: [RoutePoint]) async -> RouteLookupResult { .success(route) }
    }

    func testBentRoadCorridorDoesNotUseStraightLineShortcut() {
        let a = RoutePoint(latitude: 40, longitude: 29)
        let bend = RoutePoint(latitude: 41, longitude: 29)
        let b = RoutePoint(latitude: 41, longitude: 30)
        let road = [a, bend, b]
        XCTAssertEqual(RouteGeometry.position(of: bend, along: road)?.distance, 0)
        XCTAssertGreaterThan(RouteGeometry.position(of: RoutePoint(latitude: 40.5, longitude: 29.5), along: road)!.distance, 30)
        // Between sparse vertices still belongs to the corridor.
        XCTAssertLessThan(RouteGeometry.position(of: RoutePoint(latitude: 40.5, longitude: 29.001), along: road)!.distance, 1)
        let service = ChargingDataService(providers: [])
        let nearBend = station(id: "bend", source: .operatorAPI, latitude: 41, longitude: 29, updated: Date(), units: [])
        XCTAssertTrue(service.isInside(nearBend, corridor: RouteCorridor(origin: a, destination: b, polyline: road, radiusKilometers: 2)))
    }

    func testRouteDecoderPreservesGeometryAndLegs() {
        let data = #"{"routes":[{"distanceMeters":3000,"duration":"120s","polyline":{"geoJsonLinestring":{"type":"LineString","coordinates":[[29,41],[30,42]]}},"legs":[{"distanceMeters":1000,"duration":"40s"},{"distanceMeters":2000,"duration":"80s"}]}]}"#.data(using: .utf8)!
        guard case .success(let route) = GoogleRoutesService(apiKey: nil).decode(data) else { return XCTFail("Expected route") }
        XCTAssertEqual(route.polyline?.first, RoutePoint(latitude: 41, longitude: 29))
        XCTAssertEqual(route.legs.map(\.distanceKilometers), [1, 2])
        XCTAssertEqual(route.durationMinutes, 2)
    }

    func testMalformedRouteDurationIsRejected() {
        let data = #"{"routes":[{"distanceMeters":3000,"duration":"120x"}]}"#.data(using: .utf8)!
        XCTAssertEqual(GoogleRoutesService(apiKey: nil).decode(data), .failure(.invalidResponse))
    }

    func testVerifiedDrivingLegsDetermineEnergyAndDetour() {
        let now = Date()
        let origin = RoutePoint(latitude: 41, longitude: 29), destination = RoutePoint(latitude: 41, longitude: 32)
        let route = RouteData(distanceKilometers: 300, durationMinutes: 180, providerName: "Fixture", timestamp: now, polyline: [origin, destination])
        let stop = station(id: "stop", source: .operatorAPI, latitude: 41, longitude: 30, updated: now, units: [unit(id: "dc", connector: "CCS", power: 150, updated: now)])
        let via = RouteData(distanceKilometers: 330, durationMinutes: 230, providerName: "Fixture", timestamp: now, legs: [RouteLegData(distanceKilometers: 110, durationMinutes: 80), RouteLegData(distanceKilometers: 220, durationMinutes: 150)])
        let result = RoadTripPlanner().bestStop(stations: [stop], route: route, battery: 62, reserve: 20, preferredLimit: 80, origin: origin, destination: destination, checkedRoutes: ["stop": via])
        XCTAssertEqual(result?.arrivalBattery, 42)
        XCTAssertEqual(result?.arrivalBatteryAtDestination, 40)
        XCTAssertEqual(result?.distanceOffRouteKilometers, 30)
        XCTAssertEqual(result?.extraTravelMinutes, 69)
        XCTAssertNil(RoadTripPlanner().bestStop(stations: [stop], route: route, battery: 62, reserve: 20, preferredLimit: 80, origin: origin, destination: destination, checkedRoutes: [:]))
        XCTAssertNil(RoadTripPlanner().bestStop(stations: [stop], route: route, battery: 30, reserve: 20, preferredLimit: 80, origin: origin, destination: destination, checkedRoutes: ["stop": via]))
        XCTAssertNil(RoadTripPlanner().bestStop(stations: [stop], route: route, battery: 62, reserve: 20, preferredLimit: 50, origin: origin, destination: destination, checkedRoutes: ["stop": via]))
    }

    private func catalogueFixture(timestamp: Double, extra: String = "") -> Data {
        """
        {"fetchedAt":\(timestamp),"stations":[{"sarjIstasyonuNo":"1","sarjIstasyonuAdi":"Fixture","marka":"TEST","enlem":41,"boylam":29,"soketler":[]}]\(extra)}
        """.data(using: .utf8)!
    }

    func testEPDKPreservesServerCatalogueAgeSeparatelyFromDownload() {
        let now = Date(timeIntervalSince1970: 2_000_000)
        let result = EPDKChargingProvider().decodeResult(data: catalogueFixture(timestamp: now.timeIntervalSince1970 - 43_200), downloadedAt: now)
        XCTAssertNil(result.errorDescription)
        XCTAssertEqual(result.stations.first?.catalogueFetchedAt, now.addingTimeInterval(-43_200))
        XCTAssertEqual(result.stations.first?.retrievedAt, now)
        XCTAssertNil(result.stations.first?.lastUpdated)
    }

    func testEPDKRejectsExpiredAndFutureCatalogue() {
        let now = Date(timeIntervalSince1970: 2_000_000)
        for offset in [-86_401.0, 301.0] {
            let result = EPDKChargingProvider().decodeResult(data: catalogueFixture(timestamp: now.timeIntervalSince1970 + offset), downloadedAt: now)
            XCTAssertTrue(result.stations.isEmpty)
            XCTAssertNotNil(result.errorDescription)
        }
    }

    func testEPDKPartialFailureKeepsUsefulStationsAndWarning() {
        let now = Date(timeIntervalSince1970: 2_000_000)
        let data = catalogueFixture(timestamp: now.timeIntervalSince1970, extra: #", "partialFailures":["ZES: timeout"]"#)
        let result = EPDKChargingProvider().decodeResult(data: data, downloadedAt: now)
        XCTAssertEqual(result.stations.count, 1)
        XCTAssertTrue(result.errorDescription?.contains("incomplete") == true)
    }

    func testEPDKMalformedStationDoesNotDiscardValidStation() {
        let data = #"{"fetchedAt":2000000,"stations":[{"sarjIstasyonuNo":"1","sarjIstasyonuAdi":"Valid","enlem":41,"boylam":29},{"enlem":"invalid"},{"sarjIstasyonuNo":"3","sarjIstasyonuAdi":"Outside","enlem":141,"boylam":29}]}"#.data(using: .utf8)!
        let result = EPDKChargingProvider().decodeResult(data: data, downloadedAt: Date(timeIntervalSince1970: 2_000_000))
        XCTAssertEqual(result.stations.map(\.name), ["Valid"])
        XCTAssertNotNil(result.errorDescription)
    }

    func testEPDKDownloadDoesNotInventSourceFreshnessOrAvailability() {
        let downloaded = Date()
        let json = #"{"stations":[{"sarjIstasyonuNo":"1","sarjIstasyonuAdi":"Fixture","marka":"TEST","enlem":41,"boylam":29,"soketler":[{"soketNo":"1","soketTuru":"CCS","soketGucu":"150"}]}]}"#.data(using: .utf8)!
        let station = EPDKChargingProvider().decode(data: json, fetchedAt: downloaded)[0]
        XCTAssertNil(station.lastUpdated)
        XCTAssertNil(station.units[0].lastUpdated)
        XCTAssertEqual(station.retrievedAt, downloaded)
        XCTAssertEqual(station.units[0].status, .unknown)
        XCTAssertEqual(station.dataConfidence, .low)
        XCTAssertEqual(ChargingDataService(providers: []).confidence(for: station), .low)
        XCTAssertEqual(ChargingDataService(providers: []).merge([station])[0].retrievedAt, downloaded)
        XCTAssertTrue(RoadTripPlanner().hasReliableCandidate(in: [station]))
        var expired = station
        expired.retrievedAt = downloaded.addingTimeInterval(-2 * 86_400)
        XCTAssertFalse(RoadTripPlanner().hasReliableCandidate(in: [expired]))
    }

    func testProviderDecodingPreservesUnknownStatusAndMissingPower() {
        let json = #"[{"ID":7,"AddressInfo":{"Title":"Test Hub","Latitude":41.0,"Longitude":29.0},"Connections":[{"ID":1,"ConnectionType":{"Title":"CCS Type 2"},"PowerKW":150},{"ID":2,"ConnectionType":{"Title":"CHAdeMO"}}]}]"#.data(using: .utf8)!
        let stations = OpenChargeMapProvider(apiKey: nil).decode(data: json)
        XCTAssertEqual(stations.count, 1)
        XCTAssertEqual(stations[0].units.count, 2)
        XCTAssertEqual(stations[0].units[0].maximumPowerKW, 150)
        XCTAssertEqual(stations[0].units[0].status, .unknown)
        XCTAssertNil(stations[0].units[1].maximumPowerKW)
    }

    func testMergeConflictFreshnessCorridorAndDCFiltering() {
        let service = ChargingDataService(providers: [])
        let recent = Date()
        let dc = unit(id: "dc", connector: "CCS Type 2", power: 150, updated: recent)
        let ac = unit(id: "ac", connector: "Type 2", power: 22, updated: recent)
        let first = station(id: "1", source: .openChargeMap, latitude: 41.0, longitude: 29.0, updated: recent, units: [dc, ac])
        let conflict = station(id: "2", source: .googlePlaces, latitude: 41.00001, longitude: 29.00001, updated: recent, units: [dc])
        XCTAssertEqual(service.merge([first, conflict]).first?.dataConfidence, .low)
        XCTAssertEqual(service.confidence(for: station(id: "official", source: .operatorAPI, latitude: 41, longitude: 29, updated: recent, units: [dc])), .high)
        XCTAssertEqual(service.confidence(for: station(id: "old", source: .openChargeMap, latitude: 41, longitude: 29, updated: Date().addingTimeInterval(-8 * 86_400), units: [dc])), .low)
        let corridor = RouteCorridor(origin: RoutePoint(latitude: 41, longitude: 29), destination: RoutePoint(latitude: 41.1, longitude: 29.1), polyline: nil, radiusKilometers: 3)
        let snapshot = service.snapshot(from: [ChargingProviderResult(stations: [first], source: .openChargeMap, timestamp: recent, errorDescription: nil)], corridor: corridor)
        XCTAssertEqual(snapshot.stations.count, 1)
        XCTAssertEqual(snapshot.stations[0].units.filter { service.isUsefulDC($0, vehicleConnectors: []) }.count, 1)
    }

    func testProviderFailureReturnsPartialResults() async {
        let now = Date()
        let good = station(id: "good", source: .openChargeMap, latitude: 41, longitude: 29, updated: now, units: [unit(id: "dc", connector: "CCS", power: 100, updated: now)])
        let service = ChargingDataService(providers: [FixtureProvider(result: ChargingProviderResult(stations: [good], source: .openChargeMap, timestamp: now, errorDescription: nil)), FixtureProvider(result: ChargingProviderResult(stations: [], source: .operatorAPI, timestamp: now, errorDescription: "Operator unavailable"))])
        let snapshot = await service.stations(near: 41, longitude: 29)
        XCTAssertEqual(snapshot.stations.count, 1)
        XCTAssertEqual(snapshot.partialFailures, ["Operator unavailable"])
    }

    private struct FixtureProvider: ChargingDataProvider {
        let result: ChargingProviderResult
        var source: ChargingDataSource { result.source }
        func searchStations(near latitude: Double, longitude: Double, radiusKilometers: Double) async -> ChargingProviderResult { result }
        func searchStations(in corridor: RouteCorridor) async -> ChargingProviderResult { result }
    }

    private func unit(id: String, connector: String?, power: Double?, updated: Date?) -> ChargingUnit {
        ChargingUnit(id: id, stationID: "station", connectorType: connector, maximumPowerKW: power, status: .unknown, lastUpdated: updated, dataConfidence: .low)
    }

    private func station(id: String, source: ChargingDataSource, latitude: Double, longitude: Double, updated: Date?, units: [ChargingUnit]) -> ChargingStation {
        ChargingStation(id: id, name: "Station " + id, operatorName: "Operator", latitude: latitude, longitude: longitude, lastUpdated: updated, source: source, dataConfidence: .low, units: units)
    }
}
