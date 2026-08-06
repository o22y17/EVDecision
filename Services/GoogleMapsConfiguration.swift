import Foundation
import GoogleMaps
import GooglePlaces

@MainActor
enum GoogleMapsConfiguration {
    static var isConfigured: Bool {
        guard let key = Bundle.main.object(forInfoDictionaryKey: "GoogleMapsAPIKey") as? String else {
            return false
        }
        let trimmedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedKey.hasPrefix("AIza")
            && trimmedKey.count >= 35
            && !trimmedKey.contains("$(")
            && !trimmedKey.contains("REPLACE_WITH")
    }

    static func configure() {
        guard isConfigured,
              let key = Bundle.main.object(forInfoDictionaryKey: "GoogleMapsAPIKey") as? String else {
            return
        }
        GMSServices.provideAPIKey(key)
        GMSPlacesClient.provideAPIKey(key)
    }
}
