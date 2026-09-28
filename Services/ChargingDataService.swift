import Foundation

struct RoutePoint: Hashable { let latitude: Double; let longitude: Double }

struct RouteCorridor: Hashable {
    let origin: RoutePoint
    let destination: RoutePoint
    let polyline: [RoutePoint]?
    let radiusKilometers: Double

    var samplePoints: [RoutePoint] {
        if let polyline, !polyline.isEmpty { return polyline }
        return (0...8).map { step in
            let fraction = Double(step) / 8
            return RoutePoint(latitude: origin.latitude + (destination.latitude - origin.latitude) * fraction, longitude: origin.longitude + (destination.longitude - origin.longitude) * fraction)
        }
    }
}

/// Local metric projection onto every segment, not only sparse sample points.
enum RouteGeometry {
    static func position(of point: RoutePoint, along points: [RoutePoint]) -> (distance: Double, progress: Double)? {
        guard points.count >= 2 else { return nil }
        let lonScale = 111 * cos(point.latitude * .pi / 180)
        let lengths = zip(points, points.dropFirst()).map { a, b in
            hypot((b.latitude - a.latitude) * 111, (b.longitude - a.longitude) * lonScale)
        }
        let total = lengths.reduce(0, +)
        guard total > 0 else { return nil }
        var traversed = 0.0
        var bestDistance = Double.infinity
        var bestProgress = 0.0
        for (index, length) in lengths.enumerated() {
            let a = points[index], b = points[index + 1]
            let ax = (a.longitude - point.longitude) * lonScale, ay = (a.latitude - point.latitude) * 111
            let dx = (b.longitude - a.longitude) * lonScale, dy = (b.latitude - a.latitude) * 111
            let t = length > 0 ? min(1, max(0, -(ax * dx + ay * dy) / (length * length))) : 0
            let distance = hypot(ax + t * dx, ay + t * dy)
            if distance < bestDistance { bestDistance = distance; bestProgress = (traversed + t * length) / total }
            traversed += length
        }
        return (bestDistance, bestProgress)
    }
}

@MainActor
struct ChargingDataService {
    let providers: [any ChargingDataProvider]

    func stations(near latitude: Double, longitude: Double, radiusKilometers: Double = 25, vehicleConnectors: Set<String> = []) async -> ChargingDataSnapshot {
        var results: [ChargingProviderResult] = []
        for provider in providers {
            results.append(await provider.searchStations(near: latitude, longitude: longitude, radiusKilometers: radiusKilometers))
        }
        return snapshot(from: results, corridor: nil, vehicleConnectors: vehicleConnectors)
    }

    func stations(in corridor: RouteCorridor, vehicleConnectors: Set<String> = []) async -> ChargingDataSnapshot {
        var results: [ChargingProviderResult] = []
        for provider in providers {
            results.append(await provider.searchStations(in: corridor))
        }
        return snapshot(from: results, corridor: corridor, vehicleConnectors: vehicleConnectors)
    }

    func snapshot(from results: [ChargingProviderResult], corridor: RouteCorridor? = nil, vehicleConnectors: Set<String> = []) -> ChargingDataSnapshot {
        let minimumPower = UserDefaults.standard.object(forKey: "minimumChargingPowerKW") as? Int ?? 50
        let candidates = results.flatMap(\.stations).map { station in
            ChargingStation(id: station.id, name: station.name, operatorName: station.operatorName,
                            latitude: station.latitude, longitude: station.longitude, lastUpdated: station.lastUpdated,
                            source: station.source, dataConfidence: station.dataConfidence,
                            units: station.units.filter { ($0.maximumPowerKW ?? 0) >= Double(minimumPower) && isUsefulDC($0, vehicleConnectors: vehicleConnectors) }, retrievedAt: station.retrievedAt, catalogueFetchedAt: station.catalogueFetchedAt)
        }
        let merged = merge(candidates)
        let filtered = merged.filter { station in
            (corridor == nil || isInside(station, corridor: corridor!)) && station.units.contains { isUsefulDC($0, vehicleConnectors: vehicleConnectors) }
        }
        return ChargingDataSnapshot(stations: filtered, sources: Array(Set(results.map(\.source))).sorted { $0.rawValue < $1.rawValue }, timestamp: Date(), partialFailures: results.compactMap(\.errorDescription))
    }

    func merge(_ stations: [ChargingStation]) -> [ChargingStation] {
        Dictionary(grouping: stations, by: { station in "\(station.operatorName?.lowercased() ?? "")|\(Int(station.latitude * 10_000))|\(Int(station.longitude * 10_000))" }).values.map { group in
            let ordered = group.sorted { confidence(for: $0) > confidence(for: $1) }
            let base = ordered[0]
            let unitMap = Dictionary(grouping: group.flatMap(\.units), by: { "\($0.connectorType ?? "unknown")|\($0.maximumPowerKW ?? -1)" })
            let units = unitMap.values.map { entries in entries.max { confidence(for: $0) < confidence(for: $1) }! }.sorted { $0.id < $1.id }
            let hasConflictingSources = Set(group.map(\.source)).count > 1
            let stationConfidence: ChargingDataConfidence = hasConflictingSources ? .low : confidence(for: base, units: units)
            return ChargingStation(id: base.id, name: base.name, operatorName: base.operatorName, latitude: base.latitude, longitude: base.longitude, lastUpdated: base.lastUpdated, source: base.source, dataConfidence: stationConfidence, units: units, retrievedAt: base.retrievedAt, catalogueFetchedAt: base.catalogueFetchedAt)
        }.sorted { $0.name < $1.name }
    }

    func confidence(for station: ChargingStation, units: [ChargingUnit]? = nil) -> ChargingDataConfidence {
        let units = units ?? station.units
        let complete = !units.isEmpty && units.allSatisfy { $0.connectorType != nil && $0.maximumPowerKW != nil }
        let fresh = station.lastUpdated.map { Date().timeIntervalSince($0) < 7 * 86_400 } ?? false
        if (station.source == .operatorAPI || station.source == .epdkPublic) && fresh && complete { return .high }
        if fresh && complete { return .medium }
        return .low
    }

    func confidence(for unit: ChargingUnit) -> ChargingDataConfidence {
        guard unit.connectorType != nil, unit.maximumPowerKW != nil else { return .low }
        guard let updated = unit.lastUpdated, Date().timeIntervalSince(updated) < 7 * 86_400 else { return .low }
        return unit.status == .unknown ? .medium : .high
    }

    func isUsefulDC(_ unit: ChargingUnit, vehicleConnectors: Set<String>) -> Bool {
        guard let power = unit.maximumPowerKW, power >= 20 else { return false }
        let connector = unit.connectorType?.lowercased() ?? ""
        let isDC = ["ccs", "chademo", "nacs", "tesla"].contains { connector.contains($0) }
        guard isDC else { return false }
        return vehicleConnectors.isEmpty || vehicleConnectors.contains { connector.contains($0.lowercased()) }
    }

    func isInside(_ station: ChargingStation, corridor: RouteCorridor) -> Bool {
        guard let position = RouteGeometry.position(of: RoutePoint(latitude: station.latitude, longitude: station.longitude), along: corridor.samplePoints) else { return false }
        return position.distance <= corridor.radiusKilometers
    }

    private func distanceKilometers(from: RoutePoint, to: RoutePoint) -> Double {
        let latitudeScale = 111.0
        let longitudeScale = 111.0 * cos((from.latitude + to.latitude) * .pi / 360)
        return hypot((from.latitude - to.latitude) * latitudeScale, (from.longitude - to.longitude) * longitudeScale)
    }
}
