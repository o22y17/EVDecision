import CoreLocation
import SwiftUI

struct JourneyView: View {
    @AppStorage("reserveBattery") private var reserveBattery = 20
    @AppStorage("preferredFastChargeLimit") private var preferredChargeLimit = 80
    @State private var batteryPercentage = 62.0
    @State private var selectedPlace: SelectedPlace?
    @State private var recommendation: ChargingRecommendation?
    @State private var showsDestinationSearch = false
    @State private var isChecking = false
    @State private var routeMessage: String?
    @StateObject private var locationService = LocationService()

    private let engine = DecisionEngineV1()
    private let routeService = GoogleRoutesService()
    private let chargingService = ChargingDataService(providers: [EPDKChargingProvider()])
    private let planner = RoadTripPlanner()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Label("A little further, well planned", systemImage: "map.fill")
                        .font(.title2.weight(.semibold)).fontDesign(.rounded).foregroundStyle(EVStyle.accent)
                    Text("Check whether your current battery can cover the journey safely.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                GroupBox("Starting battery") {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Charge right now")
                            Spacer()
                            Text("\(Int(batteryPercentage))%")
                                .font(.headline.monospacedDigit())
                                .foregroundStyle(EVStyle.accent)
                        }
                        Slider(value: $batteryPercentage, in: 0...100, step: 1)
                            .tint(EVStyle.accent).accessibilityLabel("Starting battery percentage")
                    }
                    .padding(.vertical, 2)
                }

                GroupBox("Journey destination") {
                    VStack(alignment: .leading, spacing: 10) {
                        Button { showsDestinationSearch = true } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "magnifyingglass")
                                Text(selectedPlace?.name ?? "Where are you going?")
                                    .foregroundStyle(selectedPlace == nil ? .secondary : .primary)
                                    .lineLimit(2)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                            .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 8))
                        }
                        Text("Arrival reserve: \(reserveBattery)%")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }

                if isChecking || locationService.isLoading {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Checking your journey…")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                if let routeMessage {
                    Text(routeMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Button { Task { await checkJourney() } } label: {
                    Label(isChecking ? "Checking journey…" : "Check my journey", systemImage: "arrow.right.circle.fill")
                        .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.roundedRectangle(radius: 16)).tint(EVStyle.accent)
                .disabled(isChecking)

                Text("The complete charging plan uses your entered battery level, not live vehicle data.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
        .background(EVStyle.canvas)
        .navigationTitle("Journey")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $recommendation) {
            RecommendationView(recommendation: $0)
        }
        .sheet(isPresented: $showsDestinationSearch) {
            GooglePlaceAutocompleteView(isPresented: $showsDestinationSearch) {
                selectedPlace = $0
            }
        }
    }

    @MainActor
    private func checkJourney() async {
        guard let selectedPlace else {
            routeMessage = "Choose a destination to check your journey."
            return
        }

        isChecking = true
        let batteryPercentage = self.batteryPercentage
        let reserveBattery = self.reserveBattery
        let preferredChargeLimit = self.preferredChargeLimit
        routeMessage = nil
        var routeData: RouteData?
        var originPoint: RoutePoint?

        do {
            let origin = try await locationService.currentCoordinate()
            originPoint = RoutePoint(latitude: origin.latitude, longitude: origin.longitude)
            let destination = CLLocationCoordinate2D(
                latitude: selectedPlace.latitude,
                longitude: selectedPlace.longitude
            )
            switch await routeService.route(from: origin, to: destination) {
            case .success(let data):
                routeData = data
            case .failure(let failure):
                routeMessage = "Live route unavailable. Using a conservative basic estimate. \(failure.localizedDescription)"
            }
        } catch {
            routeMessage = "Current location unavailable. Using a conservative basic estimate. \(error.localizedDescription)"
        }

        let base = engine.recommendation(
            for: TripInput(
                batteryPercentage: Int(batteryPercentage),
                destination: selectedPlace,
                reserveBattery: reserveBattery,
                preferredChargeLimit: preferredChargeLimit,
                routeData: routeData
            )
        )
        var itinerary: ChargingItinerary?
        if base.decision == .chargeNow, let routeData, let originPoint {
            let destination = RoutePoint(latitude: selectedPlace.latitude, longitude: selectedPlace.longitude)
            let snapshot = await chargingService.stations(in: RouteCorridor(origin: originPoint, destination: destination, polyline: routeData.polyline, radiusKilometers: 12))
            let result = await planner.verifiedItinerary(stations: snapshot.stations, route: routeData, battery: Int(batteryPercentage), reserve: reserveBattery, preferredLimit: preferredChargeLimit, origin: originPoint, destination: destination, service: routeService)
            itinerary = result.itinerary
            let messages = snapshot.partialFailures + [result.message].compactMap { $0 }
            if !messages.isEmpty { routeMessage = messages.joined(separator: "\n") }
        }
        recommendation = ChargingRecommendation(decision: base.decision, arrivalBattery: base.arrivalBattery, reserveBattery: base.reserveBattery, incrementalTimeCostMinutes: base.incrementalTimeCostMinutes, destination: base.destination, explanation: base.explanation, confidence: base.confidence, routeData: base.routeData, usedLiveRouteData: base.usedLiveRouteData, chargingStop: nil, routeIssue: routeMessage, itinerary: itinerary)
        isChecking = false
    }
}
