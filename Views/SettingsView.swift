import SwiftUI

struct SettingsView: View {
    @AppStorage("vehicleName") private var vehicleName = "My EV"
    @AppStorage("reserveBattery") private var reserveBattery = 20
    @AppStorage("preferredFastChargeLimit") private var preferredFastChargeLimit = 80
    @AppStorage("minimumChargingPowerKW") private var minimumChargingPowerKW = 50
    @AppStorage("chargingNetworks") private var chargingNetworks = ""
    private let networks = ["TESLA", "TRUGO", "ZES", "ESARJ", "SHARZ", "OTOJET", "VOLTRUN"]
    var body: some View {
        Form {
            Section("Charging preferences") {
                Picker("Minimum power", selection: $minimumChargingPowerKW) {
                    ForEach([20, 50, 100, 150, 200, 250, 300], id: \.self) { power in
                        Text("\(power) kW or more").tag(power)
                    }
                }
                Toggle("All supported networks", isOn: Binding(
                    get: { chargingNetworks.isEmpty },
                    set: { chargingNetworks = $0 ? "" : "TESLA" }
                ))
                ForEach(networks, id: \.self) { network in
                    Toggle(network == "ESARJ" ? "Eşarj" : network, isOn: Binding(
                        get: { chargingNetworks.isEmpty || chargingNetworks.split(separator: ",").contains(Substring(network)) },
                        set: { enabled in
                            var selected = Set(chargingNetworks.isEmpty ? networks : chargingNetworks.components(separatedBy: ","))
                            if enabled { selected.insert(network) } else { selected.remove(network) }
                            chargingNetworks = selected.isEmpty ? "NONE" : selected.sorted().joined(separator: ",")
                        }
                    ))
                }
                Text("Filters apply to stations returned by our data source. Coverage and live availability vary by network.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("Vehicle") {
                TextField("Vehicle name", text: $vehicleName).textInputAutocapitalization(.words)
            }
            Section("Arrival and charging") {
                Stepper("Keep \(reserveBattery)% at arrival", value: $reserveBattery, in: 5...50, step: 5)
                Stepper("Charge up to \(preferredFastChargeLimit)%", value: $preferredFastChargeLimit, in: 50...100, step: 5)
            }
#if DEBUG
            Section("Developer") {
                NavigationLink("Charging data diagnostics") { ChargingDiagnosticsView() }
            }
#endif
        }.navigationTitle("Settings").navigationBarTitleDisplayMode(.inline)
    }
}
