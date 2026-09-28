import SwiftUI

struct RecommendationView: View {
    let recommendation: ChargingRecommendation
    @Environment(\.openURL) private var openURL

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let itinerary = recommendation.itinerary {
                    fullPlan(itinerary)
                } else if recommendation.decision == .dontCharge {
                    safeArrival
                } else if let stop = recommendation.chargingStop {
                    chargingStop(stop)
                } else {
                    noStopFound
                }
                routeSummary
                if recommendation.chargingStop != nil || recommendation.itinerary != nil, let issue = recommendation.routeIssue {
                    Label(issue, systemImage: "exclamationmark.triangle")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if recommendation.confidence == .low {
                    Text("This estimate has limited information. Check your car’s battery before relying on it.").font(.footnote).foregroundStyle(.secondary)
                }
            }.padding()
        }
        .navigationTitle("Your trip")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func fullPlan(_ plan: ChargingItinerary) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 10) {
                Label("Your complete charging plan", systemImage: "map").font(.title3.weight(.semibold))
                metric("Charging stops", "\(plan.stops.count)")
                metric("Estimated arrival battery", "\(plan.arrivalBattery)%")
                metric("Safety reserve", "\(recommendation.reserveBattery)%")
                metric("Total extra time", formattedDuration(plan.extraTravelMinutes))
                Text("Battery and charging times are estimates, not live vehicle readings. Stop availability is not verified.").font(.footnote).foregroundStyle(.secondary)
            }.card()
            ForEach(Array(plan.stops.enumerated()), id: \.element.station.id) { index, stop in
                VStack(alignment: .leading, spacing: 10) {
                    Label(index == 0 ? "Stop 1 · Next" : "Stop \(index + 1)", systemImage: "bolt.circle.fill")
                        .font(.headline).foregroundStyle(index == 0 ? .green : .primary)
                    Text(stop.station.name).font(.headline)
                    metric("Operator", stop.station.operatorName ?? "Not listed")
                    powerMetric(stop.unit.maximumPowerKW.map { String(format: "%.0f kW", $0) } ?? "Not listed")
                    metric(index == 0 ? "Drive to first stop" : "Drive from previous stop", formattedDuration(stop.incomingLeg.durationMinutes))
                    metric("Estimated arrival battery", "\(stop.arrivalBattery)%")
                    metric("Charge", "\(stop.arrivalBattery)% to \(stop.chargeTo)%")
                    metric("Estimated charging time", formattedDuration(stop.chargingMinutes))
                    Text("Live availability not verified. Check the operator’s app.").font(.footnote).foregroundStyle(.secondary)
                    DisclosureGroup("Station information") {
                        metric("Source", stop.station.source == .epdkPublic ? "EPDK catalogue" : stop.station.source.rawValue)
                        metric("Source update", stop.station.lastUpdated.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "Not provided")
                        if let date = stop.station.catalogueFetchedAt { metric("Catalogue retrieved", date.formatted(date: .abbreviated, time: .shortened)) }
                    }.font(.footnote)
                    if index == 0 { navigationMenu(latitude: stop.station.latitude, longitude: stop.station.longitude) }
                }.card()
            }
            Text("After charging, return to your trip while parked, enter your current battery and check the remaining journey again. Later stops may change.").font(.footnote).foregroundStyle(.secondary)
        }
    }

    private func navigationMenu(latitude: Double, longitude: Double) -> some View {
        Menu("Navigate to next stop") {
            Button("Google Maps") { navigate("comgooglemaps://?daddr=\(latitude),\(longitude)", fallback: "https://www.google.com/maps/dir/?api=1&destination=\(latitude),\(longitude)") }
            Button("Apple Maps") { navigate("https://maps.apple.com/?daddr=\(latitude),\(longitude)", fallback: "https://maps.apple.com/?daddr=\(latitude),\(longitude)") }
            Button("Yandex Maps") { navigate("yandexmaps://maps.yandex.com/?rtext=~\(latitude),\(longitude)&rtt=auto", fallback: "https://yandex.com/maps/?rtext=~\(latitude),\(longitude)&rtt=auto") }
        }.buttonStyle(.borderedProminent).tint(.green).frame(maxWidth: .infinity)
            .disabled(recommendation.itinerary?.route.providerName == "Sample")
    }

    private var safeArrival: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("No charging stop expected", systemImage: "checkmark.circle.fill").font(.title3.weight(.semibold)).foregroundStyle(.green)
            Text("Based on the battery level you entered, not live vehicle data.").font(.footnote).foregroundStyle(.secondary)
            metric("Destination", recommendation.destination?.name ?? "Selected destination")
            metric("Estimated arrival battery", "\(recommendation.arrivalBattery)%")
            metric("Safety reserve", "\(recommendation.reserveBattery)%")
            metric("Extra travel time", "0 min")
        }.card()
    }

    private func chargingStop(_ stop: ChargingStopPlan) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Recommended charging stop", systemImage: "bolt.circle.fill").font(.title3.weight(.semibold)).foregroundStyle(.orange)
            Text(stop.station.name).font(.headline)
            metric("Operator", stop.station.operatorName ?? "Not listed")
            if stop.station.source == .epdkPublic {
                metric("Station source", "EPDK catalogue")
                metric("Source update", "Not provided")
                if let fetchedAt = stop.station.catalogueFetchedAt {
                    metric("Catalogue retrieved", fetchedAt.formatted(date: .abbreviated, time: .shortened))
                }
                if let retrievedAt = stop.station.retrievedAt {
                    metric("Downloaded", retrievedAt.formatted(date: .abbreviated, time: .shortened))
                }
                Text("The catalogue may be cached. Download time is not the station’s update time.").font(.footnote).foregroundStyle(.secondary)
            } else if let lastUpdated = stop.station.lastUpdated {
                metric("Station details updated", lastUpdated.formatted(date: .abbreviated, time: .shortened))
            }
            powerMetric(stop.unit.maximumPowerKW.map { String(format: "%.0f kW", $0) } ?? "Not listed")
            metric("Live availability", "Not verified")
            Text("Check the operator’s app for availability before heading here. Battery and charging times are estimates, not live vehicle readings.").font(.footnote).foregroundStyle(.secondary)
            metric("Additional driving distance", String(format: "%.1f km", stop.distanceOffRouteKilometers))
            Text("Selected from up to three route-checked candidates in the available data.").font(.footnote).foregroundStyle(.secondary)
            metric("Arrival battery at station", "\(stop.arrivalBattery)%")
            metric("Charge", "\(stop.chargeFrom)% to \(stop.chargeTo)%")
            metric("Estimated charging time", formattedDuration(stop.chargingMinutes))
            metric("Estimated arrival battery", "\(stop.arrivalBatteryAtDestination)%")
            metric("Extra travel time", "+\(formattedDuration(stop.extraTravelMinutes))")
            Menu("Navigate") {
                Button("Google Maps") { navigate("comgooglemaps://?daddr=\(stop.station.latitude),\(stop.station.longitude)", fallback: "https://www.google.com/maps/dir/?api=1&destination=\(stop.station.latitude),\(stop.station.longitude)") }
                Button("Apple Maps") { navigate("http://maps.apple.com/?daddr=\(stop.station.latitude),\(stop.station.longitude)", fallback: "http://maps.apple.com/?daddr=\(stop.station.latitude),\(stop.station.longitude)") }
                Button("Yandex Maps") { navigate("yandexmaps://maps.yandex.com/?rtext=~\(stop.station.latitude),\(stop.station.longitude)&rtt=auto", fallback: "https://yandex.com/maps/?rtext=~\(stop.station.latitude),\(stop.station.longitude)&rtt=auto") }
            }.buttonStyle(.borderedProminent).tint(.green).frame(maxWidth: .infinity)
        }.card()
    }

    private var noStopFound: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Charging is needed", systemImage: "exclamationmark.triangle.fill").font(.title3.weight(.semibold)).foregroundStyle(.orange)
            Text(recommendation.routeIssue ?? "We could not find a suitable fast charger close enough to this route. Check your vehicle’s navigation or choose a different destination before leaving.").foregroundStyle(.secondary)
        }.card()
    }

    private var routeSummary: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Route").font(.headline)
            metric("Destination", recommendation.destination?.name ?? "Selected destination")
            if let stop = recommendation.chargingStop { metric("Charging stop", stop.station.name) }
            if let route = recommendation.itinerary?.route ?? recommendation.routeData {
                metric("Trip distance", String(format: "%.0f km", route.distanceKilometers))
                metric("Driving time", formattedDuration(route.durationMinutes))
            }
        }.card()
    }

    private func formattedDuration(_ totalMinutes: Int) -> String {
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        return hours > 0 ? "\(hours) hr \(minutes) min" : "\(minutes) min"
    }

    private func powerMetric(_ value: String) -> some View { HStack(alignment: .firstTextBaseline) { Label("Maximum power", systemImage: "bolt.fill").foregroundStyle(.secondary); Spacer(minLength: 12); Text(value).multilineTextAlignment(.trailing).font(.body.weight(.semibold)) } }

    private func metric(_ label: String, _ value: String) -> some View { HStack(alignment: .firstTextBaseline) { Text(label).foregroundStyle(.secondary); Spacer(minLength: 12); Text(value).multilineTextAlignment(.trailing).font(.body.weight(.semibold)) } }
    private func navigate(_ preferred: String, fallback: String) {
        guard let fallbackURL = URL(string: fallback) else { return }
        guard let url = URL(string: preferred) else { openURL(fallbackURL); return }
        openURL(url) { accepted in if !accepted { openURL(fallbackURL) } }
    }
}

private extension View { func card() -> some View { padding().background(.background, in: RoundedRectangle(cornerRadius: 16)).overlay(RoundedRectangle(cornerRadius: 16).stroke(.quaternary)) } }
