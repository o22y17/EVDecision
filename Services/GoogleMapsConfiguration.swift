import Foundation
import GoogleMaps
import GooglePlaces

@MainActor
enum GoogleMapsConfiguration {
    static var isConfigured: Bool {
        guard let key = Bundle.main.object(forInfoDictionaryKey: "GoogleMapsAPIKey") as? String else {
            return false
        }
        return !key.isEmpty && !key.contains("$(") && !key.contains("REPLACE_WITH")
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
