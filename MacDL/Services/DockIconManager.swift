import AppKit
import MacDLCore

// Hides the Dock icon when every window is closed (pure menu-bar background app)
// and restores it when a window becomes visible again. LSUIElement keeps the app
// accessory at launch, so a URL-scheme activation (e.g. the widget) never forces
// it to regular and never leaves a ghost icon behind.
@MainActor
final class DockIconManager {
    static let shared = DockIconManager()

    /// Suppress Dock icon entirely during deep-link handling so the system
    /// activation never shows a ghost icon — even if a window briefly becomes
    /// key in the URL-delivery lifecycle.
    var isHandlingDeepLink = false

    private init() {
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: nil, queue: .main
        ) { [weak self] _ in
            // Let the window actually finish closing before re-checking visibility.
            DispatchQueue.main.async { self?.update() }
        }
        // No didBecomeKeyNotification observer: reactive window-key → .regular
        // promotion is what causes the Dock flicker during URL-scheme activation.
        // Instead, explicit callers (showWindow, reopen) drive the policy change.
    }

    func update() {
        guard NSApp != nil else { return }
        let before = NSApp.activationPolicy()
        let policy: NSApplication.ActivationPolicy
        if isHandlingDeepLink {
            // Deep-link handling is in progress: hold accessory no matter what
            // so rapid widget taps never cause a .regular ↔ .accessory flip.
            policy = .accessory
        } else {
            // Only titled windows count: the menu bar's pop-up window also becomes
            // key while tracking, and treating it as a real window would re-show
            // the Dock icon just from hovering the menu.
            let hasRealWindow = NSApp.windows.contains {
                $0.isVisible && $0.canBecomeKey && $0.styleMask.contains(.titled)
            }
            // Launch-in-background hides the Dock icon too, so a background start
            // with no visible window never leaves one lingering.
            let hide = SettingsStore.shared.hideDockIconOnClose
            let background = SettingsStore.shared.launchInBackground
            if (hide || background), !hasRealWindow {
                policy = .accessory
            } else {
                policy = .regular
            }
        }
        if NSApp.activationPolicy() != policy {
            NSApp.setActivationPolicy(policy)
        }
        EngineLog.app.debug("DockIcon update before=\(before.rawValue) after=\(policy.rawValue) dl=\(isHandlingDeepLink ? 1 : 0) windows=\(NSApp.windows.count)")
    }
}
