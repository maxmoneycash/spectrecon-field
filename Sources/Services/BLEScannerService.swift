import Foundation
import CoreBluetooth

/// Native RF capture on iOS: full BLE scan (peripheral UUID, local name, RSSI).
/// Dedupes by peripheral UUID, keeping firstSeen and the latest RSSI/position.
@MainActor
@Observable
final class BLEScannerService: NSObject {
    @ObservationIgnored private var central: CBCentralManager!
    /// Wired up by the app root so sightings can be stamped with the current GPS fix.
    @ObservationIgnored var locationProvider: (@MainActor () -> LocationFix?)?
    @ObservationIgnored private var pendingScan = false

    private(set) var state: CBManagerState = .unknown
    private(set) var isScanning = false
    private(set) var sightings: [UUID: Sighting] = [:]

    var sightingCount: Int { sightings.count }

    var sortedSightings: [Sighting] {
        sightings.values.sorted { $0.rssi > $1.rssi }
    }

    var isUnavailable: Bool {
        state == .unauthorized || state == .poweredOff || state == .unsupported
    }

    override init() {
        super.init()
        central = CBCentralManager(
            delegate: self,
            queue: nil,
            options: [CBCentralManagerOptionRestoreIdentifierKey: "com.spectrecon.field.ble-central"]
        )
    }

    func startScanning() {
        guard state == .poweredOn else {
            pendingScan = true
            return
        }
        central.scanForPeripherals(
            withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
        )
        isScanning = true
    }

    func stopScanning() {
        pendingScan = false
        central.stopScan()
        isScanning = false
    }

    func reset() {
        sightings.removeAll()
    }

    fileprivate func applyCentralState(_ state: CBManagerState) {
        self.state = state
        if state == .poweredOn, pendingScan {
            startScanning()
        } else if state != .poweredOn {
            isScanning = false
        }
    }

    private func recordSighting(id: UUID, name: String?, rssi: Int) {
        let location = locationProvider?()
        if var existing = sightings[id] {
            var changed = false
            if abs(existing.rssi - rssi) >= 2 {
                existing.rssi = rssi
                changed = true
            }
            if let name, !name.isEmpty, name != existing.name {
                existing.name = name
                changed = true
            }
            if let location {
                let moved = abs(existing.latitude - location.latitude) > 0.00005
                    || abs(existing.longitude - location.longitude) > 0.00005
                    || !existing.hasFix
                if moved {
                    existing.latitude = location.latitude
                    existing.longitude = location.longitude
                    existing.altitudeMeters = location.altitude
                    existing.accuracyMeters = location.accuracy
                    changed = true
                }
            }
            if changed {
                sightings[id] = existing
            }
        } else {
            sightings[id] = Sighting(
                type: .ble,
                mac: id.uuidString,
                name: name ?? "",
                authMode: "[BLE]",
                firstSeen: .now,
                channel: 0,
                rssi: rssi,
                latitude: location?.latitude ?? 0,
                longitude: location?.longitude ?? 0,
                altitudeMeters: location?.altitude ?? 0,
                accuracyMeters: location?.accuracy ?? 0
            )
        }
    }
}

extension BLEScannerService: CBCentralManagerDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        let state = central.state
        Task { @MainActor in
            self.applyCentralState(state)
        }
    }

    nonisolated func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        // CBPeripheral is not Sendable; extract Sendable values before hopping actors.
        let id = peripheral.identifier
        let advertised = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        let name = peripheral.name ?? advertised
        let value = RSSI.intValue
        guard value != 127 else { return } // 127 = RSSI not available
        Task { @MainActor in
            self.recordSighting(id: id, name: name, rssi: value)
        } as Task<Void, Never>
    }

    nonisolated func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
        // State restoration is opt-in via the restore identifier; nothing to restore yet.
    }
}
