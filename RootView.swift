import SwiftUI
struct RootView: View { var body: some View { TabView { NavigationStack { HomeView() }.tabItem { Label("Daily", systemImage: "bolt.car") }; NavigationStack { JourneyView() }.tabItem { Label("Journey", systemImage: "map") }; NavigationStack { SettingsView() }.tabItem { Label("Settings", systemImage: "gearshape") } }.tint(.green) } }
