import AppKit
import MacDLCore

// In menu-bar-only mode (hideDockIconOnClose) the main window is only shown
// when the user explicitly asks for it (Show Window). Deep-link activations
// (e.g. tapping the widget) never raise it: the window is folded back the
// moment it becomes key. Driven by user intent rather than timing, so it holds
// no matter how late the window is created or which path surfaces it.
@MainActor
final class MacDLWindowHider {
    static let shared = MacDLWindowHider()

    /// True after the user asked to show the window; false after hiding or
    /// closing it, and initially in launch-in-background mode.
    private var userWantsVisible: Bool

    func markUserWantsVisible() { userWantsVisible = true }
    func markHidden() { userWantsVisible = false }

    private init() {
        userWantsVisible = !SettingsStore.shared.launchInBackground
        NotificationCenter.default.addObserver(
            self, selector: #selector(windowDidBecomeKey(_:)),
            name: NSWindow.didBecomeKeyNotification, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(windowWillClose(_:)),
            name: NSWindow.willCloseNotification, object: nil)
    }

    /// The main download window: tagged "main" by SwiftUI, otherwise matched by
    /// title, falling back to any non-settings key-capable window.
    static func findMainWindow() -> NSWindow? {
        NSApp.windows.first { $0.identifier?.rawValue == "main" }
            ?? NSApp.windows.first { $0.title == "MacDL" }
            ?? NSApp.windows.first { $0.canBecomeKey && !isSettingsWindow($0) }
    }

    /// True while the main download window is actually on screen.
    static func isMainWindowVisible() -> Bool {
        guard let window = findMainWindow() else { return false }
        return window.isVisible && window.canBecomeKey && window.styleMask.contains(.titled)
    }

    static func isSettingsWindow(_ window: NSWindow) -> Bool {
        let t = window.title.lowercased()
        return t.contains("settings") || t.contains("preferences") || t.contains("设置")
    }

    @objc private func windowDidBecomeKey(_ note: Notification) {
        guard let window = note.object as? NSWindow else { return }
        let deepLink = DockIconManager.shared.isHandlingDeepLink
        let gate = (SettingsStore.shared.hideDockIconOnClose || deepLink)
            && !userWantsVisible
            && !Self.isSettingsWindow(window)
            && window.canBecomeKey
            && window.styleMask.contains(.titled)
        EngineLog.app.debug("hider didBecomeKey title=\(window.title) gate=\(gate ? 1 : 0) wants=\(userWantsVisible ? 1 : 0) hide=\(SettingsStore.shared.hideDockIconOnClose ? 1 : 0) dl=\(deepLink ? 1 : 0) visible=\(window.isVisible ? 1 : 0)")
        guard gate else { return }
        window.orderOut(nil)
        DockIconManager.shared.update()
    }

    @objc private func windowWillClose(_ note: Notification) {
        guard let window = note.object as? NSWindow,
              window === Self.findMainWindow()
        else { return }
        markHidden()
    }
}
