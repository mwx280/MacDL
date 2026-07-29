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
                Button { Aria2DeskApp.showAbout() } label: {
                    Label("About Aria2Desk", systemImage: "info.circle")
                }
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
        window.setContentSize(NSSize(width: 380, height: 440))
        window.center()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}

private struct AboutView: View {
    @State private var refresh = UUID()
    @State private var iconTapCount = 0

    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }
    private var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    var body: some View {
        VStack(spacing: 12) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .frame(width: 64, height: 64)
                .onTapGesture { iconTapCount += 1 }

            Text("Aria2Desk")
                .font(.system(size: 20, weight: .medium))

            Text("Version \(version) (build \(build))")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            Divider()

            VStack(spacing: 8) {
                sectionHeader("Tech Stack")
                Text("SwiftUI · Aria2")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Divider()

            VStack(spacing: 8) {
                sectionHeader("Developer")
                Label(title: { Text("小舞 / xiaowu") }, icon: { Image(systemName: "person") })
                    .font(.system(size: 12))
            }

            Button { NSWorkspace.shared.open(URL(string: "https://github.com/mwx280")!) } label: {
                Label(title: { Text("github.com/mwx280") }, icon: { Image(systemName: "arrow.up.right.square") })
                    .font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tint)

            VStack(spacing: 4) {
                Text("MIT License")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                Text("Copyright © 2026 xiaowu")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(24)
        .frame(width: 380, height: 420)
        .id(refresh)
        .onReceive(NotificationCenter.default.publisher(for: .languageChanged)) { _ in
            refresh = UUID()
        }
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.tertiary)
            .textCase(.uppercase)
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
