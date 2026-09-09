import Foundation

/// WiGLE CSV v1.4 parser and serializer.
///
/// File layout:
///   Line 1: `WigleWifi-1.4,appRelease=...,model=...,release=...,device=...,display=...,board=...,brand=...`
///   Line 2: `MAC,SSID,AuthMode,FirstSeen,Channel,RSSI,CurrentLatitude,CurrentLongitude,AltitudeMeters,AccuracyMeters,Type`
///   Line 3+: one row per observation.
enum WigleCSV {
    static let versionHeader = "WigleWifi-1.4"
    static let columnHeader = "MAC,SSID,AuthMode,FirstSeen,Channel,RSSI,CurrentLatitude,CurrentLongitude,AltitudeMeters,AccuracyMeters,Type"

    enum CSVError: LocalizedError {
        case notWigleFile
        case missingHeader
        case noObservations

        var errorDescription: String? {
            switch self {
            case .notWigleFile:
                return "Not a WiGLE CSV: the first line must start with “WigleWifi”."
            case .missingHeader:
                return "The WiGLE column header line (MAC,SSID,…) is missing."
            case .noObservations:
                return "The file contains no observation rows."
            }
        }
    }

    // MARK: - Serialize

    static func serialize(_ capture: Capture, deviceModel: String) -> String {
        let metadata = [
            versionHeader,
            "appRelease=SpectreconField-1.0",
            "model=\(sanitizeMetadata(deviceModel))",
            "release=1.0",
            "device=Spectrecon Field",
            "display=Spectrecon Field",
            "board=",
            "brand=Apple",
        ].joined(separator: ",")

        var lines = [metadata, columnHeader]
        for observation in capture.observations.sorted(by: { $0.firstSeen < $1.firstSeen }) {
            lines.append(row(for: observation))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func row(for observation: Sighting) -> String {
        [
            escape(observation.mac),
            escape(observation.name),
            escape(observation.authMode),
            escape(format(date: observation.firstSeen)),
            String(observation.channel),
            String(observation.rssi),
            format(coordinate: observation.latitude),
            format(coordinate: observation.longitude),
            format(plain: observation.altitudeMeters),
            format(plain: observation.accuracyMeters),
            observation.type.rawValue,
        ].joined(separator: ",")
    }

    // MARK: - Parse

    static func parse(_ text: String) throws -> [Sighting] {
        let lines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "\r")) }

        guard let first = lines.first(where: { !$0.isEmpty }), first.hasPrefix("WigleWifi") else {
            throw CSVError.notWigleFile
        }
        guard let headerIndex = lines.firstIndex(where: { $0.hasPrefix("MAC,") }) else {
            throw CSVError.missingHeader
        }

        let header = parseLine(lines[headerIndex]).map { $0.trimmingCharacters(in: .whitespaces) }
        var columnIndex: [String: Int] = [:]
        for (index, name) in header.enumerated() { columnIndex[name] = index }

        func column(_ name: String, in fields: [String]) -> String? {
            guard let index = columnIndex[name], index < fields.count else { return nil }
            return fields[index]
        }

        var observations: [Sighting] = []
        for line in lines[(headerIndex + 1)...] where !line.isEmpty {
            let fields = parseLine(line)
            guard let mac = column("MAC", in: fields), !mac.isEmpty else { continue }
            let type = ObservationType(rawValue: (column("Type", in: fields) ?? "WIFI").uppercased()) ?? .wifi
            observations.append(
                Sighting(
                    type: type,
                    mac: mac,
                    name: column("SSID", in: fields) ?? "",
                    authMode: column("AuthMode", in: fields) ?? (type == .wifi ? "[ESS]" : "[BLE]"),
                    firstSeen: parse(date: column("FirstSeen", in: fields) ?? "") ?? .now,
                    channel: Int(column("Channel", in: fields) ?? "") ?? 0,
                    rssi: Int(column("RSSI", in: fields) ?? "") ?? 0,
                    latitude: Double(column("CurrentLatitude", in: fields) ?? "") ?? 0,
                    longitude: Double(column("CurrentLongitude", in: fields) ?? "") ?? 0,
                    altitudeMeters: Double(column("AltitudeMeters", in: fields) ?? "") ?? 0,
                    accuracyMeters: Double(column("AccuracyMeters", in: fields) ?? "") ?? 0
                )
            )
        }

        guard !observations.isEmpty else { throw CSVError.noObservations }
        return observations
    }

    /// Minimal CSV field parser: handles quoted fields and escaped ("") quotes.
    static func parseLine(_ line: String) -> [String] {
        var fields: [String] = []
        var field = ""
        var inQuotes = false
        var iterator = line.makeIterator()
        while let character = iterator.next() {
            if inQuotes {
                if character == "\"" {
                    if let next = iterator.next() {
                        if next == "\"" {
                            field.append("\"")
                        } else {
                            inQuotes = false
                            if next == "," {
                                fields.append(field)
                                field = ""
                            } else {
                                field.append(next)
                            }
                        }
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.append(character)
                }
            } else if character == "\"" {
                inQuotes = true
            } else if character == "," {
                fields.append(field)
                field = ""
            } else {
                field.append(character)
            }
        }
        fields.append(field)
        return fields
    }

    // MARK: - Helpers

    private static func escape(_ field: String) -> String {
        guard field.contains(",") || field.contains("\"") || field.contains("\n") else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    private static func sanitizeMetadata(_ value: String) -> String {
        value.replacingOccurrences(of: ",", with: " ")
    }

    private static func format(date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: date)
    }

    private static func parse(date string: String) -> Date? {
        let trimmed = string.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        for format in ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd"] {
            formatter.dateFormat = format
            formatter.timeZone = TimeZone(identifier: "UTC")
            if let date = formatter.date(from: trimmed) { return date }
        }
        return ISO8601DateFormatter().date(from: trimmed)
    }

    /// Locale-independent decimal formatting (always a `.` decimal separator).
    private static func format(coordinate: Double) -> String {
        String(format: "%.7f", coordinate)
    }

    private static func format(plain: Double) -> String {
        String(format: "%.1f", plain)
    }
}
