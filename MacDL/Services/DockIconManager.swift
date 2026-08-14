import AppKit

// Hides the Dock icon when every window is closed (pure menu-bar background app)
// and restores it when a window becomes visible again.
@MainActor
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
            // The observer runs on the main queue, so isolation is guaranteed.
            MainActor.assumeIsolated {
                self?.update()
            }
        }
    }

    func update() {
        guard NSApp != nil else { return }
        let policy: NSApplication.ActivationPolicy
        // Only titled windows count: the menu bar's pop-up window also becomes
        // key while tracking, and treating it as a real window would re-show
        // the Dock icon just from hovering the menu.
        let hasRealWindow = NSApp.windows.contains {
            $0.isVisible && $0.canBecomeKey && $0.styleMask.contains(.titled)
        }
        // Launch-in-background hides the Dock icon too, so a background start
        // with no visible window never leaves one lingering.
        if (SettingsStore.shared.hideDockIconOnClose || SettingsStore.shared.launchInBackground),
           !hasRealWindow {
            policy = .accessory
        } else {
            policy = .regular
        }
        if NSApp.activationPolicy() != policy {
            NSApp.setActivationPolicy(policy)
        }
    }
}
