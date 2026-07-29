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
            Button("Show Window") { showWindow() }
            Button("Hide Window") { hideWindow() }

            Divider()

            SettingsLink {
                Text("Settings...")
            }

            Divider()

            Button("Quit") { NSApp.terminate(nil) }
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
