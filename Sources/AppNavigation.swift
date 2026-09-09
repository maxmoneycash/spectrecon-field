import SwiftUI

enum AppTab: Hashable {
    case drive
    case captures
}

/// Tab + pending-capture router so a finished drive lands on its debrief.
@MainActor
@Observable
final class FieldRouter {
    var tab: AppTab = .drive
    var pendingCapture: Capture?

    func open(_ capture: Capture) {
        pendingCapture = capture
        tab = .captures
    }
}
