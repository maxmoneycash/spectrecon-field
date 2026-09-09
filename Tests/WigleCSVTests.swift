import XCTest
@testable import SpectreconField

final class WigleCSVTests: XCTestCase {
    let sample = """
    WigleWifi-1.4,appRelease=test,model=iPhone,release=1,device=test,display=x,board=x,brand=Apple
    MAC,SSID,AuthMode,FirstSeen,Channel,RSSI,CurrentLatitude,CurrentLongitude,AltitudeMeters,AccuracyMeters,Type
    24:6F:28:AA:BB:01,Testnet,[WPA2-PSK][ESS],2026-09-01 10:00:00,6,-45,34.0530000,-118.2460000,100.0,5.0,WIFI
    AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE,Meshtastic,[MESH:meshtastic],2026-09-01 10:01:00,0,-60,34.0531000,-118.2461000,100.0,8.0,BLE
    """

    func testParseCountsAndTypes() throws {
        let rows = try WigleCSV.parse(sample)
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[0].type, .wifi)
        XCTAssertEqual(rows[0].name, "Testnet")
        XCTAssertEqual(rows[1].type, .ble)
        XCTAssertEqual(rows[1].authMode, "[MESH:meshtastic]")
        XCTAssertEqual(rows[0].latitude, 34.053, accuracy: 0.0001)
    }

    func testQuotedCommaInSSID() throws {
        let csv = """
        WigleWifi-1.4
        MAC,SSID,AuthMode,FirstSeen,Channel,RSSI,CurrentLatitude,CurrentLongitude,AltitudeMeters,AccuracyMeters,Type
        AA:BB:CC:DD:EE:FF,"Shop, Annex",[ESS],2026-09-01 10:00:00,1,-50,34.0,-118.0,0.0,1.0,WIFI
        """
        let rows = try WigleCSV.parse(csv)
        XCTAssertEqual(rows[0].name, "Shop, Annex")
    }

    func testRejectsNonWigle() {
        XCTAssertThrowsError(try WigleCSV.parse("not a wigle file\n")) { error in
            XCTAssertEqual(error as? WigleCSV.CSVError, .notWigleFile)
        }
    }

    func testRoundTripPreservesMACAndType() throws {
        let original = try WigleCSV.parse(sample)
        let capture = Capture(
            name: "Roundtrip",
            startedAt: original.map(\.firstSeen).min() ?? .now,
            endedAt: original.map(\.firstSeen).max() ?? .now,
            track: [],
            observations: original
        )
        let serialized = WigleCSV.serialize(capture, deviceModel: "iPhone")
        XCTAssertTrue(serialized.hasPrefix("WigleWifi-1.4"))
        let again = try WigleCSV.parse(serialized)
        XCTAssertEqual(Set(again.map(\.mac)), Set(original.map(\.mac)))
        XCTAssertEqual(Set(again.map(\.type)), Set(original.map(\.type)))
    }

    func testClassifyMeshtastic() {
        XCTAssertEqual(
            BLEScannerService.classify(name: "Meshtastic_ab12", serviceUUIDs: []),
            "[MESH:meshtastic]"
        )
        XCTAssertEqual(
            BLEScannerService.classify(
                name: nil,
                serviceUUIDs: [BLEScannerService.meshtasticServiceUUID]
            ),
            "[MESH:meshtastic]"
        )
        XCTAssertEqual(
            BLEScannerService.classify(name: "MeshCore-cabin", serviceUUIDs: []),
            "[MESH:meshcore]"
        )
        XCTAssertEqual(
            BLEScannerService.classify(
                name: "ESP32",
                serviceUUIDs: [BLEScannerService.nordicUARTServiceUUID]
            ),
            "[BLE:UART]"
        )
        XCTAssertEqual(
            BLEScannerService.classify(name: "Biscuit", serviceUUIDs: []),
            "[RIG:biscuit]"
        )
        XCTAssertEqual(
            BLEScannerService.classify(name: "AirPods", serviceUUIDs: []),
            "[BLE]"
        )
    }
}
