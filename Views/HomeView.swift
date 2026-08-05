import SwiftUI

struct HomeView: View {
    @AppStorage("reserveBattery") private var reserveBattery = 20
    @State private var batteryPercentage = 62.0
    @State private var selectedPlace: SelectedPlace?
    @State private var recommendation: ChargingRecommendation?
    @State private var showsAutocomplete = false
    private let engine = MockDecisionEngine()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Daily decision").font(.title3.weight(.semibold))
                    Text("Optimize your time, not the battery.").font(.subheadline).foregroundStyle(.secondary)
                }
                GroupBox("Battery") {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack { Text("Current charge"); Spacer(); Text("\(Int(batteryPercentage))%").font(.headline.monospacedDigit()).foregroundStyle(.green) }
                        Slider(value: $batteryPercentage, in: 0...100, step: 1).tint(.green)
                    }.padding(.vertical, 2)
                }
                GroupBox("Trip") {
                    VStack(alignment: .leading, spacing: 10) {
                        Button { showsAutocomplete = true } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "magnifyingglass")
                                Text(selectedPlace?.name ?? "Search destination")
                                    .foregroundStyle(selectedPlace == nil ? .secondary : .primary)
                                    .lineLimit(2)
                                Spacer()
                                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                            .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 8))
                        }
                        .disabled(!GoogleMapsConfiguration.isConfigured)
                        if !GoogleMapsConfiguration.isConfigured {
                            Text("Add your Google Maps API key in Config/GoogleMaps.local.xcconfig to search places.")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                        if let selectedPlace {
                            Text("\(selectedPlace.latitude.formatted(.number.precision(.fractionLength(4)))), \(selectedPlace.longitude.formatted(.number.precision(.fractionLength(4))))")
                                .font(.footnote.monospacedDigit()).foregroundStyle(.secondary)
                        }
                        Text("Reserve on arrival: \(reserveBattery)%").font(.footnote).foregroundStyle(.secondary)
                    }.padding(.vertical, 2)
                }
                Button { recommendation = engine.recommendation(for: TripInput(batteryPercentage: Int(batteryPercentage), destination: selectedPlace, reserveBattery: reserveBattery)) } label: { Text("Get Recommendation").frame(maxWidth: .infinity) }
                    .buttonStyle(.borderedProminent).tint(.green)
            }.padding()
        }
        .navigationTitle("EV Decision").navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $recommendation) { RecommendationView(recommendation: $0) }
        .sheet(isPresented: $showsAutocomplete) { GooglePlaceAutocompleteView(isPresented: $showsAutocomplete) { selectedPlace = $0 } }
    }
}
