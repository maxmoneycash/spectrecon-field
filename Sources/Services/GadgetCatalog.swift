import Foundation

/// Passive fingerprints for well-known RF gadgets and audit rigs.
/// Identification only: advertised names and BLE service UUIDs, no pairing.
struct GadgetHit: Equatable, Sendable {
    let id: String
    let label: String
    let family: String
    let authMode: String
    /// Firmware BLE/mesh short name (`Lilyshark 4B01` → `4B01`).
    /// Low 16 bits of the Meshtastic node number; joins LoRa `!xxxx4B01`.
    let nodeSuffix: String?
}

enum GadgetCatalog {
    static let meshtasticServiceUUID = "6BA1B218-15A8-461F-9FA8-5DCAE273EAFD"
    static let nordicUARTServiceUUID = "6E400001-B5A3-F393-E0A9-E50E24DCCA9E"
    static let biscuitServiceUUID = "4FAFC201-1FB5-459E-8FCC-C5C9C331914B"
    /// Lilyshark analyzer GATT (docs/lsk-ble-contract.md). Firmware still
    /// primarily advertises Meshtastic's service; the local name is the tell.
    static let lilysharkLSKServiceUUID = "6C736B00-9C1D-4B7A-B3F2-1D0E5A7C4E10"
    static let flipperSerialUUID = "8FE5B3D5-2E7F-4A98-2A48-7ACC60FE0000"
    /// Flipper Zero color 16-bit UUIDs (black / white / transparent).
    static let flipperColorUUIDs: Set<String> = [
        "00003081-0000-1000-8000-00805F9B34FB",
        "00003082-0000-1000-8000-00805F9B34FB",
        "00003083-0000-1000-8000-00805F9B34FB",
    ]

    static func identify(name: String?, serviceUUIDs: [String]) -> GadgetHit? {
        let raw = name ?? ""
        let lowered = raw.lowercased()
        let uuids = Set(serviceUUIDs.map { $0.uppercased() })

        if uuids.contains(where: { flipperColorUUIDs.contains($0) })
            || uuids.contains(flipperSerialUUID)
            || lowered.contains("flipper") {
            return hit("flipper", "Flipper Zero", "gadget", "[GADGET:flipper]")
        }
        if lowered.contains("pineapple") {
            return hit("pineapple", "Hak5 WiFi Pineapple", "gadget", "[GADGET:pineapple]")
        }
        if lowered.contains("pwnagotchi") {
            return hit("pwnagotchi", "Pwnagotchi", "gadget", "[GADGET:pwnagotchi]")
        }
        if lowered.contains("deauther") || lowered.contains("dstike") || lowered.contains("spacehuhn") {
            return hit("deauther", "ESP8266/ESP32 Deauther", "gadget", "[GADGET:deauther]")
        }
        if lowered.contains("marauder") {
            return hit("marauder", "ESP32 Marauder", "rig", "[RIG:marauder]")
        }
        if lowered.contains("ghostesp") || lowered.contains("ghost-esp") {
            return hit("ghostesp", "GhostESP", "rig", "[RIG:ghostesp]")
        }
        if lowered.contains("piglet") {
            return hit("piglet", "Piglet wardrive", "rig", "[RIG:piglet]")
        }
        if lowered.contains("hashmonster") || lowered.contains("hash-monster") {
            return hit("hashmonster", "ESP32 WiFi Hash Monster", "rig", "[RIG:hashmonster]")
        }
        if uuids.contains(biscuitServiceUUID) || raw == "Biscuit" {
            return hit("biscuit", "Biscuit wardrive rig", "rig", "[RIG:biscuit]")
        }
        if raw.hasPrefix("Lilyshark") || lowered.hasPrefix("lilyshark")
            || uuids.contains(lilysharkLSKServiceUUID) {
            return hit(
                "lilyshark",
                "Lilyshark T-Deck",
                "rig",
                "[RIG:lilyshark]",
                nodeSuffix: lilysharkShortName(from: raw)
            )
        }
        if uuids.contains(meshtasticServiceUUID) || raw.hasPrefix("Meshtastic_") || lowered.contains("meshtastic") {
            return hit("meshtastic", "Meshtastic node", "mesh", "[MESH:meshtastic]")
        }
        if raw.hasPrefix("MeshCore") {
            return hit("meshcore", "MeshCore node", "mesh", "[MESH:meshcore]")
        }
        if lowered.hasPrefix("rnode") {
            return hit("rnode", "Reticulum RNode", "mesh", "[MESH:rnode]")
        }
        if uuids.contains(nordicUARTServiceUUID) {
            return hit("uart", "Nordic UART", "rig", "[BLE:UART]")
        }
        if lowered.hasPrefix("omg") {
            return hit("omg", "O.MG cable / plug", "gadget", "[GADGET:omg]")
        }
        return nil
    }

    static func authMode(name: String?, serviceUUIDs: [String]) -> String {
        identify(name: name, serviceUUIDs: serviceUUIDs)?.authMode ?? "[BLE]"
    }

    /// Firmware advertises `Lilyshark %04X` (space) and names the node
    /// `Lilyshark-%04X`. The four hex digits are `node_num & 0xffff`.
    static func lilysharkShortName(from name: String) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        for separator in [" ", "-", "_"] {
            let prefix = "Lilyshark" + separator
            guard trimmed.count == prefix.count + 4,
                  trimmed.lowercased().hasPrefix(prefix.lowercased()) else {
                continue
            }
            let suffix = String(trimmed.suffix(4))
            if suffix.allSatisfy(\.isHexDigit) {
                return suffix.uppercased()
            }
        }
        return nil
    }

    private static func hit(
        _ id: String,
        _ label: String,
        _ family: String,
        _ auth: String,
        nodeSuffix: String? = nil
    ) -> GadgetHit {
        GadgetHit(id: id, label: label, family: family, authMode: auth, nodeSuffix: nodeSuffix)
    }
}
