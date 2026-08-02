import AppKit

// Hides the Dock icon when every window is closed (pure menu-bar background app)
// and restores it when a window becomes visible again.
final class DockIconManager {
    static let shared = DockIconManager()

    private init() {
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: nil, queue: .main
        ) { [weak self] _ in
            // Let the window actually finish closing before re-checking visibility.
            DispatchQueue.main.async { self?.update() }
        }
        NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.update()
        }
    }

    func update() {
        guard NSApp != nil else { return }
        let policy: NSApplication.ActivationPolicy
        if SettingsStore.shared.hideDockIconOnClose,
           !NSApp.windows.contains(where: { $0.isVisible && $0.canBecomeKey }) {
            policy = .accessory
        } else {
            policy = .regular
        }
        if NSApp.activationPolicy() != policy {
            NSApp.setActivationPolicy(policy)
        }
    }
}
