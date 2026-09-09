import SwiftUI

@main
struct SpectreconFieldApp: App {
    @State private var locationService = LocationService()
    @State private var bleService = BLEScannerService()
    @State private var store = CaptureStore()
    @State private var importNotice: Notice?

    var body: some Scene {
        WindowGroup {
            TabView {
                Tab("Drive", systemImage: "map") {
                    DriveMapView()
                }
                Tab("Captures", systemImage: "archivebox") {
                    CapturesListView()
                }
            }
            .tint(Color.accentColor)
            .preferredColorScheme(.dark)
            .environment(locationService)
            .environment(bleService)
            .environment(store)
            .onAppear {
                bleService.locationProvider = { [locationService] in
                    locationService.currentFix
                }
            }
            .onOpenURL { url in
                handleOpen(url)
            }
            .alert(importNotice?.title ?? "", isPresented: noticePresented) {
                Button("OK", role: .cancel) { importNotice = nil }
            } message: {
                Text(importNotice?.message ?? "")
            }
        }
    }

    private var noticePresented: Binding<Bool> {
        Binding(
            get: { importNotice != nil },
            set: { if !$0 { importNotice = nil } }
        )
    }

    /// CSVs handed to the app via the Files app or a share sheet.
    private func handleOpen(_ url: URL) {
        guard url.pathExtension.lowercased() == "csv" else { return }
        do {
            let capture = try store.importCSV(from: url)
            importNotice = Notice(
                title: "Import Complete",
                message: "\(capture.observations.count) observations from “\(capture.name)”."
            )
        } catch {
            importNotice = Notice(title: "Import Failed", message: error.localizedDescription)
        }
    }
}
