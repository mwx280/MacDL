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
}

private struct MenuBarContent: View {
    var body: some View {
        Button { Aria2DeskApp.showWindow() } label: {
            Label(title: { Text(verbatim: LanguageManager.shared.localized("Show Window")) }, icon: { Image(systemName: "macwindow") })
        }

        Button { Aria2DeskApp.hideWindow() } label: {
            Label(title: { Text(verbatim: LanguageManager.shared.localized("Hide Window")) }, icon: { Image(systemName: "rectangle.dashed") })
        }

        Button { NSApp.orderFrontStandardAboutPanel(nil) } label: {
            Label(title: { Text(verbatim: LanguageManager.shared.localized("About")) }, icon: { Image(systemName: "info.circle") })
        }

        Divider()

        SettingsLink {
            Label(title: { Text(verbatim: LanguageManager.shared.localized("Preferences")) }, icon: { Image(systemName: "gearshape") })
        }

        Divider()

        Button { NSApp.terminate(nil) } label: {
            Label(title: { Text(verbatim: LanguageManager.shared.localized("Quit")) }, icon: { Image(systemName: "xmark.rectangle") })
        }
    }
}
