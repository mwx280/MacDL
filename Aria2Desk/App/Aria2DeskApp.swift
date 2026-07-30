import SwiftUI

@main
struct Aria2DeskApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    init() {
        NSWindow.allowsAutomaticWindowTabbing = false
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(LanguageManager.shared)
        }
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button { Aria2DeskApp.showAbout() } label: {
                    Label("About Aria2Desk", systemImage: "info.circle")
                }
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
        guard let vm = ContentViewModel.current else { return .terminateNow }
        let active = vm.downloads.filter { $0.status == .active }
        guard !active.isEmpty else { return .terminateNow }

        let alert = NSAlert()
        alert.messageText = LanguageManager.shared.localized("Active Downloads")
        alert.informativeText = String(
            format: LanguageManager.shared.localized("There are %lld active downloads. Quit anyway?"),
            Int64(active.count)
        )
        alert.addButton(withTitle: LanguageManager.shared.localized("Quit"))
        alert.addButton(withTitle: LanguageManager.shared.localized("Cancel"))

        if alert.runModal() == .alertFirstButtonReturn {
            DownloadPersistence.shared.save(vm.downloads)
            return .terminateNow
        }
        return .terminateCancel
    }
}
