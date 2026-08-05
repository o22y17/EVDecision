import Foundation

struct SelectedPlace: Identifiable, Hashable {
    let id: String
    let name: String
    let latitude: Double
    let longitude: Double

    init(name: String, latitude: Double, longitude: Double) {
        self.id = "\(latitude),\(longitude),\(name)"
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
    }
}
