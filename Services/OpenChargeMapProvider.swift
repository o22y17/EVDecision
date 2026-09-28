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
            URLQueryItem(name: "compact", value: "false"),
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
        request.setValue("EVDecision/1.0 (iOS)", forHTTPHeaderField: "User-Agent")
        if let apiKey, !apiKey.isEmpty {
            request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        }
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
        if text.contains("available") && !text.contains("operational") { return .available }
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

/// Uses EPDK's public charging-station catalogue. Its documented public API
/// does not expose live socket availability, so every unit remains unknown.
@MainActor
final class EPDKChargingProvider: ChargingDataProvider {
    let source: ChargingDataSource = .epdkPublic
    private let session: URLSession
    private var networkCache: [String: ChargingProviderResult] = [:]
    private let cacheLifetime: TimeInterval = 30 * 60

    init(session: URLSession = .shared) {
        self.session = session
    }

    func searchStations(near latitude: Double, longitude: Double, radiusKilometers: Double = 25) async -> ChargingProviderResult {
        let result = await catalogue()
        let center = RoutePoint(latitude: latitude, longitude: longitude)
        let nearby = result.stations.filter {
            Self.distanceKilometers(from: center, to: RoutePoint(latitude: $0.latitude, longitude: $0.longitude)) <= radiusKilometers
        }
        return ChargingProviderResult(stations: nearby, source: source, timestamp: result.timestamp, errorDescription: result.errorDescription)
    }

    func searchStations(in corridor: RouteCorridor) async -> ChargingProviderResult {
        await catalogue()
    }

    private func catalogue() async -> ChargingProviderResult {
        let supported = ["TESLA", "TRUGO", "ZES", "ESARJ", "SHARZ", "OTOJET", "VOLTRUN"]
        let selection = UserDefaults.standard.string(forKey: "chargingNetworks") ?? ""
        let selected = selection.isEmpty ? supported : supported.filter { selection.components(separatedBy: ",").contains($0) }
        guard !selected.isEmpty else { return failure("Select at least one charging network in Settings.") }
        var stations: [ChargingStation] = []
        var issues: [String] = []
        for network in selected {
            let result = await catalogue(network: network)
            stations.append(contentsOf: result.stations)
            if let issue = result.errorDescription { issues.append("\(network): \(issue)") }
        }
        return ChargingProviderResult(stations: stations, source: source, timestamp: Date(), errorDescription: issues.isEmpty ? nil : issues.joined(separator: "\n"))
    }

    private func catalogue(network: String) async -> ChargingProviderResult {
        if let cached = networkCache[network], Date().timeIntervalSince(cached.timestamp) < cacheLifetime,
           cached.stations.allSatisfy({ $0.catalogueFetchedAt.map { Date().timeIntervalSince($0) <= 86_400 } ?? true }) {
            return cached
        }
        guard let proxyURL = Bundle.main.object(forInfoDictionaryKey: "EPDKStationProxyURL") as? String,
              var components = URLComponents(string: proxyURL), components.scheme == "https", components.host != nil else {
            return failure("Official charging data could not be reached.")
        }
        components.queryItems = [URLQueryItem(name: "brands", value: network)]
        guard let url = components.url else { return failure("Charging service configuration is incomplete.") }

        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.setValue("EVDecision/1.0 (iOS)", forHTTPHeaderField: "User-Agent")

        do {
            let (fileURL, response) = try await session.download(for: request)
            guard let http = response as? HTTPURLResponse else { return failure("Official charging data could not be reached.") }
            guard (200..<300).contains(http.statusCode) else {
                return failure(http.statusCode == 429 ? "Official charging data is busy. Please try again in a moment." : "Official charging data is unavailable right now.")
            }
            let fetchedAt = Date()
            let data = try Data(contentsOf: fileURL)
            let result = decodeResult(data: data, downloadedAt: fetchedAt)
            if result.errorDescription == nil { networkCache[network] = result }
            return result
        } catch {
            return failure("Official charging data could not connect. Please check your connection.")
        }
    }

    private func failure(_ message: String) -> ChargingProviderResult {
        ChargingProviderResult(stations: [], source: source, timestamp: Date(), errorDescription: message)
    }

    func decode(data: Data, fetchedAt: Date) -> [ChargingStation] {
        decodeResult(data: data, downloadedAt: fetchedAt).stations
    }

    func decodeResult(data: Data, downloadedAt: Date) -> ChargingProviderResult {
        guard let response = try? JSONDecoder().decode(EPDKResponse.self, from: data) else {
            return ChargingProviderResult(stations: [], source: source, timestamp: downloadedAt, errorDescription: "Charging service returned an unreadable catalogue. Try again later.")
        }
        let catalogueDate = response.fetchedAt.map { Date(timeIntervalSince1970: $0) }
        if let catalogueDate, downloadedAt.timeIntervalSince(catalogueDate) > 86_400 || catalogueDate.timeIntervalSince(downloadedAt) > 300 {
            return ChargingProviderResult(stations: [], source: source, timestamp: downloadedAt, errorDescription: "The charging catalogue is out of date or has an invalid timestamp. Try again later.")
        }
        let stations = response.stations.compactMap { record -> ChargingStation? in
            guard let id = record.stationID, let name = record.stationName,
                  !id.isEmpty, !name.isEmpty,
                  let latitude = record.latitude, let longitude = record.longitude,
                  (-90...90).contains(latitude), (-180...180).contains(longitude) else { return nil }
            let units = (record.sockets ?? []).compactMap { socket -> ChargingUnit? in
                guard let socketID = socket.socketID else { return nil }
                return ChargingUnit(id: socketID, stationID: id, connectorType: socket.socketType,
                                    maximumPowerKW: Double(socket.power ?? ""), status: .unknown,
                                    lastUpdated: nil, dataConfidence: .low)
            }
            return ChargingStation(id: id, name: name,
                                   operatorName: record.networkOperator ?? record.stationOperator ?? record.brand,
                                   latitude: latitude, longitude: longitude, lastUpdated: nil,
                                   source: source, dataConfidence: .low, units: units, retrievedAt: downloadedAt, catalogueFetchedAt: catalogueDate)
        }
        var issues: [String] = []
        if !response.partialFailures.isEmpty { issues.append("Some charging data could not be refreshed. Results may be incomplete.") }
        if stations.count < response.stations.count + response.invalidRecordCount { issues.append("Some station records were incomplete and could not be used.") }
        if stations.isEmpty { issues.append("No usable stations were returned by this network.") }
        if catalogueDate == nil { issues.append("The catalogue download time from the source is not available.") }
        return ChargingProviderResult(stations: stations, source: source, timestamp: downloadedAt, errorDescription: issues.isEmpty ? nil : issues.joined(separator: " "))
    }

    private static func distanceKilometers(from: RoutePoint, to: RoutePoint) -> Double {
        let latitudeScale = 111.0
        let longitudeScale = 111.0 * cos((from.latitude + to.latitude) * .pi / 360)
        return hypot((from.latitude - to.latitude) * latitudeScale, (from.longitude - to.longitude) * longitudeScale)
    }
}

private struct EPDKResponse: Decodable {
    let stations: [EPDKStation]
    let fetchedAt: Double?
    let partialFailures: [String]
    let invalidRecordCount: Int

    enum CodingKeys: String, CodingKey { case stations, data, fetchedAt, partialFailures }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        fetchedAt = try container.decodeIfPresent(Double.self, forKey: .fetchedAt)
        partialFailures = try container.decodeIfPresent([String].self, forKey: .partialFailures) ?? []
        var records = try container.nestedUnkeyedContainer(forKey: container.contains(.stations) ? .stations : .data)
        var decoded: [EPDKStation] = []
        var invalid = 0
        while !records.isAtEnd {
            let recordDecoder = try records.superDecoder()
            if let record = try? EPDKStation(from: recordDecoder) { decoded.append(record) }
            else { invalid += 1 }
        }
        stations = decoded
        invalidRecordCount = invalid
    }
}

private struct EPDKStation: Decodable {
    let stationID: String?
    let stationName: String?
    let networkOperator: String?
    let stationOperator: String?
    let brand: String?
    let latitude: Double?
    let longitude: Double?
    let sockets: [EPDKSocket]?

    enum CodingKeys: String, CodingKey {
        case stationID = "sarjIstasyonuNo"
        case stationName = "sarjIstasyonuAdi"
        case networkOperator = "sarjAgiIsletmecisiUnvan"
        case stationOperator = "sarjIstasyonuIsletmecisi"
        case brand = "marka"
        case latitude = "enlem"
        case longitude = "boylam"
        case sockets = "soketler"
    }
}

private struct EPDKSocket: Decodable {
    let socketID: String?
    let socketType: String?
    let power: String?

    enum CodingKeys: String, CodingKey {
        case socketID = "soketNo"
        case socketType = "soketTuru"
        case power = "soketGucu"
    }
}
