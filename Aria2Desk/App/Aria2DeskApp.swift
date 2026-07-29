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
            Button { showWindow() } label: { Label("Show Window", systemImage: "macwindow") }
            Button { hideWindow() } label: { Label("Hide Window", systemImage: "macwindow.badge.xmark") }

            Divider()

            SettingsLink {
                Label("Settings...", systemImage: "gearshape")
            }

            Divider()

            Button { NSApp.terminate(nil) } label: { Label("Quit", systemImage: "xmark.circle") }
        } label: {
            Image(systemName: "arrow.down.circle")
        }
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
