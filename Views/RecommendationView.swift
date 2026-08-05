import SwiftUI

struct RecommendationView: View {
    let recommendation: ChargingRecommendation
    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Label(recommendation.title, systemImage: "checkmark.circle.fill").font(.title3.weight(.semibold)).foregroundStyle(.green)
                    Text("Continue to your destination — charging now would add time without improving this trip.").font(.subheadline).foregroundStyle(.secondary)
                }.padding(.vertical, 4)
            }
            Section("Trip impact") {
                metric("Arrival battery", "\(recommendation.arrivalBattery)%")
                metric("Reserve", "\(recommendation.reserveBattery)%")
                metric("ITC", "+\(recommendation.incrementalTimeCostMinutes) min")
            }
            Section("Why") { Text("Your projected arrival charge stays above the reserve. Skipping a charge saves an estimated 18 minutes.").font(.subheadline) }
        }.navigationTitle("Recommendation").navigationBarTitleDisplayMode(.inline)
    }
    private func metric(_ name: String, _ value: String) -> some View { HStack { Text(name); Spacer(); Text(value).font(.body.monospacedDigit().weight(.semibold)) } }
}
