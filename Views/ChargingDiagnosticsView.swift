import SwiftUI

#if DEBUG
struct ChargingDiagnosticsView: View {
    @State private var snapshot: ChargingDataSnapshot?
    @State private var isLoading = false
    private let service = ChargingDataService(providers: [EPDKChargingProvider(), OpenChargeMapProvider()])

    var body: some View {
        List {
            Section("Charging data diagnostics") {
                Text("Developer-only. This does not affect recommendations.").font(.footnote).foregroundStyle(.secondary)
                Button(isLoading ? "Loading…" : "Fetch sample data") { Task { await load() } }.disabled(isLoading)
            }
            if let snapshot {
                Section("Summary") {
                    row("Stations fetched", "\(snapshot.stations.count)")
                    row("Sources", snapshot.sources.map(\.rawValue).joined(separator: ", "))
                    row("Checked on device", snapshot.timestamp.formatted(date: .abbreviated, time: .shortened))
                    ForEach(snapshot.partialFailures, id: \.self) { Text($0).font(.footnote) }
                }
                Section("Normalized stations") {
                    ForEach(snapshot.stations) { station in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(station.name).font(.subheadline.weight(.semibold))
                            Text("\(station.source.rawValue) · \(station.dataConfidence.rawValue) confidence").font(.footnote).foregroundStyle(.secondary)
                            Text(station.units.map { "\($0.maximumPowerKW.map { String(format: "%.0f kW", $0) } ?? "Unknown power") · \($0.status.rawValue)" }.joined(separator: "\n")).font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }.navigationTitle("Charging diagnostics").navigationBarTitleDisplayMode(.inline)
    }

    private func load() async {
        isLoading = true
        snapshot = await service.stations(near: 41.0082, longitude: 28.9784, radiusKilometers: 10)
        isLoading = false
    }

    private func row(_ label: String, _ value: String) -> some View { HStack { Text(label); Spacer(); Text(value).multilineTextAlignment(.trailing).foregroundStyle(.secondary) } }
}
#endif
