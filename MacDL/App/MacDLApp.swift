import SwiftUI
import os
import MacDLCore

@main
struct MacDLApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    private static let firstLaunchKey = "didCompleteFirstLaunchSetup"

    init() {
        NSWindow.allowsAutomaticWindowTabbing = false
        // File log in the sandbox container's Logs dir; truncated each launch.
        let logsDir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Logs", isDirectory: true)
        if let logsDir {
            FileLogWriter.setLogFile(logsDir.appendingPathComponent("MacDL.log"))
        }
        // Per-host download history for smart cold-start, kept beside downloads.json.
        let historyURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("com.xiaowu.MacDL")
            .appendingPathComponent("source-history.json")
        SourceHistoryStore.shared.setFileURL(historyURL)
        // 0 means "Adaptive" connections; the shared session must still allow
        // the per-host cap up to the maximum the adaptive policy may reach.
        ChunkDownloadTask.maxConnectionsProvider = {
            let connections = SettingsStore.shared.maxConnections
            return connections > 0 ? connections : EngineConstants.maxAutoConnections
        }
        // Seed the shared bandwidth bucket with the persisted global cap.
        ChunkDownloadTask.globalBucket.setRate(Double(SettingsStore.shared.maxDownloadSpeed))
        EngineLog.app.notice("didFinishLaunching (log file: \(FileLogWriter.logFileURL?.path ?? "nil"))")
        // Ask up front so the first download's "started" banner isn't dropped
        // while the permission prompt is still pending. No-op if already decided.
        // The view model's app services (redownload/termination observers, file
        // check timer) are also only started in the real app, never under tests.
        if !ProcessInfo.isRunningTests {
            DownloadNotifier.shared.requestAuthorization()
            ContentViewModel.shared.startAppServices()
            UpdateModel.shared.autoCheckAndDownloadIfNeeded()
            performFirstLaunchSetupIfNeeded()
            // A background launch shows no window, so post a "running" notice
            // (gated by the Launch Notification setting) to confirm the app is alive.
            if SettingsStore.shared.launchInBackground {
                DownloadNotifier.shared.notifyLaunched()
            }
        }
        _ = DockIconManager.shared
    }

    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView()
                .environment(LanguageManager.shared)
        }
        .defaultSize(width: 700, height: 520)
        .defaultLaunchBehavior(SettingsStore.shared.launchInBackground ? .suppressed : .presented)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button { MacDLApp.showAbout() } label: {
                    Label(LanguageManager.shared.localized("About MacDL"), systemImage: "info.circle")
                }
            }
            CommandGroup(replacing: .appTermination) {
                Button {
                    if MacDLApp.quitWithCheck() {
                        NSApp.terminate(nil)
                    }
                } label: {
                    Text(LanguageManager.shared.localized("Quit MacDL"))
                }.keyboardShortcut("q")
            }
        }

        Settings {
            SettingsView()
                .environment(LanguageManager.shared)
        }
        .windowResizability(.contentSize)

        MenuBarExtra {
            MenuBarContent()
        } label: {
            MenuBarLabel()
        }
    }

    /// Menu bar icon. Registers SwiftUI's `openWindow` action as soon as the
    /// icon renders, so the main window can be created even when the menu is
    /// never opened (e.g. tapping a notification after a background launch).
    private struct MenuBarLabel: View {
        @Environment(\.openWindow) private var openWindow

        var body: some View {
            Image(systemName: "arrow.down.circle")
                .onAppear {
                    MacDLApp.openWindowAction = { id in openWindow(id: id) }
                }
        }
    }

    // Runs once: notification permission is requested separately above, and
    // launch at login is enabled here. Registering only works from /Applications,
    // so it is skipped silently when running from a build product.
    private func performFirstLaunchSetupIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: Self.firstLaunchKey) else { return }
        defaults.set(true, forKey: Self.firstLaunchKey)
        do {
            try LaunchAtLoginService.setEnabled(true)
            EngineLog.app.notice("first launch: launch at login enabled")
        } catch {
            EngineLog.app.debug("first launch: launch at login skipped (\(error.localizedDescription))")
        }
    }

    /// SwiftUI's `openWindow` action, registered by the menu bar view. It is the
    /// only reliable way to create the main window after a background launch,
    /// when `WindowGroup` has never instantiated it yet.
    @MainActor static var openWindowAction: ((String) -> Void)?

    @MainActor
    static func showWindow() {
        if let action = openWindowAction {
            action("main")
        }
        // openWindow creates the window asynchronously; poll briefly for it,
        // then activate the app and bring the main window to the front. Target
        // the main window only — a hidden settings window kept alive by SwiftUI
        // must not be picked up.
        Task { @MainActor in
            NSApp.activate(ignoringOtherApps: true)
            for _ in 0..<20 {
                if let window = mainWindow() {
                    window.makeKeyAndOrderFront(nil)
                    return
                }
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
        }
    }

    @MainActor
    static func hideWindow() {
        mainWindow()?.orderOut(nil)
    }

    @MainActor
    private static func mainWindow() -> NSWindow? {
        NSApp.windows.first { $0.identifier?.rawValue == "main" }
            ?? NSApp.windows.first { $0.title == "MacDL" }
            ?? NSApp.windows.first { $0.canBecomeKey && !isSettingsWindow($0) }
    }

    @MainActor
    private static func isSettingsWindow(_ window: NSWindow) -> Bool {
        let title = window.title.lowercased()
        return title.contains("settings") || title.contains("preferences") || title.contains("设置")
    }

    private static var isTerminating = false

    @MainActor
    static func quitWithCheck() -> Bool {
        guard !Self.isTerminating else { Self.isTerminating = false; return true }

        let vmActive = ContentViewModel.current?.downloads.filter { $0.status == .active } ?? []
        let persisted = DownloadPersistence.shared.load()
        let persistedActive = persisted.filter { $0.status == .active || $0.status == .waiting }
        let engineActive = DownloadEngine.shared.hasActiveTasks

        let count = max(vmActive.count, persistedActive.count, engineActive ? 1 : 0)
        guard count > 0 else { return true }

        let alert = NSAlert()
        alert.messageText = LanguageManager.shared.localized("Active Downloads")
        alert.informativeText = String(
            format: LanguageManager.shared.localized("There are %lld active downloads. Quit anyway?"),
            Int64(count)
        )
        alert.addButton(withTitle: LanguageManager.shared.localized("Quit"))
        alert.addButton(withTitle: LanguageManager.shared.localized("Cancel"))
        guard alert.runModal() == .alertFirstButtonReturn else { return false }

        if let vm = ContentViewModel.current { DownloadPersistence.shared.save(vm.downloads) }
        Self.isTerminating = true
        return true
    }

    @MainActor
    static func showAbout() {
        let vc = NSHostingController(rootView: AboutView().environment(LanguageManager.shared))
        let window = NSWindow(contentViewController: vc)
        window.title = LanguageManager.shared.localized("About")
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.setContentSize(NSSize(width: 380, height: 460))
        window.center()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    // Closing the last window must not quit the app - it keeps running in the
    // menu bar and downloads continue. Quit is only via Cmd+Q / the Quit menu.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        EngineLog.app.notice("didFinishLaunching")
        // Launch-in-background suppresses the main window; apply the accessory
        // policy right away so no Dock icon lingers (window events never fire
        // when the window is never shown).
        DockIconManager.shared.update()
        // Single-instance: terminate other running MacDL processes so only one menu bar icon exists.
        let bundleID = Bundle.main.bundleIdentifier ?? "com.xiaowu.MacDL"
        let myPID = ProcessInfo.processInfo.processIdentifier
        let duplicates = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .filter { $0.processIdentifier != myPID }
        for app in duplicates {
            app.terminate()
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        // macdl:// deep links (from bookmarklets, Shortcuts or the terminal)
        // hand a download URL to the app; non-macdl opens are ignored.
        for url in urls {
            guard let target = MacDLURL.downloadURL(from: url) else { continue }
            ContentViewModel.shared.addDownload(url: target)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        EngineLog.app.notice("willTerminate")
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        MacDLApp.quitWithCheck() ? .terminateNow : .terminateCancel
    }
}
