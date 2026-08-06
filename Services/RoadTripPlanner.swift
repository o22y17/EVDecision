import Foundation

struct RoadTripPlanner {
    func bestStop(stations: [ChargingStation], route: RouteData, battery: Int, reserve: Int, preferredLimit: Int, origin: RoutePoint, destination: RoutePoint) -> ChargingStopPlan? {
        let candidates = stations.compactMap { station -> ChargingStopPlan? in
            guard let unit = station.units.filter({ $0.maximumPowerKW ?? 0 >= 20 }).max(by: { ($0.maximumPowerKW ?? 0) < ($1.maximumPowerKW ?? 0) }) else { return nil }
            let offRoute = distanceToLine(point: RoutePoint(latitude: station.latitude, longitude: station.longitude), start: origin, end: destination)
            let progress = min(0.9, max(0.1, projection(point: RoutePoint(latitude: station.latitude, longitude: station.longitude), start: origin, end: destination)))
            let consumedToStop = Int((Double(route.distanceKilometers) * progress * 0.18).rounded(.up))
            let atStop = max(0, battery - consumedToStop)
            guard atStop > 3 else { return nil }
            let remainingConsumption = Int((Double(route.distanceKilometers) * (1 - progress) * 0.18).rounded(.up))
            let chargeTo = max(preferredLimit, min(100, remainingConsumption + reserve + 5))
            let power = max(20, unit.maximumPowerKW ?? 20)
            let chargingMinutes = max(8, Int((Double(max(0, chargeTo - atStop)) * 60 / (power / 70)).rounded()))
            let extra = Int((offRoute * 4).rounded()) + 4
            return ChargingStopPlan(station: station, unit: unit, distanceOffRouteKilometers: offRoute, arrivalBattery: atStop, chargeFrom: atStop, chargeTo: chargeTo, chargingMinutes: chargingMinutes, arrivalBatteryAtDestination: max(0, chargeTo - remainingConsumption), extraTravelMinutes: extra + chargingMinutes)
        }
        return candidates.sorted {
            if $0.extraTravelMinutes != $1.extraTravelMinutes { return $0.extraTravelMinutes < $1.extraTravelMinutes }
            if ($0.unit.maximumPowerKW ?? 0) != ($1.unit.maximumPowerKW ?? 0) { return ($0.unit.maximumPowerKW ?? 0) > ($1.unit.maximumPowerKW ?? 0) }
            if $0.distanceOffRouteKilometers != $1.distanceOffRouteKilometers { return $0.distanceOffRouteKilometers < $1.distanceOffRouteKilometers }
            return $0.station.dataConfidence > $1.station.dataConfidence
        }.first
    }

    private func projection(point: RoutePoint, start: RoutePoint, end: RoutePoint) -> Double {
        let dx = end.longitude - start.longitude; let dy = end.latitude - start.latitude
        let denominator = dx * dx + dy * dy
        guard denominator > 0 else { return 0 }
        return ((point.longitude - start.longitude) * dx + (point.latitude - start.latitude) * dy) / denominator
    }
    private func distanceToLine(point: RoutePoint, start: RoutePoint, end: RoutePoint) -> Double {
        let t = min(1, max(0, projection(point: point, start: start, end: end)))
        let closest = RoutePoint(latitude: start.latitude + (end.latitude - start.latitude) * t, longitude: start.longitude + (end.longitude - start.longitude) * t)
        let lat = (point.latitude - closest.latitude) * 111
        let lon = (point.longitude - closest.longitude) * 111 * cos(point.latitude * .pi / 180)
        return hypot(lat, lon)
    }
}
