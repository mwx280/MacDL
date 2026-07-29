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
    @State private var langCode = LanguageManager.shared.selectedLanguage.rawValue

    var body: some View {
        Group {
            Button { Aria2DeskApp.showWindow() } label: {
                Text(verbatim: t("Show Window"))
            }

            Button { Aria2DeskApp.hideWindow() } label: {
                Label(title: { Text(verbatim: t("Hide Window")) }, icon: { Image(systemName: "rectangle.dashed") })
            }

            Divider()

            SettingsLink {
                Label(title: { Text(verbatim: t("Preferences")) }, icon: { Image(systemName: "gearshape") })
            }

            Divider()

            Button { NSApp.terminate(nil) } label: {
                Label(title: { Text(verbatim: t("Quit")) }, icon: { Image(systemName: "xmark.rectangle") })
            }
        }
        .id("menu_\(langCode)")
        .onReceive(NotificationCenter.default.publisher(for: .languageChanged)) { _ in
            langCode = LanguageManager.shared.selectedLanguage.rawValue
        }
    }

    private func t(_ key: String) -> String {
        LanguageManager.shared.localized(key)
    }
}
