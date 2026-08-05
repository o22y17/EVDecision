import SwiftUI

struct RecommendationView: View {
    let recommendation: ChargingRecommendation
    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Label(recommendation.title, systemImage: recommendation.decision == .chargeNow ? "bolt.fill" : "checkmark.circle.fill")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(recommendation.decision == .chargeNow ? .orange : .green)
                    Text(recommendation.explanation).font(.subheadline).foregroundStyle(.secondary)
                }.padding(.vertical, 4)
            }
            Section("What this means") {
                metric("Battery when you arrive", "\(recommendation.arrivalBattery)%")
                metric("Your arrival buffer", "\(recommendation.reserveBattery)%")
                metric("Time added by charging", "+\(recommendation.incrementalTimeCostMinutes) min")
                metric("How sure we are", recommendation.confidence.rawValue)
            }
            Section("Route") {
                if let route = recommendation.routeData {
                    metric("Trip distance", String(format: "%.1f km", route.distanceKilometers))
                    metric("Estimated driving time", "\(route.durationMinutes) min")
                    metric("Recommendation data", "Live route")
                } else {
                    metric("Recommendation data", "Basic estimate")
                }
            }
            if let place = recommendation.destination, GoogleMapsConfiguration.isConfigured {
                Section("Destination") {
                    GoogleMapView(place: place).frame(height: 180).clipShape(RoundedRectangle(cornerRadius: 10))
                    Text(place.name).font(.subheadline)
                }
            }
            Section("Why we recommend this") { Text(recommendation.explanation).font(.subheadline) }
        }.navigationTitle("Recommendation").navigationBarTitleDisplayMode(.inline)
    }
    private func metric(_ name: String, _ value: String) -> some View {
        HStack { Text(name); Spacer(); Text(value).font(.body.monospacedDigit().weight(.semibold)) }
    }
}
