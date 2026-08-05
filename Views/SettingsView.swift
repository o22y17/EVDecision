import SwiftUI

struct SettingsView: View {
    @AppStorage("vehicleName") private var vehicleName = "My EV"
    @AppStorage("reserveBattery") private var reserveBattery = 20
    @AppStorage("preferredFastChargeLimit") private var preferredFastChargeLimit = 80
    var body: some View {
        Form {
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
