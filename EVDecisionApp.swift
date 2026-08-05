import SwiftUI

@main
struct EVDecisionApp: App {
    init() {
        GoogleMapsConfiguration.configure()
    }

    var body: some Scene {
        WindowGroup { RootView() }
    }
}
