import CoreLocation
import SwiftUI

struct HomeView: View {
    @AppStorage("reserveBattery") private var reserveBattery = 20
    @AppStorage("preferredFastChargeLimit") private var preferredChargeLimit = 80
    @State private var batteryPercentage = 62.0
    @State private var selectedPlace: SelectedPlace?
    @State private var recommendation: ChargingRecommendation?
    @State private var showsAutocomplete = false
    @State private var isPreparingRecommendation = false
    @State private var routeMessage: String?
    @StateObject private var locationService = LocationService()

    private let engine = DecisionEngineV1()
    private let routeService = GoogleRoutesService()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Today’s charging decision").font(.title3.weight(.semibold))
                    Text("See whether you can skip a charging stop.").font(.subheadline).foregroundStyle(.secondary)
                }
                GroupBox("Your battery") {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack { Text("Charge right now"); Spacer(); Text("\(Int(batteryPercentage))%").font(.headline.monospacedDigit()).foregroundStyle(.green) }
                        Slider(value: $batteryPercentage, in: 0...100, step: 1).tint(.green)
                    }.padding(.vertical, 2)
                }
                GroupBox("Your trip") {
                    VStack(alignment: .leading, spacing: 10) {
                        Button { showsAutocomplete = true } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "magnifyingglass")
                                Text(selectedPlace?.name ?? "Where are you going?").foregroundStyle(selectedPlace == nil ? .secondary : .primary).lineLimit(2)
                                Spacer()
                                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                            }.frame(maxWidth: .infinity, alignment: .leading).padding(10).background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 8))
                        }.disabled(!GoogleMapsConfiguration.isConfigured)
                        if !GoogleMapsConfiguration.isConfigured { Text("Finish Google Maps setup to search for places.").font(.footnote).foregroundStyle(.secondary) }
                        if selectedPlace != nil { Label("Destination selected", systemImage: "checkmark.circle.fill").font(.footnote).foregroundStyle(.green) }
                        Text("Keep at least \(reserveBattery)% when you arrive.").font(.footnote).foregroundStyle(.secondary)
                    }.padding(.vertical, 2)
                }
                if isPreparingRecommendation || locationService.isLoading {
                    HStack(spacing: 8) { ProgressView(); Text("Checking your route…").font(.footnote).foregroundStyle(.secondary) }
                }
                if let routeMessage { Text(routeMessage).font(.footnote).foregroundStyle(.secondary) }
                Button { Task { await prepareRecommendation() } } label: {
                    Text(isPreparingRecommendation ? "Checking route…" : "Check my trip").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).tint(.green)
                .disabled(isPreparingRecommendation)
            }.padding()
        }
        .navigationTitle("EV Decision").navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $recommendation) { RecommendationView(recommendation: $0) }
        .sheet(isPresented: $showsAutocomplete) { GooglePlaceAutocompleteView(isPresented: $showsAutocomplete) { selectedPlace = $0 } }
    }

    @MainActor
    private func prepareRecommendation() async {
        guard let selectedPlace else {
            routeMessage = "Choose a destination to check your trip."
            return
        }
        isPreparingRecommendation = true
        routeMessage = nil
        var routeData: RouteData?
        do {
            let origin = try await locationService.currentCoordinate()
            let destination = CLLocationCoordinate2D(latitude: selectedPlace.latitude, longitude: selectedPlace.longitude)
            switch await routeService.route(from: origin, to: destination) {
            case .success(let data): routeData = data
            case .failure(let failure): routeMessage = failure.localizedDescription
            }
        } catch {
            routeMessage = error.localizedDescription
        }
        recommendation = engine.recommendation(for: TripInput(batteryPercentage: Int(batteryPercentage), destination: selectedPlace, reserveBattery: reserveBattery, preferredChargeLimit: preferredChargeLimit, routeData: routeData))
        isPreparingRecommendation = false
    }
}
