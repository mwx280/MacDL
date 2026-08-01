import SwiftUI
import MacDLCore

@main
struct MacDLApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    init() {
        NSWindow.allowsAutomaticWindowTabbing = false
        ChunkDownloadTask.maxConnectionsProvider = { SettingsStore.shared.maxConnections }
        // Ask up front so the first download's "started" banner isn't dropped
        // while the permission prompt is still pending. No-op if already decided.
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil {
            DownloadNotifier.shared.requestAuthorization()
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(LanguageManager.shared)
        }
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

        MenuBarExtra {
            MenuBarContent()
        } label: {
            Image(systemName: "arrow.down.circle")
        }
    }

    @MainActor
    static func showWindow() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first?.makeKeyAndOrderFront(nil)
    }

    @MainActor
    static func hideWindow() {
        NSApp.windows.first?.orderOut(nil)
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
        let vc = NSHostingController(rootView: AboutView())
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
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        MacDLApp.quitWithCheck() ? .terminateNow : .terminateCancel
    }
}
