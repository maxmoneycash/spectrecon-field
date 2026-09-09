import SwiftUI
import MapKit

/// Root screen: full-bleed dark map with live GPS track, live BLE sighting
/// dots, floating status chrome, and the Start / Hold-to-Stop drive control.
struct DriveMapView: View {
    @Environment(LocationService.self) private var location
    @Environment(BLEScannerService.self) private var ble
    @Environment(CaptureStore.self) private var store
    @Environment(FieldRouter.self) private var router
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openURL) private var openURL

    @State private var cameraPosition: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var savedCount = 0
    @State private var lastSavedName: String?
    @State private var showLiveLog = false
    @State private var showAbout = false

    var body: some View {
        NavigationStack {
            map
            .safeAreaInset(edge: .top) { topChrome }
            .safeAreaInset(edge: .bottom) { bottomChrome }
            .sensoryFeedback(.success, trigger: savedCount)
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showLiveLog) { liveLog }
            .sheet(isPresented: $showAbout) { AboutView() }
        }
    }

    // MARK: - Map

    private var map: some View {
        Map(position: $cameraPosition) {
            if location.track.count > 1 {
                MapPolyline(coordinates: location.track.map(\.coordinate))
                    .stroke(
                        Color.accentColor,
                        style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round)
                    )
            }
            ForEach(ble.sortedSightings.filter(\.hasFix)) { observation in
                Annotation(observation.displayName, coordinate: observation.coordinate) {
                    SightingDot(color: observation.rssi.rssiColor)
                }
            }
            UserAnnotation()
        }
        .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll, showsTraffic: false))
        .mapControls {
            MapCompass()
            MapUserLocationButton()
        }
        .mapControlVisibility(.visible)
    }

    // MARK: - Chrome

    private var topChrome: some View {
        VStack(spacing: Spacing.xs) {
            topStrip
            if location.isDenied {
                StatusBanner(
                    title: "Location is off — observations won’t be placed on the map.",
                    actionTitle: "Settings",
                    action: openSettings
                )
                .padding(.horizontal, Spacing.md)
            } else if ble.state == .unauthorized {
                StatusBanner(
                    title: "Bluetooth access is off — GPS still records.",
                    actionTitle: "Settings",
                    action: openSettings
                )
                .padding(.horizontal, Spacing.md)
            } else if ble.state == .poweredOff {
                StatusBanner(title: "Bluetooth is off — GPS still records.")
                    .padding(.horizontal, Spacing.md)
            }
        }
    }

    private var topStrip: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: location.isRecording ? "record.circle" : "dot.radiowaves.left.and.right")
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(location.isRecording ? Color.accentColor : Color.secondary)
                .symbolEffect(.pulse, options: .repeating, isActive: location.isRecording && !reduceMotion)
                .contentTransition(.symbolEffect(.replace))
                .accessibilityHidden(true)

            if location.isRecording {
                ElapsedTimeText(start: location.recordingStartedAt)
                    .font(.subheadline)
            } else {
                Text(lastSavedName.map { "Saved \($0)" } ?? "Ready")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: Spacing.xs)

            if location.isRecording {
                Button {
                    showLiveLog = true
                } label: {
                    HStack(spacing: Spacing.xxs) {
                        Text("\(ble.sightingCount)")
                            .font(.subheadline)
                            .monospacedDigit()
                            .contentTransition(.numericText())
                        Text("obs")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(minHeight: 44)
                }
                .accessibilityLabel("\(ble.sightingCount) observations. Show live log.")
            } else {
                Button {
                    showAbout = true
                } label: {
                    Image(systemName: "info.circle")
                        .symbolRenderingMode(.hierarchical)
                        .frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityLabel("About Spectrecon Field")
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.xs)
        .background(.thinMaterial, in: Surfaces.card)
        .padding(.horizontal, Spacing.md)
        .padding(.top, Spacing.xxs)
    }

    private var bottomChrome: some View {
        VStack(spacing: Spacing.sm) {
            HStack(spacing: Spacing.md) {
                StatItem(title: "Devices", value: "\(ble.sightingCount)")
                StatItem(title: "Distance", value: Format.distance(location.track.pathDistance))
                StatItem(
                    title: location.isRecording ? "Accuracy" : "Duration",
                    value: location.isRecording
                        ? Format.accuracy(location.currentFix?.accuracy ?? -1)
                        : Format.duration(elapsed)
                )
            }
            .padding(Spacing.md)
            .background(.regularMaterial, in: Surfaces.card)
            .animation(.snappy(duration: 0.2), value: ble.sightingCount)

            controlButton
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.xs)
    }

    @ViewBuilder
    private var controlButton: some View {
        if location.isRecording {
            HoldToConfirmButton(title: "Hold to Stop", systemImage: "stop.circle.fill") {
                stopDrive()
            }
            .transition(.opacity.combined(with: .scale(scale: 0.97)))
        } else {
            Button {
                startDrive()
            } label: {
                Label("Start Drive", systemImage: "record.circle")
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(AccentButtonStyle())
            .transition(.opacity.combined(with: .scale(scale: 0.97)))
        }
    }

    private var liveLog: some View {
        NavigationStack {
            Group {
                if ble.sortedSightings.isEmpty {
                    ContentUnavailableView(
                        "Listening",
                        systemImage: "antenna.radiowaves.left.and.right",
                        description: Text("Nearby BLE devices appear here as they’re heard.")
                    )
                } else {
                    List(ble.sortedSightings) { observation in
                        LiveSightingRow(observation: observation)
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Live")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showLiveLog = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Stats

    private var elapsed: TimeInterval {
        guard let startedAt = location.recordingStartedAt else { return 0 }
        return Date.now.timeIntervalSince(startedAt)
    }

    // MARK: - Actions

    private func startDrive() {
        lastSavedName = nil
        location.requestAuthorization()
        withAnimation(Motion.adaptive(Motion.sheet, reduceMotion: reduceMotion)) {
            location.startRecording()
        }
        ble.reset()
        ble.startScanning()
    }

    private func stopDrive() {
        let startedAt = location.recordingStartedAt ?? .now
        let capture = Capture(
            name: store.nextDriveName(at: startedAt),
            startedAt: startedAt,
            endedAt: .now,
            track: location.track,
            observations: ble.sortedSightings
        )
        withAnimation(Motion.adaptive(Motion.sheet, reduceMotion: reduceMotion)) {
            location.stopRecording()
        }
        ble.stopScanning()
        showLiveLog = false
        if let saved = try? store.save(capture) {
            lastSavedName = saved.name
            savedCount += 1
            router.open(saved)
        }
        ble.reset()
        location.clearTrack()
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            openURL(url)
        }
    }
}

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("App", value: "Spectrecon Field")
                    LabeledContent("Version", value: "1.0")
                }
                Section("What this records") {
                    Text("iOS has no public Wi-Fi scan API. Field records your GPS track and every BLE device Core Bluetooth can hear. Import a WiGLE CSV from an ESP32 rig to add Wi-Fi rows, then debrief on the map.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Section("On device") {
                    Text("Captures stay in this app’s Application Support folder as JSON. Export writes a WiGLE CSV v1.4 you can share into spectrecon debrief.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("About")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

#Preview("Drive") {
    DriveMapView()
        .environment(LocationService())
        .environment(BLEScannerService())
        .environment(CaptureStore(previewCaptures: []))
        .environment(FieldRouter())
        .preferredColorScheme(.dark)
}
