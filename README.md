# Spectrecon Field

Mobile companion to [spectrecon](../spectrecon) (RF licensing-intelligence CLI).
A wardriving field tool: record drives (GPS track + BLE observations), export
WiGLE-format CSV, import CSVs from ESP32 rigs via the share sheet or Files, and
debrief captures on a map.

iOS 18+, SwiftUI, iPhone. No third-party dependencies.

## The iOS WiFi restriction (read this first)

iOS has **no public API for WiFi scanning or BSSID enumeration**.
`NEHotspotHelper` requires a special Apple entitlement that is effectively
unavailable for this kind of app. So:

- **CoreLocation** provides the GPS track, including in the background
  (When-In-Use, then Always, plus `location` background mode) while a drive is recording.
- **CoreBluetooth** provides full BLE scanning — peripheral UUID, advertised
  name, RSSI. Advertised Meshtastic / MeshCore / Biscuit rigs are tagged in
  the WiGLE `AuthMode` column (`[MESH:meshtastic]`, `[MESH:meshcore]`,
  `[RIG:biscuit]`) without connecting. This *is* RF wardriving data and works
  natively.
- **WiFi capture is not possible on-device.** WiFi rows arrive by importing
  WiGLE CSVs from external rigs (ESP32 etc.) via the share sheet or Files, and
  are fully supported for debrief and re-export.

Note: CoreBluetooth never exposes BLE MAC addresses, so the `MAC` column for
BLE rows carries the stable CoreBluetooth peripheral UUID instead.

## Open and run

```sh
cd spectrecon-field
xcodegen
open SpectreconField.xcodeproj
```

Or build from the CLI:

```sh
xcodegen
xcodebuild -project SpectreconField.xcodeproj -scheme SpectreconField \
  -destination 'platform=iOS Simulator,name=iPhone 17' build
xcodebuild -project SpectreconField.xcodeproj -scheme SpectreconField \
  -destination 'platform=iOS Simulator,name=iPhone 17' test
```

## Features

- **Drive** — full-bleed dark map, live GPS track polyline, live BLE sighting
  dots colored by RSSI, floating status strip (recording pulse, duration,
  observation count), bottom stats (devices / distance / GPS accuracy).
  Start Drive; hold-to-confirm (2s) to stop; success haptic on save.
  Tap the observation count for a live log sheet. Denied location/Bluetooth
  surfaces a card with a Settings jump.
- **Captures** — saved drives and imported captures with stats, swipe to
  delete, export WiGLE CSV via the share sheet, import `.csv` from Files,
  zoom transition into debrief.
- **Debrief** — map with RSSI-colored observation dots over the drive track,
  segmented All / Wi-Fi / BLE filter, searchable list (SSID / name / MAC).
- **WiGLE CSV v1.4** — exports with the proper `WigleWifi-1.4` metadata line
  and `MAC,SSID,AuthMode,FirstSeen,Channel,RSSI,CurrentLatitude,
  CurrentLongitude,AltitudeMeters,AccuracyMeters,Type` header; imports the
  same format.

## Layout

```
Sources/
  SpectreconFieldApp.swift      app entry, tabs, environment wiring, open-URL import
  Models/
    Sighting.swift              RF sighting (type, MAC, name, RSSI, position)
    Capture.swift               saved drive/import: track + observations + stats
  Services/
    LocationService.swift       CLLocationManager, background-capable track recording
    BLEScannerService.swift     CBCentralManager BLE scan, dedupe by peripheral UUID
    CaptureStore.swift          JSON persistence in Application Support, import/export
    WigleCSV.swift              WiGLE CSV v1.4 parser/serializer
  Views/
    DriveMapView.swift          map-first recording screen + About sheet
    CapturesListView.swift      capture list, delete, share, import
    CaptureDetailView.swift     debrief map + filterable searchable list
    Components/
      DesignSystem.swift        Spacing grid, corner-radius lock, content colors, motion
      Components.swift          SightingDot, ElapsedTimeText, StatItem,
                                HoldToConfirmButton, StatusCard, ActivityView
Support/Info.plist              location + Bluetooth usage strings, background modes
Assets.xcassets                 AccentColor (#32ADE6) + AppIcon
project.yml                     xcodegen spec (bundle id com.spectrecon.field)
```

## Roadmap

- **BLE → Meshtastic rig bridge**: subscribe to a Meshtastic node's BLE service
  so an ESP32 rig can stream WiFi scan results into the app live during a drive
  (also gives background scanning the service-UUID filter it needs).
- **On-device debrief against the spectrecon DuckDB** via duckdb-swift: run
  licensing-intelligence queries against imported captures without leaving
  the field.
- **Lilyshark T-Deck `.lscap`**: LoRa captures from the deck import on the
  CLI (`spectrecon import capture.lscap`) and join heard Meshtastic node IDs
  to `mesh.nodes`. Field tags the deck's BLE name `Lilyshark <short>` as
  `[RIG:lilyshark]` and shows the node-number suffix (`4B01` → LoRa
  `!****4B01`) so a drive CSV and a T-Deck capture debrief as one identity.
