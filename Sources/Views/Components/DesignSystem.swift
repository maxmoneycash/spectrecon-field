import SwiftUI

/// Strict 4pt spacing grid. Never use ad-hoc values outside these.
enum Spacing {
    static let xxs: CGFloat = 4
    static let xs: CGFloat = 8
    static let sm: CGFloat = 12
    static let md: CGFloat = 16
    static let lg: CGFloat = 20
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
}

/// Shape lock: floating cards 16pt continuous, buttons 12pt, chips fully rounded (Capsule).
enum CornerRadius {
    static let card: CGFloat = 16
    static let button: CGFloat = 12
}

enum Surfaces {
    static let card = RoundedRectangle(cornerRadius: CornerRadius.card, style: .continuous)
    static let button = RoundedRectangle(cornerRadius: CornerRadius.button, style: .continuous)
}

extension Color {
    init(hex: UInt32) {
        let red = Double((hex >> 16) & 0xFF) / 255
        let green = Double((hex >> 8) & 0xFF) / 255
        let blue = Double(hex & 0xFF) / 255
        self.init(.sRGB, red: red, green: green, blue: blue, opacity: 1)
    }

    /// Semantic content colors — used as small dots only, never as chrome.
    static let signalStrong = Color(hex: 0x30D158)
    static let signalWeak = Color(hex: 0xFF9F0A)
    static let signalAnomalous = Color(hex: 0xFF453A)
    static let blePurple = Color(hex: 0xBF5AF2)
    static let wifiBlue = Color(hex: 0x0A84FF)
    static let btTeal = Color(hex: 0x30B0C7)
}

extension ObservationType {
    var dotColor: Color {
        switch self {
        case .wifi: return .wifiBlue
        case .ble: return .blePurple
        case .bt: return .btTeal
        }
    }

    var symbolName: String {
        switch self {
        case .wifi: "wifi"
        case .ble: "antenna.radiowaves.left.and.right"
        case .bt: "dot.radiowaves.left.and.right"
        }
    }
}

extension Int {
    /// RSSI in dBm → content color. Never used as chrome.
    var rssiColor: Color {
        if self >= -60 { return .signalStrong }
        if self >= -80 { return .signalWeak }
        return .signalAnomalous
    }
}

/// Motion presets from the design brief.
enum Motion {
    static let sheet: Animation = .interactiveSpring(response: 0.3, dampingFraction: 0.8)
    static let press: Animation = .snappy(duration: 0.12)
    static let snapBack: Animation = .snappy(duration: 0.15)

    /// Reduce Motion collapses everything to a short fade (≤150ms).
    static func adaptive(_ animation: Animation, reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeInOut(duration: 0.15) : animation
    }
}

/// Press-in scale (0.97, ~120ms) for buttons; list rows use default highlight instead.
struct PressableButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .animation(Motion.press, value: configuration.isPressed)
    }
}

/// Solid accent fill, 12pt continuous corners — the primary CTA look.
struct AccentButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 54)
            .background(Color.accentColor, in: Surfaces.button)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .animation(Motion.press, value: configuration.isPressed)
    }
}

enum Format {
    static func duration(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval.rounded()))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }

    static func distance(_ meters: Double) -> String {
        Measurement(value: meters, unit: UnitLength.meters)
            .formatted(.measurement(width: .abbreviated, usage: .road))
    }

    static func rssi(_ rssi: Int) -> String {
        "\(rssi) dBm"
    }

    static func accuracy(_ meters: Double) -> String {
        guard meters >= 0 else { return "—" }
        return "±\(Int(meters.rounded())) m"
    }
}

/// File URL presented via `.sheet(item:)`.
struct SharePayload: Identifiable {
    let id = UUID()
    let url: URL
}

struct Notice: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let message: String
}
