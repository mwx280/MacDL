import SwiftUI

@main
struct MacDLApp: App {
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
                Button { MacDLApp.showAbout() } label: {
                    Label("About MacDL", systemImage: "info.circle")
                }
            }
            CommandGroup(replacing: .appTermination) {
                Button { MacDLApp.quitWithCheck() } label: {
                    Text("Quit MacDL")
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

    @MainActor
    static func quitWithCheck() {
        if let vm = ContentViewModel.current {
            let active = vm.downloads.filter { $0.status == .active }
            if active.isEmpty { NSApp.terminate(nil); return }
            let alert = NSAlert()
            alert.messageText = LanguageManager.shared.localized("Active Downloads")
            alert.informativeText = String(
                format: LanguageManager.shared.localized("There are %lld active downloads. Quit anyway?"),
                Int64(active.count)
            )
            alert.addButton(withTitle: LanguageManager.shared.localized("Quit"))
            alert.addButton(withTitle: LanguageManager.shared.localized("Cancel"))
            if alert.runModal() != .alertFirstButtonReturn { return }
            DownloadPersistence.shared.save(vm.downloads)
        } else if DownloadEngine.shared.hasActiveTasks {
            let downloads = DownloadPersistence.shared.load()
            let active = downloads.filter { $0.status == .active || $0.status == .waiting }
            if active.isEmpty { NSApp.terminate(nil); return }
            let alert = NSAlert()
            alert.messageText = LanguageManager.shared.localized("Active Downloads")
            alert.informativeText = String(
                format: LanguageManager.shared.localized("There are %lld active downloads. Quit anyway?"),
                Int64(active.count)
            )
            alert.addButton(withTitle: LanguageManager.shared.localized("Quit"))
            alert.addButton(withTitle: LanguageManager.shared.localized("Cancel"))
            if alert.runModal() != .alertFirstButtonReturn { return }
            DownloadPersistence.shared.save(downloads)
        }
        NSApp.terminate(nil)
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
}
