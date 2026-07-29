import SwiftUI

@main
struct Aria2DeskApp: App {
    init() {
        print("[Aria2Desk] App init, starting engine...")
        Aria2RPCClient.shared.startEngine()
        print("[Aria2Desk] Engine state: \(Aria2RPCClient.shared.engineState)")
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(LanguageManager.shared)
                .environment(Aria2RPCClient.shared)
        }

        Settings {
            SettingsView()
                .environment(LanguageManager.shared)
                .environment(Aria2RPCClient.shared)
        }

        MenuBarExtra {
            Button { showWindow() } label: {
                Label(title: { LocalizedText(key: "Show Window") }, icon: { Image(systemName: "macwindow") })
            }

            Button { hideWindow() } label: {
                Label(title: { LocalizedText(key: "Hide Window") }, icon: { Image(systemName: "eye.slash") })
            }

            Divider()

            SettingsLink {
                Label(title: { LocalizedText(key: "Settings...") }, icon: { Image(systemName: "gearshape") })
            }

            Divider()

            Button { NSApp.terminate(nil) } label: {
                Label(title: { LocalizedText(key: "Quit") }, icon: { Image(systemName: "xmark.circle") })
            }
        } label: {
            Image(systemName: "arrow.down.circle")
        }
        .environment(LanguageManager.shared)
    }

    @MainActor
    private func showWindow() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first?.makeKeyAndOrderFront(nil)
    }

    @MainActor
    private func hideWindow() {
        NSApp.windows.first?.orderOut(nil)
    }
}
