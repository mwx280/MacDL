import AppKit

// Folds back the main window after a macdl:// deep link wakes the app (e.g.
// tapping the download-from-clipboard widget). LaunchServices activates the app
// and would otherwise raise the main window even from a menu-bar-only start;
// this hides it whenever it surfaces during a short suppression window. Only
// triggered by macdl:// handling, so normal window control is untouched.
@MainActor
final class MacDLWindowHider {
    static let shared = MacDLWindowHider()

    private var suppressUntil: Date = .distantPast

    private init() {
        NotificationCenter.default.addObserver(
            self, selector: #selector(windowDidBecomeKey(_:)),
            name: NSWindow.didBecomeKeyNotification, object: nil)
    }

    /// Hides surfaced windows for `interval` seconds after a macdl:// open.
    func suppress(interval: TimeInterval = 5) {
        suppressUntil = Date().addingTimeInterval(interval)
    }

    /// The main download window: tagged "main" by SwiftUI, otherwise matched by
    /// title, falling back to any non-settings key-capable window.
    static func findMainWindow() -> NSWindow? {
        NSApp.windows.first { $0.identifier?.rawValue == "main" }
            ?? NSApp.windows.first { $0.title == "MacDL" }
            ?? NSApp.windows.first { $0.canBecomeKey && !isSettingsWindow($0) }
    }

    static func isSettingsWindow(_ window: NSWindow) -> Bool {
        let t = window.title.lowercased()
        return t.contains("settings") || t.contains("preferences") || t.contains("设置")
    }

    @objc private func windowDidBecomeKey(_ note: Notification) {
        guard let window = note.object as? NSWindow,
              Date() < suppressUntil,
              !Self.isSettingsWindow(window),
              window.canBecomeKey,
              window.styleMask.contains(.titled)
        else { return }
        window.orderOut(nil)
        DockIconManager.shared.update()
    }
}
