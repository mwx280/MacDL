import SwiftUI
import AppKit

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
        window.setContentSize(NSSize(width: 380, height: 460))
        window.center()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}

private struct AboutView: View {
    @State private var refresh = UUID()
    @State private var iconTapCount = 0

    @State private var flashIndex = -1
    @State private var phase = 0
    @State private var terminalLines: [String] = []
    @State private var progress: Double = 0
    @State private var bgOpacity: Double = 0

    private let flashColors: [Color] = [.red, .orange, .yellow, .green, .blue, .purple, .pink]

    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }
    private var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }
    private var totalSpeed: Int64 {
        Download.mock.reduce(0) { $0 + $1.downloadSpeed }
    }

    var body: some View {
        ZStack {
            contentView.opacity(phase == 0 ? 1 : 0.15)
            if phase > 0 { terminalScene }
        }
        .frame(width: 380, height: 460)
        .id(refresh)
        .onReceive(NotificationCenter.default.publisher(for: .languageChanged)) { _ in
            refresh = UUID()
        }
    }

    private var contentView: some View {
        VStack(spacing: 12) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .frame(width: 64, height: 64)
                .onTapGesture {
                    iconTapCount += 1
                    if iconTapCount >= 5 { triggerTerminal() }
                    else { flashOnce() }
                }

            Text("Aria2Desk")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(flashIndex >= 0 ? flashColors[flashIndex] : .primary)

            Text(String(format: LanguageManager.shared.localized("Version %@ (build %@)"), version, build))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            Divider()

            VStack(spacing: 8) {
                sectionHeader(LanguageManager.shared.localized("Tech Stack"))
                Text("SwiftUI · Aria2")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Divider()

            VStack(spacing: 8) {
                sectionHeader(LanguageManager.shared.localized("Developer"))
                Label(title: { Text("小舞 / xiaowu") }, icon: { Image(systemName: "person") })
                    .font(.system(size: 12))
            }

            Button { NSWorkspace.shared.open(URL(string: "https://github.com/mwx280")!) } label: {
                Label(title: { Text("github.com/mwx280") }, icon: { Image(systemName: "arrow.up.right.square") })
                    .font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tint)

            VStack(spacing: 6) {
                Label {
                    Text(verbatim: LanguageManager.shared.localized("If you like this project, please give it a star ⭐"))
                        .font(.system(size: 11))
                } icon: {
                    Image(systemName: "star.fill")
                        .foregroundStyle(.yellow)
                        .font(.system(size: 10))
                }
            }
            .padding(.vertical, 4)

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
    }

    @ViewBuilder
    private var terminalScene: some View {
        ZStack {
            Color.black.opacity(0.92 * bgOpacity)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(terminalLines.enumerated()), id: \.offset) { i, line in
                    Text(line)
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(i == terminalLines.count - 1 && progress < 1
                            ? .green.opacity(0.7)
                            : .green)
                        .opacity(i < terminalLines.count - 1 || progress >= 1 ? 1 : 0.7)
                }

                if !terminalLines.isEmpty {
                    ProgressView(value: progress)
                        .tint(.green)
                        .frame(width: 280)
                        .opacity(terminalLines.count >= 4 ? 1 : 0)
                }
            }
            .padding(24)
        }
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(verbatim: text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.tertiary)
            .textCase(.uppercase)
    }

    private func flashOnce() {
        guard flashIndex < 0 else { return }
        Task {
            for i in flashColors.indices {
                flashIndex = i
                try? await Task.sleep(for: .milliseconds(500 / flashColors.count))
            }
            flashIndex = -1
        }
    }

    private func triggerTerminal() {
        guard phase == 0 else { return }
        iconTapCount = 0
        terminalLines = []
        progress = 0
        phase = 1
        runTerminal()
    }

    private func runTerminal() {
        let speed = totalSpeed
        let barDuration: Double
        let barSpeed: String

        if speed == 0 {
            barDuration = 5.0; barSpeed = "0 B/s"
        } else if speed < 500_000 {
            barDuration = 3.0; barSpeed = formatSpeed(speed)
        } else if speed < 5_000_000 {
            barDuration = 2.0; barSpeed = formatSpeed(speed)
        } else {
            barDuration = 1.0; barSpeed = formatSpeed(speed)
        }

        Task {
            withAnimation(.easeIn(duration: 0.3)) { bgOpacity = 1 }

            try? await Task.sleep(for: .milliseconds(300))
            typeLine("> Initializing download sequence...")
            try? await Task.sleep(for: .milliseconds(400))
            typeLine("> Connecting to server...")
            try? await Task.sleep(for: .milliseconds(400))
            typeLine("> Download speed: \(barSpeed)")
            try? await Task.sleep(for: .milliseconds(300))
            typeLine("> Downloading classified data...")

            try? await Task.sleep(for: .milliseconds(200))

            let start = CACurrentMediaTime()
            while true {
                let elapsed = CACurrentMediaTime() - start
                let p = min(elapsed / barDuration, 1)
                await MainActor.run { progress = p }
                if p >= 1 { break }
                try? await Task.sleep(for: .milliseconds(30))
            }

            typeLine("> ████████████████ 100%")
            try? await Task.sleep(for: .milliseconds(500))
            typeLine("> Access granted.")
            try? await Task.sleep(for: .milliseconds(800))
            typeLine("> 🎉 You found the easter egg!")
            try? await Task.sleep(for: .seconds(2))
            endTerminal()
        }
    }

    private func typeLine(_ text: String) {
        terminalLines.append(text)
    }

    private func endTerminal() {
        Task {
            withAnimation(.easeOut(duration: 0.4)) { bgOpacity = 0 }
            try? await Task.sleep(for: .milliseconds(500))
            terminalLines = []
            progress = 0
            phase = 0
        }
    }

    private func formatSpeed(_ bytes: Int64) -> String {
        let f = ByteCountFormatter()
        f.countStyle = .binary
        return f.string(fromByteCount: bytes) + "/s"
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
