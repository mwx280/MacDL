import AppKit

// Keeps MacDL a pure menu-bar app (LSUIElement): the Dock icon never appears,
// regardless of window state. Flipping the activation policy on every window
// open/close used to leave ghost icons in the Dock, and URL-scheme activations
// (e.g. the widget) would surface an icon each time.
@MainActor
final class DockIconManager {
    static let shared = DockIconManager()

    func update() {
        guard NSApp != nil else { return }
        if NSApp.activationPolicy() != .accessory {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}
