import SwiftUI
import MapKit

/// Debrief: map with type-colored observation dots over the drive track,
/// a segmented All / Wi-Fi / BLE filter, and a searchable observation list.
struct CaptureDetailView: View {
    let capture: Capture

    @Environment(CaptureStore.self) private var store

    @State private var filter: DetailFilter = .all
    @State private var searchText = ""
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var share: SharePayload?

    enum DetailFilter: String, CaseIterable, Identifiable {
        case all = "All"
        case wifi = "Wi-Fi"
        case ble = "BLE"

        var id: Self { self }

        func matches(_ observation: Sighting) -> Bool {
            switch self {
            case .all: return true
            case .wifi: return observation.type == .wifi
            case .ble: return observation.type == .ble || observation.type == .bt
            }
        }
    }

    private var filteredObservations: [Sighting] {
        capture.observations
            .filter(filter.matches)
            .filter { observation in
                searchText.isEmpty
                    || observation.name.localizedCaseInsensitiveContains(searchText)
                    || observation.mac.localizedCaseInsensitiveContains(searchText)
            }
            .sorted { $0.rssi > $1.rssi }
    }

    var body: some View {
        VStack(spacing: 0) {
            Map(position: $cameraPosition) {
                if capture.track.count > 1 {
                    MapPolyline(coordinates: capture.track.map(\.coordinate))
                        .stroke(
                            Color.accentColor,
                            style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round)
                        )
                }
                ForEach(filteredObservations.filter(\.hasFix)) { observation in
                    Annotation(observation.displayName, coordinate: observation.coordinate) {
                        SightingDot(color: observation.rssi.rssiColor)
                    }
                }
            }
            .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll, showsTraffic: false))
            .mapControls { MapCompass() }
            .containerRelativeFrame(.vertical) { length, _ in max(220, length * 0.38) }

            Picker("Type", selection: $filter) {
                ForEach(DetailFilter.allCases) { filter in
                    Text(filter.rawValue).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.xs)

            List(filteredObservations) { observation in
                ObservationRow(observation: observation)
            }
            .listStyle(.plain)
            .overlay {
                if filteredObservations.isEmpty {
                    if searchText.isEmpty {
                        ContentUnavailableView(
                            "Nothing Here",
                            systemImage: "antenna.radiowaves.left.and.right",
                            description: Text(filter == .all
                                ? "No RF observations in this capture. BLE devices appear when Bluetooth is on; Wi-Fi arrives from an imported WiGLE CSV."
                                : "No \(filter.rawValue) observations in this capture.")
                        )
                    } else {
                        ContentUnavailableView.search(text: searchText)
                    }
                }
            }
        }
        .navigationTitle(capture.name)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "SSID, name, or MAC")
        .sensoryFeedback(.selection, trigger: filter)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Export WiGLE CSV", systemImage: "square.and.arrow.up") {
                    if let url = try? store.export(capture) {
                        share = SharePayload(url: url)
                    }
                }
            }
        }
        .sheet(item: $share) { payload in
            ActivityView(items: [payload.url])
                .presentationDetents([.medium, .large])
        }
        .onAppear {
            cameraPosition = .region(Self.region(fitting: capture))
        }
    }

    static func region(fitting capture: Capture) -> MKCoordinateRegion {
        var coordinates = capture.observations.filter(\.hasFix).map(\.coordinate)
        coordinates.append(contentsOf: capture.track.map(\.coordinate))
        guard let first = coordinates.first else {
            return MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 37.3349, longitude: -122.0090),
                span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
            )
        }
        var minLat = first.latitude, maxLat = first.latitude
        var minLon = first.longitude, maxLon = first.longitude
        for coordinate in coordinates {
            minLat = min(minLat, coordinate.latitude)
            maxLat = max(maxLat, coordinate.latitude)
            minLon = min(minLon, coordinate.longitude)
            maxLon = max(maxLon, coordinate.longitude)
        }
        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )
        let span = MKCoordinateSpan(
            latitudeDelta: max((maxLat - minLat) * 1.4, 0.005),
            longitudeDelta: max((maxLon - minLon) * 1.4, 0.005)
        )
        return MKCoordinateRegion(center: center, span: span)
    }
}

private struct ObservationRow: View {
    let observation: Sighting

    var body: some View {
        HStack(spacing: Spacing.sm) {
            SightingDot(color: observation.rssi.rssiColor, size: 8)

            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(observation.displayName)
                    .font(.headline)
                    .lineLimit(1)
                Text(observation.mac)
                    .font(.caption)
                    .monospaced()
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(1)
            }

            Spacer(minLength: Spacing.xs)

            VStack(alignment: .trailing, spacing: Spacing.xxs) {
                Text(Format.rssi(observation.rssi))
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(observation.rssi.rssiColor)
                if let suffix = GadgetCatalog.lilysharkShortName(from: observation.name) {
                    Text("LoRa !****\(suffix)")
                        .font(.caption2)
                        .monospaced()
                        .foregroundStyle(Color.accentColor)
                        .lineLimit(1)
                } else if observation.authMode != "[BLE]", !observation.authMode.isEmpty,
                   !observation.authMode.hasPrefix("[ESS]"),
                   !observation.authMode.hasPrefix("[WPA") {
                    Text(observation.authMode)
                        .font(.caption2)
                        .foregroundStyle(Color.accentColor)
                        .lineLimit(1)
                }
                Text(observation.firstSeen.formatted(date: .omitted, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, Spacing.xxs)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(observation.displayName), \(observation.type.title), \(Format.rssi(observation.rssi))")
    }
}

#Preview("Debrief") {
    NavigationStack {
        CaptureDetailView(
            capture: Capture(
                name: "Drive · Sep 8",
                startedAt: .now.addingTimeInterval(-600),
                endedAt: .now,
                track: [
                    TrackPoint(latitude: 34.0522, longitude: -118.2437, altitude: 80, timestamp: .now)
                ],
                observations: [
                    Sighting(
                        type: .ble,
                        mac: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE",
                        name: "Meshtastic",
                        authMode: "[BLE]",
                        firstSeen: .now,
                        channel: 0,
                        rssi: -52,
                        latitude: 34.0522,
                        longitude: -118.2437,
                        altitudeMeters: 80,
                        accuracyMeters: 8
                    )
                ]
            )
        )
        .environment(CaptureStore(previewCaptures: []))
    }
    .preferredColorScheme(.dark)
}
