import Foundation
import CoreLocation
import SwiftUI

/// RF observation kinds. WiFi rows are only ever produced by imported rig CSVs;
/// iOS exposes no API for WiFi/BSSID scanning. BLE is recorded natively.
enum ObservationType: String, Codable, Sendable, CaseIterable {
    case wifi = "WIFI"
    case ble = "BLE"
    case bt = "BT"

    var title: String {
        switch self {
        case .wifi: "Wi-Fi"
        case .ble: "BLE"
        case .bt: "Bluetooth"
        }
    }
}

/// A single RF sighting: one WiFi network (imported) or one BLE peripheral (live scan).
struct Sighting: Identifiable, Codable, Sendable, Hashable {
    var id: UUID = UUID()
    var type: ObservationType
    /// BSSID for WiFi, peripheral UUID string for BLE (CoreBluetooth never exposes BLE MACs).
    var mac: String
    /// SSID or BLE local name; empty when the device does not advertise one.
    var name: String
    var authMode: String
    var firstSeen: Date
    var channel: Int
    var rssi: Int
    var latitude: Double
    var longitude: Double
    var altitudeMeters: Double
    var accuracyMeters: Double

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var displayName: String {
        name.isEmpty ? "Unknown device" : name
    }

    var hasFix: Bool {
        latitude != 0 || longitude != 0
    }
}
