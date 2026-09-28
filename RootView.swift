import SwiftUI
struct RootView: View {
    var body: some View {
        TabView {
            NavigationStack { dailyContent }.tabItem { Label("Daily", systemImage: "bolt.car") }
            NavigationStack { JourneyView() }.tabItem { Label("Journey", systemImage: "map") }
            NavigationStack { SettingsView() }.tabItem { Label("Settings", systemImage: "gearshape") }
        }.tint(.green)
    }

    @ViewBuilder private var dailyContent: some View {
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--preview-itinerary") {
            RecommendationView(recommendation: .itineraryPreview)
                .safeAreaInset(edge: .top) { Text("SAMPLE PLAN · NOT FOR DRIVING").font(.caption.weight(.semibold)).frame(maxWidth: .infinity).padding(8).background(.yellow).foregroundStyle(.black) }
        } else { HomeView() }
#else
        HomeView()
#endif
    }
}
