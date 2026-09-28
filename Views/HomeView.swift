import CoreLocation
import MapKit
import SwiftUI

struct HomeView: View {
    @AppStorage("reserveBattery") private var reserveBattery = 20
    @AppStorage("preferredFastChargeLimit") private var preferredChargeLimit = 80
    @State private var batteryPercentage = 62.0
    @State private var selectedPlace: SelectedPlace?
    @State private var destinationQuery = ""
    @State private var destinationResults: [MKMapItem] = []
    @State private var isSearchingDestinations = false
    @State private var destinationSearchTask: Task<Void, Never>?
    @FocusState private var destinationIsFocused: Bool
    @State private var recommendation: ChargingRecommendation?
    @State private var isPreparingRecommendation = false
    @State private var routeMessage: String?
    @StateObject private var locationService = LocationService()

    private let engine = DecisionEngineV1()
    private let routeService = GoogleRoutesService()
    private let chargingDataService = ChargingDataService(providers: [EPDKChargingProvider()])
    private let tripPlanner = RoadTripPlanner()

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
                        HStack(spacing: 8) {
                            Image(systemName: "magnifyingglass").foregroundStyle(.green)
                            TextField("Where are you going?", text: $destinationQuery)
                                .textInputAutocapitalization(.words)
                                .autocorrectionDisabled()
                                .focused($destinationIsFocused)
                                .onChange(of: destinationQuery) { _, newValue in scheduleDestinationSearch(for: newValue) }
                            if isSearchingDestinations { ProgressView().controlSize(.small) }
                        }
                        .padding(10)
                        .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 8))

                        if !destinationResults.isEmpty {
                            VStack(spacing: 0) {
                                ForEach(Array(destinationResults.prefix(5)), id: \.self) { item in
                                    Button { selectDestination(item) } label: {
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(item.name ?? "Selected place").foregroundStyle(.primary)
                                            if let address = item.placemark.title {
                                                Text(address).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
                                            }
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.vertical, 9)
                                    }
                                    .buttonStyle(.plain)
                                    if item != destinationResults.prefix(5).last { Divider() }
                                }
                            }
                        }
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
        .onDisappear { destinationSearchTask?.cancel() }
    }

    private func scheduleDestinationSearch(for text: String) {
        destinationSearchTask?.cancel()
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if selectedPlace?.name != trimmedText { selectedPlace = nil }
        guard trimmedText.count >= 2 else {
            destinationResults = []
            isSearchingDestinations = false
            return
        }
        destinationSearchTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            isSearchingDestinations = true
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = trimmedText
            do {
                let response = try await MKLocalSearch(request: request).start()
                guard !Task.isCancelled else { return }
                destinationResults = response.mapItems
            } catch {
                guard !Task.isCancelled else { return }
                destinationResults = []
            }
            isSearchingDestinations = false
        }
    }

    private func selectDestination(_ item: MKMapItem) {
        let place = SelectedPlace(name: item.name ?? item.placemark.title ?? "Selected place", latitude: item.placemark.coordinate.latitude, longitude: item.placemark.coordinate.longitude)
        selectedPlace = place
        destinationQuery = place.name
        destinationResults = []
        destinationSearchTask?.cancel()
        destinationIsFocused = false
    }

    @MainActor
    private func prepareRecommendation() async {
        guard let selectedPlace else {
            routeMessage = "Choose a destination to check your trip."
            return
        }
        isPreparingRecommendation = true
        let batteryPercentage = self.batteryPercentage
        let reserveBattery = self.reserveBattery
        let preferredChargeLimit = self.preferredChargeLimit
        routeMessage = nil
        var routeData: RouteData?
        var originPoint: RoutePoint?
        do {
            let origin = try await locationService.currentCoordinate()
            originPoint = RoutePoint(latitude: origin.latitude, longitude: origin.longitude)
            let destination = CLLocationCoordinate2D(latitude: selectedPlace.latitude, longitude: selectedPlace.longitude)
            switch await routeService.route(from: origin, to: destination) {
            case .success(let data): routeData = data
            case .failure(let failure): routeMessage = failure.localizedDescription
            }
        } catch {
            routeMessage = error.localizedDescription
        }
        let base = engine.recommendation(for: TripInput(batteryPercentage: Int(batteryPercentage), destination: selectedPlace, reserveBattery: reserveBattery, preferredChargeLimit: preferredChargeLimit, routeData: routeData))
        var itinerary: ChargingItinerary?
        if base.decision == .chargeNow, let routeData, let originPoint {
            let corridor = RouteCorridor(origin: originPoint, destination: RoutePoint(latitude: selectedPlace.latitude, longitude: selectedPlace.longitude), polyline: routeData.polyline, radiusKilometers: 12)
            let snapshot = await chargingDataService.stations(in: corridor)
            routeMessage = snapshot.partialFailures.isEmpty ? routeMessage : snapshot.partialFailures.joined(separator: "\n")
            let verified = await tripPlanner.verifiedItinerary(stations: snapshot.stations, route: routeData, battery: Int(batteryPercentage), reserve: reserveBattery, preferredLimit: preferredChargeLimit, origin: originPoint, destination: RoutePoint(latitude: selectedPlace.latitude, longitude: selectedPlace.longitude), service: routeService)
            itinerary = verified.itinerary
            if let message = verified.message { routeMessage = [routeMessage, message].compactMap { $0 }.joined(separator: "\n") }
            if itinerary == nil {
                routeMessage = routeMessage ?? "No suitable charging stop was found in the available station data."
            }
        }
        recommendation = ChargingRecommendation(decision: base.decision, arrivalBattery: base.arrivalBattery, reserveBattery: base.reserveBattery, incrementalTimeCostMinutes: base.incrementalTimeCostMinutes, destination: base.destination, explanation: base.explanation, confidence: base.confidence, routeData: base.routeData, usedLiveRouteData: base.usedLiveRouteData, chargingStop: nil, routeIssue: routeMessage, itinerary: itinerary)
        isPreparingRecommendation = false
    }
}
