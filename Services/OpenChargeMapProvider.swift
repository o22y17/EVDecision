import Foundation

struct OpenChargeMapProvider: ChargingDataProvider {
    let source: ChargingDataSource = .openChargeMap
    private let session: URLSession
    private let apiKey: String?

    init(session: URLSession = .shared, apiKey: String? = Bundle.main.object(forInfoDictionaryKey: "OpenChargeMapAPIKey") as? String) {
        self.session = session
        self.apiKey = apiKey
    }

    @MainActor func searchStations(near latitude: Double, longitude: Double, radiusKilometers: Double = 25) async -> ChargingProviderResult {
        var components = URLComponents(string: "https://api.openchargemap.io/v3/poi/")!
        components.queryItems = [
            URLQueryItem(name: "output", value: "json"),
            URLQueryItem(name: "latitude", value: String(latitude)),
            URLQueryItem(name: "longitude", value: String(longitude)),
            URLQueryItem(name: "distance", value: String(radiusKilometers)),
            URLQueryItem(name: "distanceunit", value: "KM"),
            URLQueryItem(name: "maxresults", value: "100"),
            URLQueryItem(name: "compact", value: "true"),
            URLQueryItem(name: "verbose", value: "false")
        ]
        if let apiKey, !apiKey.isEmpty, !apiKey.contains("$(") { components.queryItems?.append(URLQueryItem(name: "key", value: apiKey)) }
        return await request(components.url!)
    }

    @MainActor func searchStations(in corridor: RouteCorridor) async -> ChargingProviderResult {
        var stations: [ChargingStation] = []
        var failures: [String] = []
        for point in corridor.samplePoints {
            let result = await searchStations(near: point.latitude, longitude: point.longitude, radiusKilometers: corridor.radiusKilometers)
            stations.append(contentsOf: result.stations)
            if let error = result.errorDescription { failures.append(error) }
        }
        return ChargingProviderResult(stations: stations, source: source, timestamp: Date(), errorDescription: failures.first)
    }

    private func request(_ url: URL) async -> ChargingProviderResult {
        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return ChargingProviderResult(stations: [], source: source, timestamp: Date(), errorDescription: "Open Charge Map is unavailable right now.")
            }
            return ChargingProviderResult(stations: decode(data: data), source: source, timestamp: Date(), errorDescription: nil)
        } catch {
            return ChargingProviderResult(stations: [], source: source, timestamp: Date(), errorDescription: "Open Charge Map request timed out or could not connect.")
        }
    }

    func decode(data: Data) -> [ChargingStation] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let records = try? decoder.decode([OpenChargeMapRecord].self, from: data) else { return [] }
        return records.compactMap { record in
            guard let address = record.address, let latitude = address.latitude, let longitude = address.longitude else { return nil }
            let stationID = String(record.id)
            let updated = record.dateLastStatusUpdate ?? record.dateLastVerified
            let units = (record.connections ?? []).map { connection in
                ChargingUnit(id: "\(stationID)-\(connection.id ?? 0)", stationID: stationID, connectorType: connection.connectionType?.title, maximumPowerKW: connection.powerKW, status: availability(from: connection.statusType?.title ?? record.statusType?.title), lastUpdated: updated, dataConfidence: .low)
            }
            return ChargingStation(id: stationID, name: address.title ?? "Unnamed charging station", operatorName: record.operatorInfo?.title, latitude: latitude, longitude: longitude, lastUpdated: updated, source: .openChargeMap, dataConfidence: .low, units: units)
        }
    }

    private func availability(from text: String?) -> ChargingAvailability {
        guard let text = text?.lowercased() else { return .unknown }
        if text.contains("operational") || text.contains("available") { return .available }
        if text.contains("occupied") || text.contains("in use") { return .occupied }
        if text.contains("out of service") || text.contains("not operational") { return .outOfService }
        return .unknown
    }
}

private struct OpenChargeMapRecord: Decodable {
    let id: Int
    let address: Address?
    let operatorInfo: NamedValue?
    let connections: [Connection]?
    let statusType: NamedValue?
    let dateLastStatusUpdate: Date?
    let dateLastVerified: Date?
    enum CodingKeys: String, CodingKey { case id = "ID", address = "AddressInfo", operatorInfo = "OperatorInfo", connections = "Connections", statusType = "StatusType", dateLastStatusUpdate = "DateLastStatusUpdate", dateLastVerified = "DateLastVerified" }
    struct Address: Decodable { let title: String?; let latitude: Double?; let longitude: Double?; enum CodingKeys: String, CodingKey { case title = "Title", latitude = "Latitude", longitude = "Longitude" } }
    struct NamedValue: Decodable { let title: String?; enum CodingKeys: String, CodingKey { case title = "Title" } }
    struct Connection: Decodable { let id: Int?; let connectionType: NamedValue?; let powerKW: Double?; let statusType: NamedValue?; enum CodingKeys: String, CodingKey { case id = "ID", connectionType = "ConnectionType", powerKW = "PowerKW", statusType = "StatusType" } }
}
