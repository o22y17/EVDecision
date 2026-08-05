import SwiftUI
struct JourneyView: View { var body: some View { ContentUnavailableView("Long-trip planning", systemImage: "map", description: Text("Route-aware charging stops will appear here.")).navigationTitle("Journey").navigationBarTitleDisplayMode(.inline) } }
