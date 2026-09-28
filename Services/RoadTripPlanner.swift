import Foundation
import CoreLocation

struct RoadTripPlanner {
    private func chargingTime(from battery: Int, to limit: Int, power: Double) -> Int {
        let energy = Double(max(0, limit - battery)) / 100 * 70
        let effectivePower = min(power, 150) * (limit > 80 ? 0.55 : 0.72)
        return max(8, Int((energy / effectivePower * 60).rounded(.up)))
    }

    private func usableUnit(_ station: ChargingStation) -> ChargingUnit? {
        station.units.filter {
            let type = $0.connectorType?.lowercased() ?? ""
            return ["ccs", "chademo", "nacs", "tesla"].contains(where: type.contains)
                && ($0.maximumPowerKW ?? 0) >= 20 && $0.status != .outOfService
        }.max { ($0.maximumPowerKW ?? 0) < ($1.maximumPowerKW ?? 0) }
    }

    /// Bounded candidate paths. Geometry estimates only screen candidates; never presented as a verified plan.
    func candidateItineraries(stations: [ChargingStation], route: RouteData, battery: Int, reserve: Int, preferredLimit: Int, maximumStops: Int = 6) -> [[ChargingStation]] {
        guard let geometry = route.polyline, geometry.count >= 2,
              (0...100).contains(battery), (0...100).contains(reserve),
              preferredLimit > reserve, preferredLimit <= 100, maximumStops > 0,
              route.distanceKilometers.isFinite, route.distanceKilometers >= 0 else { return [] }
        struct Node { let station: ChargingStation?; let progress: Double; let offRoute: Double }
        struct Path { let indices: [Int]; let cost: Int }
        var seen = Set<String>()
        let candidates: [Node] = stations.compactMap { station in
            guard seen.insert(station.id).inserted, isReliableForRecommendation(station), usableUnit(station) != nil,
                  let location = RouteGeometry.position(of: RoutePoint(latitude: station.latitude, longitude: station.longitude), along: geometry),
                  location.progress > 0, location.progress < 1, location.distance <= 12 else { return nil }
            return Node(station: station, progress: location.progress, offRoute: location.distance)
        }.sorted { $0.progress == $1.progress ? $0.station!.id < $1.station!.id : $0.progress < $1.progress }
        let nodes = [Node(station: nil, progress: 0, offRoute: 0)] + candidates + [Node(station: nil, progress: 1, offRoute: 0)]
        var paths = Array(repeating: [Path](), count: nodes.count)
        paths[0] = [Path(indices: [], cost: 0)]
        for target in 1..<nodes.count {
            var options: [Path] = []
            for source in 0..<target where !paths[source].isEmpty {
                let distance = (nodes[target].progress - nodes[source].progress) * route.distanceKilometers + nodes[source].offRoute + nodes[target].offRoute
                let arrival = (source == 0 ? battery : preferredLimit) - Int((distance * 0.18).rounded(.up))
                guard arrival >= reserve else { continue }
                for path in paths[source] {
                    if let station = nodes[target].station, let unit = usableUnit(station) {
                        guard path.indices.count < maximumStops, arrival < preferredLimit else { continue }
                        let minutes = chargingTime(from: arrival, to: preferredLimit, power: unit.maximumPowerKW!)
                        options.append(Path(indices: path.indices + [target], cost: path.cost + minutes + 4 + Int((nodes[target].offRoute * 4).rounded(.up))))
                    } else { options.append(path) }
                }
            }
            paths[target] = Array(options.sorted { $0.cost == $1.cost ? $0.indices.lexicographicallyPrecedes($1.indices) : $0.cost < $1.cost }.prefix(3))
        }
        return paths.last!.map { path in path.indices.compactMap { nodes[$0].station } }
    }

    /// Pure validation: no partially reachable itinerary may escape this function.
    func validatedItinerary(stations: [ChargingStation], route: RouteData, baseline: RouteData, battery: Int, reserve: Int, preferredLimit: Int) -> ChargingItinerary? {
        guard (0...100).contains(battery), (0...100).contains(reserve), preferredLimit > reserve, preferredLimit <= 100,
              route.legs.count == stations.count + 1, Set(stations.map(\.id)).count == stations.count,
              route.distanceKilometers.isFinite, route.distanceKilometers >= 0, route.durationMinutes >= 0,
              baseline.distanceKilometers.isFinite, baseline.distanceKilometers >= 0,
              route.legs.allSatisfy({ $0.distanceKilometers.isFinite && $0.distanceKilometers >= 0 && $0.distanceKilometers < 100_000 && $0.durationMinutes >= 0 }) else { return nil }
        var currentBattery = battery
        var stops: [ItineraryStop] = []
        for (index, leg) in route.legs.enumerated() {
            currentBattery -= Int((leg.distanceKilometers * 0.18).rounded(.up))
            guard currentBattery >= reserve else { return nil }
            if index < stations.count {
                let station = stations[index]
                guard let unit = usableUnit(station), currentBattery < preferredLimit else { return nil }
                stops.append(ItineraryStop(station: station, unit: unit, arrivalBattery: currentBattery, chargeTo: preferredLimit, chargingMinutes: chargingTime(from: currentBattery, to: preferredLimit, power: unit.maximumPowerKW!), incomingLeg: leg))
                currentBattery = preferredLimit
            }
        }
        return ChargingItinerary(stops: stops, arrivalBattery: currentBattery, route: route, additionalDistanceKilometers: max(0, route.distanceKilometers - baseline.distanceKilometers), extraTravelMinutes: max(0, route.durationMinutes - baseline.durationMinutes) + stops.reduce(0) { $0 + $1.chargingMinutes + 4 })
    }

    @MainActor
    func verifiedItinerary(stations: [ChargingStation], route: RouteData, battery: Int, reserve: Int, preferredLimit: Int, origin: RoutePoint, destination: RoutePoint, service: any ItineraryRouteService) async -> (itinerary: ChargingItinerary?, message: String?) {
        guard route.polyline?.count ?? 0 >= 2 else { return (nil, "The road path could not be verified. Try your trip again.") }
        let options = candidateItineraries(stations: stations, route: route, battery: battery, reserve: reserve, preferredLimit: preferredLimit)
        guard !options.isEmpty else { return (nil, "A complete charging plan could not be found within your reserve and charge limit. Available station coverage may be incomplete. No partial plan is shown.") }
        var verified: [ChargingItinerary] = []
        var failed = false
        for stations in options {
            guard !Task.isCancelled else { return (nil, "Trip check was cancelled.") }
            let result = await service.itineraryRoute(from: origin, to: destination, stops: stations.map { RoutePoint(latitude: $0.latitude, longitude: $0.longitude) })
            guard case .success(let drivingRoute) = result else { failed = true; continue }
            if let plan = validatedItinerary(stations: stations, route: drivingRoute, baseline: route, battery: battery, reserve: reserve, preferredLimit: preferredLimit) { verified.append(plan) }
        }
        guard let best = verified.min(by: { $0.extraTravelMinutes < $1.extraTravelMinutes }) else {
            return (nil, failed ? "The complete driving plan could not be verified. Please try again." : "The checked roads do not provide a complete plan within your battery reserve and charge limit. No partial plan is shown.")
        }
        return (best, failed ? "Some alternatives could not be checked. This complete plan uses a verified driving route." : nil)
    }

    func bestStop(stations: [ChargingStation], route: RouteData, battery: Int, reserve: Int, preferredLimit: Int, origin: RoutePoint, destination: RoutePoint, checkedRoutes: [String: RouteData]? = nil) -> ChargingStopPlan? {
        let candidates = stations.filter(isReliableForRecommendation).compactMap { station -> ChargingStopPlan? in
            guard let unit = station.units.filter({ ($0.maximumPowerKW ?? 0) >= 20 && $0.status != .outOfService }).max(by: { ($0.maximumPowerKW ?? 0) < ($1.maximumPowerKW ?? 0) }) else { return nil }
            guard let position = RouteGeometry.position(of: RoutePoint(latitude: station.latitude, longitude: station.longitude), along: route.polyline ?? [origin, destination]) else { return nil }
            let offRoute = position.distance
            let progress = position.progress
            let checked = checkedRoutes?[station.id]
            if checkedRoutes != nil && checked?.legs.count != 2 { return nil }
            let distanceToStop = checked?.legs.first?.distanceKilometers ?? route.distanceKilometers * progress
            let remainingDistance = checked?.legs.last?.distanceKilometers ?? route.distanceKilometers * (1 - progress)
            let consumedToStop = Int((distanceToStop * 0.18).rounded(.up))
            let atStop = max(0, battery - consumedToStop)
            guard atStop >= reserve else { return nil }
            let remainingConsumption = Int((remainingDistance * 0.18).rounded(.up))
            let chargeTo = preferredLimit
            guard chargeTo <= 100, chargeTo > atStop,
                  chargeTo - remainingConsumption >= reserve else { return nil }
            let power = max(20, unit.maximumPowerKW ?? 20)
            let energyNeededKWh = Double(max(0, chargeTo - atStop)) / 100 * 70
            let taperFactor = chargeTo > 80 ? 0.55 : 0.72
            let effectiveChargingPower = min(power, 150) * taperFactor
            let chargingMinutes = max(8, Int((energyNeededKWh / effectiveChargingPower * 60).rounded(.up)))
            let extra = checked.map { max(0, $0.durationMinutes - route.durationMinutes) + 4 } ?? (Int((offRoute * 4).rounded()) + 4)
            let additionalDistance = checked.map { max(0, $0.distanceKilometers - route.distanceKilometers) } ?? offRoute
            return ChargingStopPlan(station: station, unit: unit, distanceOffRouteKilometers: additionalDistance, arrivalBattery: atStop, chargeFrom: atStop, chargeTo: chargeTo, chargingMinutes: chargingMinutes, arrivalBatteryAtDestination: max(0, chargeTo - remainingConsumption), extraTravelMinutes: extra + chargingMinutes)
        }
        return candidates.sorted {
            if $0.extraTravelMinutes != $1.extraTravelMinutes { return $0.extraTravelMinutes < $1.extraTravelMinutes }
            if ($0.unit.maximumPowerKW ?? 0) != ($1.unit.maximumPowerKW ?? 0) { return ($0.unit.maximumPowerKW ?? 0) > ($1.unit.maximumPowerKW ?? 0) }
            if $0.distanceOffRouteKilometers != $1.distanceOffRouteKilometers { return $0.distanceOffRouteKilometers < $1.distanceOffRouteKilometers }
            return $0.station.dataConfidence > $1.station.dataConfidence
        }.first
    }

    @MainActor
    func verifiedStop(stations: [ChargingStation], route: RouteData, battery: Int, reserve: Int, preferredLimit: Int, origin: RoutePoint, destination: RoutePoint, service: GoogleRoutesService) async -> (stop: ChargingStopPlan?, message: String?) {
        guard let geometry = route.polyline, geometry.count >= 2 else {
            return (nil, "The road path could not be verified. No charging stop has been selected. Try your trip again.")
        }
        // Cheap geometry/energy screening precedes a bounded number of paid route requests.
        let shortlist = stations.compactMap { station in
            bestStop(stations: [station], route: route, battery: battery, reserve: reserve, preferredLimit: preferredLimit, origin: origin, destination: destination)
        }.sorted { $0.extraTravelMinutes < $1.extraTravelMinutes }.prefix(3)
        guard !shortlist.isEmpty else {
            return (nil, "No single stop meets your arrival reserve and charge limit in the available data. This trip may need more than one charging stop.")
        }
        var checked: [String: RouteData] = [:]
        var failed = false
        for candidate in shortlist {
            guard !Task.isCancelled else { return (nil, "Trip check was cancelled.") }
            let result = await service.route(from: CLLocationCoordinate2D(latitude: origin.latitude, longitude: origin.longitude), to: CLLocationCoordinate2D(latitude: destination.latitude, longitude: destination.longitude), via: CLLocationCoordinate2D(latitude: candidate.station.latitude, longitude: candidate.station.longitude))
            if case .success(let data) = result, data.legs.count == 2 { checked[candidate.station.id] = data }
            else { failed = true }
        }
        let stop = bestStop(stations: Array(shortlist.map(\.station)), route: route, battery: battery, reserve: reserve, preferredLimit: preferredLimit, origin: origin, destination: destination, checkedRoutes: checked)
        if stop == nil {
            return (nil, failed ? "Some station routes could not be checked. No verified charging stop is available; try again." : "The checked driving routes do not meet your battery reserve and charge limit. More than one charging stop may be needed.")
        }
        return (stop, failed ? "Some station routes could not be checked. This suggestion uses only the routes that were verified." : nil)
    }

    func hasReliableCandidate(in stations: [ChargingStation]) -> Bool {
        stations.contains(where: isReliableForRecommendation)
    }

    private func isReliableForRecommendation(_ station: ChargingStation) -> Bool {
        guard let operatorName = station.operatorName?.trimmingCharacters(in: .whitespacesAndNewlines),
              !operatorName.isEmpty,
              !operatorName.localizedCaseInsensitiveContains("unknown") else { return false }
        // Catalogue eligibility is not a claim of source freshness or live availability.
        let timestamp = station.lastUpdated ?? (station.source == .epdkPublic ? station.catalogueFetchedAt ?? station.retrievedAt : nil)
        guard let timestamp else { return false }
        let age = Date().timeIntervalSince(timestamp)
        return age >= 0 && age <= (station.lastUpdated == nil ? 86_400 : 90 * 86_400)
    }

}
