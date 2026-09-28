import Foundation
import CoreLocation

struct RoadTripPlanner {
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
