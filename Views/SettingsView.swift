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
        }.navigationTitle("Settings").navigationBarTitleDisplayMode(.inline)
    }
}
