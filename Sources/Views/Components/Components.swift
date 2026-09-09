import SwiftUI
import UIKit

/// Small filled dot used on maps and as a legend swatch. Content colors only.
struct SightingDot: View {
    let color: Color
    var size: CGFloat = 10

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .overlay {
                Circle().strokeBorder(.white.opacity(0.35), lineWidth: 1)
            }
    }
}

/// Live-updating elapsed time, monospaced digits. Shows --:-- when idle.
struct ElapsedTimeText: View {
    let start: Date?

    var body: some View {
        if let start {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(Format.duration(context.date.timeIntervalSince(start)))
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
        } else {
            Text("--:--")
                .monospacedDigit()
        }
    }
}

/// Single labelled stat for the drive stats card.
struct StatItem: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline)
                .monospacedDigit()
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// Compact live-scan row for the in-drive log.
struct LiveSightingRow: View {
    let observation: Sighting

    var body: some View {
        HStack(spacing: Spacing.sm) {
            SightingDot(color: observation.rssi.rssiColor, size: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text(observation.displayName)
                    .font(.subheadline)
                    .lineLimit(1)
                HStack(spacing: Spacing.xs) {
                    Text(Format.rssi(observation.rssi))
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    if observation.authMode != "[BLE]", !observation.authMode.isEmpty {
                        Text(observation.authMode)
                            .font(.caption2)
                            .foregroundStyle(Color.accentColor)
                            .lineLimit(1)
                    }
                }
            }
            Spacer(minLength: Spacing.xs)
            Image(systemName: observation.type.symbolName)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .symbolRenderingMode(.hierarchical)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(observation.displayName), \(Format.rssi(observation.rssi))")
    }
}

/// Hold-to-confirm control: press and hold for `duration` seconds while a fill
/// sweeps across; release early and the fill snaps back. Used for Stop Drive.
/// VoiceOver activates immediately via the Confirm action (hold is a sighted affordance).
struct HoldToConfirmButton: View {
    let title: String
    let systemImage: String
    var tint: Color = .red
    var duration: TimeInterval = 2
    let onComplete: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var progress: Double = 0
    @State private var isPressing = false
    @State private var didComplete = false

    private var holdDuration: TimeInterval { reduceMotion ? 0.15 : duration }

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        tint.opacity(0.22)
                        tint
                            .frame(width: geometry.size.width * progress)
                    }
                }
            }
            .clipShape(Surfaces.button)
            .contentShape(Surfaces.button)
            .scaleEffect(isPressing && !reduceMotion ? 0.97 : 1)
            .animation(Motion.press, value: isPressing)
            .onLongPressGesture(
                minimumDuration: holdDuration,
                maximumDistance: 120,
                pressing: { pressing in
                    isPressing = pressing
                    if pressing {
                        didComplete = false
                        withAnimation(.linear(duration: holdDuration)) { progress = 1 }
                    } else if !didComplete {
                        withAnimation(Motion.adaptive(Motion.snapBack, reduceMotion: reduceMotion)) {
                            progress = 0
                        }
                    }
                },
                perform: {
                    didComplete = true
                    progress = 0
                    isPressing = false
                    onComplete()
                }
            )
            .accessibilityElement(children: .ignore)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(title)
            .accessibilityHint("Touch and hold to confirm")
            .accessibilityAction(named: "Confirm") { onComplete() }
    }
}

/// Compact non-blocking status line over the map (Bluetooth off, location denied).
struct StatusBanner: View {
    let title: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Text(title)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(.footnote.weight(.semibold))
                    .frame(minHeight: 44)
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.xs)
        .background(.regularMaterial, in: Surfaces.card)
    }
}

/// Blocking permission / hardware state card over the map.
struct StatusCard: View {
    let title: String
    let message: String
    let systemImage: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: systemImage)
                .font(.largeTitle)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)
            Text(title)
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(AccentButtonStyle())
            }
        }
        .padding(Spacing.lg)
        .frame(maxWidth: 360)
        .background(.regularMaterial, in: Surfaces.card)
        .padding(.horizontal, Spacing.md)
    }
}

/// UIActivityViewController wrapper for exporting CSV files.
struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
