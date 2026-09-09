import Foundation
import CoreLocation

/// One GPS fix on a drive's track.
struct TrackPoint: Codable, Sendable, Hashable {
    var latitude: Double
    var longitude: Double
    var altitude: Double
    var timestamp: Date

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

/// Live GPS sample used by the BLE scanner. Not persisted.
struct LocationFix: Sendable {
    var latitude: Double
    var longitude: Double
    var altitude: Double
    var accuracy: Double
}

extension Array where Element == TrackPoint {
    var pathDistance: CLLocationDistance {
        guard count > 1 else { return 0 }
        var total: CLLocationDistance = 0
        for index in 1..<count {
            let from = CLLocation(latitude: self[index - 1].latitude, longitude: self[index - 1].longitude)
            let to = CLLocation(latitude: self[index].latitude, longitude: self[index].longitude)
            total += from.distance(from: to)
        }
        return total
    }
}

/// A saved drive or an imported rig capture: GPS track plus RF observations.
struct Capture: Identifiable, Codable, Sendable, Hashable {
    var id: UUID = UUID()
    var name: String
    var startedAt: Date
    var endedAt: Date
    var track: [TrackPoint]
    var observations: [Sighting]

    var duration: TimeInterval {
        endedAt.timeIntervalSince(startedAt)
    }

    var wifiCount: Int { observations.count { $0.type == .wifi } }
    var bleCount: Int { observations.count { $0.type == .ble || $0.type == .bt } }

    var distanceMeters: Double { track.pathDistance }
}
