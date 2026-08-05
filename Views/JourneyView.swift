import SwiftUI

struct JourneyView: View {
    var body: some View {
        ContentUnavailableView("Plan a longer trip", systemImage: "map", description: Text("Your suggested charging stops will appear here."))
            .navigationTitle("Journey")
            .navigationBarTitleDisplayMode(.inline)
    }
}
