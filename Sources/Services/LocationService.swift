import Foundation
import CoreLocation

/// GPS track recording. When a drive is recording, updates continue in the
/// background (UIBackgroundModes: location) as long as the session was started
/// in the foreground with at least When-In-Use authorization.
@MainActor
@Observable
final class LocationService: NSObject {
    @ObservationIgnored private let manager = CLLocationManager()

    private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined
    private(set) var currentFix: LocationFix?
    private(set) var track: [TrackPoint] = []
    private(set) var recordingStartedAt: Date?

    var isRecording: Bool { recordingStartedAt != nil }

    var isDenied: Bool {
        authorizationStatus == .denied || authorizationStatus == .restricted
    }

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 5
        manager.activityType = .automotiveNavigation
        manager.showsBackgroundLocationIndicator = true
        authorizationStatus = manager.authorizationStatus
    }

    func requestAuthorization() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse:
            manager.requestAlwaysAuthorization()
        default:
            break
        }
    }

    func startRecording() {
        track.removeAll()
        recordingStartedAt = .now
        if manager.authorizationStatus == .authorizedAlways
            || manager.authorizationStatus == .authorizedWhenInUse {
            manager.allowsBackgroundLocationUpdates = true
            manager.pausesLocationUpdatesAutomatically = false
        }
        manager.startUpdatingLocation()
        if manager.authorizationStatus == .authorizedWhenInUse {
            manager.requestAlwaysAuthorization()
        }
    }

    func stopRecording() {
        recordingStartedAt = nil
        manager.stopUpdatingLocation()
        manager.allowsBackgroundLocationUpdates = false
        manager.pausesLocationUpdatesAutomatically = true
    }

    func clearTrack() {
        track.removeAll()
    }

    fileprivate func ingest(_ samples: [LocationSample]) {
        guard let last = samples.last else { return }
        currentFix = LocationFix(
            latitude: last.latitude,
            longitude: last.longitude,
            altitude: last.altitude,
            accuracy: last.accuracy
        )
        guard isRecording else { return }
        track.append(contentsOf: samples.map {
            TrackPoint(
                latitude: $0.latitude,
                longitude: $0.longitude,
                altitude: $0.altitude,
                timestamp: $0.timestamp
            )
        })
    }
}

private struct LocationSample: Sendable {
    let latitude: Double
    let longitude: Double
    let altitude: Double
    let accuracy: Double
    let timestamp: Date
}

extension LocationService: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        // CLLocation is not Sendable; copy primitives before hopping actors.
        let samples = locations.map { location in
            LocationSample(
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude,
                altitude: location.altitude,
                accuracy: location.horizontalAccuracy,
                timestamp: location.timestamp
            )
        }
        Task { @MainActor in
            self.ingest(samples)
        } as Task<Void, Never>
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.authorizationStatus = status
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
        // Transient CoreLocation errors (e.g. kCLErrorLocationUnknown) are safe to ignore.
    }
}
