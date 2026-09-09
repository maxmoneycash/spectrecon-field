import Foundation
import UIKit

/// Persists captures as JSON in Application Support, imports WiGLE CSVs from
/// external rigs, and exports captures as WiGLE CSV v1.4 temp files for sharing.
@MainActor
@Observable
final class CaptureStore {
    private(set) var captures: [Capture] = []

    @ObservationIgnored private let directory: URL
    @ObservationIgnored private let fileManager = FileManager.default
    @ObservationIgnored private let persistToDisk: Bool

    init() {
        persistToDisk = true
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        directory = support.appendingPathComponent("Captures", isDirectory: true)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        load()
    }

    /// In-memory store for SwiftUI previews. Never touches Application Support.
    init(previewCaptures: [Capture]) {
        persistToDisk = false
        directory = FileManager.default.temporaryDirectory
        captures = previewCaptures
    }

    func load() {
        guard persistToDisk else { return }
        let urls = (try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ).filter { $0.pathExtension == "json" }) ?? []

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        captures = urls.compactMap { url in
            guard let data = try? Data(contentsOf: url) else { return nil }
            return try? decoder.decode(Capture.self, from: data)
        }
        .sorted { $0.startedAt > $1.startedAt }
    }

    @discardableResult
    func save(_ capture: Capture) throws -> Capture {
        captures.insert(capture, at: 0)
        if persistToDisk {
            try persist(capture)
        }
        return capture
    }

    func delete(_ capture: Capture) {
        captures.removeAll { $0.id == capture.id }
        guard persistToDisk else { return }
        try? fileManager.removeItem(at: fileURL(for: capture))
    }

    func delete(at offsets: IndexSet) {
        let doomed = offsets.map { captures[$0] }
        captures.remove(atOffsets: offsets)
        guard persistToDisk else { return }
        for capture in doomed {
            try? fileManager.removeItem(at: fileURL(for: capture))
        }
    }

    /// Parses a WiGLE CSV (from Files or a share sheet) into a new capture.
    /// Imported rig captures have no GPS track of their own; the observation
    /// coordinates they carry are used for the debrief map.
    @discardableResult
    func importCSV(from url: URL) throws -> Capture {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        let text: String
        if let utf8 = try? String(contentsOf: url, encoding: .utf8) {
            text = utf8
        } else {
            text = try String(contentsOf: url, encoding: .isoLatin1)
        }

        let observations = try WigleCSV.parse(text)
        let dates = observations.map(\.firstSeen)
        let name = url.deletingPathExtension().lastPathComponent
        let capture = Capture(
            name: name.isEmpty ? "Imported capture" : name,
            startedAt: dates.min() ?? .now,
            endedAt: dates.max() ?? .now,
            track: [],
            observations: observations
        )
        return try save(capture)
    }

    /// Writes a WiGLE CSV v1.4 to a temp file, ready for ShareLink / UIActivityViewController.
    func export(_ capture: Capture) throws -> URL {
        let model = UIDevice.current.model
        let csv = WigleCSV.serialize(capture, deviceModel: model)
        let url = fileManager.temporaryDirectory
            .appendingPathComponent(sanitize(filename: capture.name))
            .appendingPathExtension("csv")
        try csv.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    func nextDriveName(at date: Date = .now) -> String {
        let stamp = date.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened))
        return "Drive · \(stamp)"
    }

    // MARK: - Private

    private func fileURL(for capture: Capture) -> URL {
        directory.appendingPathComponent(capture.id.uuidString).appendingPathExtension("json")
    }

    private func persist(_ capture: Capture) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(capture)
        try data.write(to: fileURL(for: capture), options: .atomic)
    }

    private func sanitize(filename: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let scalars = filename.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }
        let result = String(scalars)
        return result.isEmpty ? "capture" : result
    }
}
