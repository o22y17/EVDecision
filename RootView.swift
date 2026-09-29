import SwiftUI
struct RootView: View {
    var body: some View {
        TabView {
            NavigationStack { dailyContent }.tabItem { Label("Daily", systemImage: "bolt.car") }
            NavigationStack { JourneyView() }.tabItem { Label("Journey", systemImage: "map") }
            NavigationStack { SettingsView() }.tabItem { Label("Settings", systemImage: "gearshape") }
        }.tint(EVStyle.accent)
            .groupBoxStyle(EVGroupBoxStyle())
    }

    @ViewBuilder private var dailyContent: some View {
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--preview-itinerary") {
            RecommendationView(recommendation: .itineraryPreview)
                .safeAreaInset(edge: .top) {
                    Label("Sample plan · Not for driving", systemImage: "testtube.2")
                        .font(.caption.weight(.semibold)).frame(maxWidth: .infinity).padding(8)
                        .foregroundStyle(EVStyle.warning)
                        .background(EVStyle.warning.opacity(0.12), ignoresSafeAreaEdges: [])
                }
        } else { HomeView() }
#else
        HomeView()
#endif
    }
}

enum EVStyle {
    static let accent = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 0.36, green: 0.84, blue: 0.70, alpha: 1) : UIColor(red: 0.07, green: 0.40, blue: 0.33, alpha: 1) })
    static let warning = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 1, green: 0.76, blue: 0.38, alpha: 1) : UIColor(red: 0.55, green: 0.32, blue: 0.05, alpha: 1) })
    static let canvas = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 0.07, green: 0.10, blue: 0.10, alpha: 1) : UIColor(red: 0.96, green: 0.97, blue: 0.95, alpha: 1) })
    static let surface = Color(uiColor: .secondarySystemGroupedBackground)
}

struct EVGroupBoxStyle: GroupBoxStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            configuration.label.font(.headline).foregroundStyle(EVStyle.accent)
            configuration.content
        }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .background(EVStyle.surface, in: RoundedRectangle(cornerRadius: 22))
    }
}
