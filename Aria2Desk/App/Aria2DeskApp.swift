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
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About Aria2Desk") { Aria2DeskApp.showAbout() }
            }
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

    @MainActor
    static func showAbout() {
        let vc = NSHostingController(rootView: AboutView())
        let window = NSWindow(contentViewController: vc)
        window.title = LanguageManager.shared.localized("About")
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.setContentSize(NSSize(width: 360, height: 280))
        window.center()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}

private struct AboutView: View {
    @State private var refresh = UUID()

    var body: some View {
        VStack(spacing: 20) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .frame(width: 64, height: 64)

            Text("Aria2Desk")
                .font(.system(size: 20, weight: .medium))

            Text("xiaowu")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)

            Divider()

            VStack(spacing: 6) {
                Label(title: { Text("小舞") }, icon: { Image(systemName: "person") })
                    .font(.system(size: 13))
                Label(title: { Text("xiaowu") }, icon: { Image(systemName: "link") })
                    .font(.system(size: 13))
            }

            Spacer()

            Text("Copyright © 2026 xiaowu")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
        .padding(24)
        .frame(width: 360, height: 280)
        .id(refresh)
        .onReceive(NotificationCenter.default.publisher(for: .languageChanged)) { _ in
            refresh = UUID()
        }
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

        Button { Aria2DeskApp.showAbout() } label: {
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
