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
            Section("Trip impact") {
                metric("Arrival battery", "\(recommendation.arrivalBattery)%")
                metric("Reserve", "\(recommendation.reserveBattery)%")
                metric("ITC", "+\(recommendation.incrementalTimeCostMinutes) min")
                metric("Confidence", recommendation.confidence.rawValue)
            }
            if let place = recommendation.destination, GoogleMapsConfiguration.isConfigured {
                Section("Destination") {
                    GoogleMapView(place: place).frame(height: 180).clipShape(RoundedRectangle(cornerRadius: 10))
                    Text(place.name).font(.subheadline)
                }
            }
            Section("Why") { Text(recommendation.explanation).font(.subheadline) }
        }.navigationTitle("Recommendation").navigationBarTitleDisplayMode(.inline)
    }
    private func metric(_ name: String, _ value: String) -> some View {
        HStack { Text(name); Spacer(); Text(value).font(.body.monospacedDigit().weight(.semibold)) }
    }
}
