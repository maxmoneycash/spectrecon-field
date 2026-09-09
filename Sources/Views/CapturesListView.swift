import SwiftUI
import UniformTypeIdentifiers

/// Saved drives and imported rig captures. Swipe to delete, share via the
/// detail screen or row context menu, import WiGLE CSVs from Files.
struct CapturesListView: View {
    @Environment(CaptureStore.self) private var store
    @Namespace private var zoomSpace

    @State private var showImporter = false
    @State private var share: SharePayload?
    @State private var notice: Notice?
    @State private var searchText = ""

    private var filtered: [Capture] {
        guard !searchText.isEmpty else { return store.captures }
        return store.captures.filter { capture in
            capture.name.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if store.captures.isEmpty {
                    ContentUnavailableView(
                        "No Captures",
                        systemImage: "dot.radiowaves.left.and.right",
                        description: Text("Record a drive, or import a WiGLE CSV from an ESP32 rig.")
                    )
                } else if filtered.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                } else {
                    List {
                        ForEach(filtered) { capture in
                            NavigationLink(value: capture) {
                                CaptureRow(capture: capture)
                            }
                            .matchedTransitionSource(id: capture.id, in: zoomSpace)
                            .contextMenu {
                                Button {
                                    share(capture)
                                } label: {
                                    Label("Export WiGLE CSV", systemImage: "square.and.arrow.up")
                                }
                                Button(role: .destructive) {
                                    withAnimation { store.delete(capture) }
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    store.delete(capture)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Captures")
            .navigationDestination(for: Capture.self) { capture in
                CaptureDetailView(capture: capture)
                    .navigationTransition(.zoom(sourceID: capture.id, in: zoomSpace))
            }
            .searchable(text: $searchText, prompt: "Drive name")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Import CSV", systemImage: "square.and.arrow.down") {
                        showImporter = true
                    }
                }
            }
            .fileImporter(
                isPresented: $showImporter,
                allowedContentTypes: [.commaSeparatedText, .plainText]
            ) { result in
                handleImport(result)
            }
            .sheet(item: $share) { payload in
                ActivityView(items: [payload.url])
                    .presentationDetents([.medium, .large])
            }
            .alert(notice?.title ?? "", isPresented: noticePresented) {
                Button("OK", role: .cancel) { notice = nil }
            } message: {
                Text(notice?.message ?? "")
            }
        }
    }

    private var noticePresented: Binding<Bool> {
        Binding(
            get: { notice != nil },
            set: { if !$0 { notice = nil } }
        )
    }

    private func share(_ capture: Capture) {
        guard let url = try? store.export(capture) else { return }
        share = SharePayload(url: url)
    }

    private func handleImport(_ result: Result<URL, any Error>) {
        switch result {
        case .success(let url):
            do {
                let capture = try store.importCSV(from: url)
                notice = Notice(
                    title: "Import Complete",
                    message: "\(capture.observations.count) observations from “\(capture.name)”."
                )
            } catch {
                notice = Notice(title: "Import Failed", message: error.localizedDescription)
            }
        case .failure(let error):
            notice = Notice(title: "Import Failed", message: error.localizedDescription)
        }
    }
}

private struct CaptureRow: View {
    let capture: Capture

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(capture.name)
                .font(.headline)
                .lineLimit(1)
            Text(capture.startedAt.formatted(date: .abbreviated, time: .shortened))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack(spacing: Spacing.md) {
                Label("\(capture.observations.count)", systemImage: "dot.radiowaves.left.and.right")
                Label(Format.distance(capture.distanceMeters), systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                Label(Format.duration(capture.duration), systemImage: "clock")
            }
            .font(.caption)
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .symbolRenderingMode(.hierarchical)
        }
        .padding(.vertical, Spacing.xxs)
        .accessibilityElement(children: .combine)
    }
}

#Preview("Captures") {
    CapturesListView()
        .environment(CaptureStore(previewCaptures: [
            Capture(
                name: "Drive · Sep 8, 2026 at 9:41 PM",
                startedAt: .now.addingTimeInterval(-1800),
                endedAt: .now,
                track: [],
                observations: []
            )
        ]))
        .preferredColorScheme(.dark)
}
