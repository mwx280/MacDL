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
    @State private var rocketY: CGFloat = 280
    @State private var flameScale: CGFloat = 0
    @State private var countdownText = ""
    @State private var bgOpacity: Double = 0
    @State private var stars: [(x: CGFloat, y: CGFloat, size: CGFloat)] = []
    @State private var smokeOpacities: [Double] = Array(repeating: 0, count: 8)

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
            if phase > 0 { launchScene }
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
                    if iconTapCount >= 5 { triggerLaunch() }
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
    private var launchScene: some View {
        ZStack {
            Color.black.opacity(0.88 * bgOpacity)

            ForEach(Array(stars.enumerated()), id: \.offset) { i, s in
                Circle()
                    .fill(.white)
                    .frame(width: s.size, height: s.size)
                    .position(x: s.x, y: s.y)
            }

            if phase == 1 {
                Text(countdownText)
                    .font(.system(size: 72, weight: .black))
                    .foregroundStyle(.white)
            }

            if phase == 2 {
                VStack(spacing: 0) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(.orange)
                        .scaleEffect(x: flameScale, y: flameScale + 0.3)
                    Image(systemName: "rocket.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(.white)
                }
                .offset(y: rocketY)

                ForEach(Array(smokeOpacities.enumerated()), id: \.offset) { i, op in
                    Circle()
                        .fill(.white.opacity(0.3))
                        .frame(width: CGFloat(i * 4 + 6))
                        .position(x: 190 + CGFloat(i - 4) * 12, y: rocketY + 50)
                        .opacity(op)
                }
            }
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
                try? await Task.sleep(for: .milliseconds(180 / flashColors.count))
            }
            flashIndex = -1
        }
    }

    private func triggerLaunch() {
        guard phase == 0 else { return }
        iconTapCount = 0
        stars = (0..<30).map { _ in
            (CGFloat.random(in: 0...380), CGFloat.random(in: 0...460), CGFloat.random(in: 1...3))
        }
        phase = 1
        runLaunch()
    }

    private func runLaunch() {
        let speed = totalSpeed
        let flyDuration: Double
        let flameMax: CGFloat
        let endY: CGFloat = -100

        if speed == 0 {
            flyDuration = 0
            flameMax = 0
        } else if speed < 500_000 {
            flyDuration = 3.0
            flameMax = 0.6
        } else if speed < 5_000_000 {
            flyDuration = 2.0
            flameMax = 1.0
        } else {
            flyDuration = 1.2
            flameMax = 1.5
        }

        Task {
            withAnimation(.easeIn(duration: 0.4)) { bgOpacity = 1 }

            for (i, n) in ["3", "2", "1"].enumerated() {
                countdownText = n
                try? await Task.sleep(for: .milliseconds(500))
                if i < 2 { countdownText = ""; try? await Task.sleep(for: .milliseconds(100)) }
            }
            countdownText = "🚀"
            try? await Task.sleep(for: .milliseconds(300))
            countdownText = ""

            guard speed > 0 else {
                countdownText = "💤 No tasks..."
                try? await Task.sleep(for: .seconds(1.5))
                endLaunch()
                return
            }

            phase = 2
            rocketY = 280
            withAnimation(.easeIn(duration: 0.15)) { flameScale = flameMax }

            for i in smokeOpacities.indices {
                smokeOpacities[i] = 0.6
                try? await Task.sleep(for: .milliseconds(Int(80 / flameMax)))
            }

            withAnimation(.easeIn(duration: flyDuration)) {
                rocketY = endY
            }

            try? await Task.sleep(for: .milliseconds(Int(flyDuration * 800)))

            for i in smokeOpacities.indices {
                withAnimation(.easeOut(duration: 0.3)) { smokeOpacities[i] = 0 }
            }

            try? await Task.sleep(for: .milliseconds(400))
            endLaunch()
        }
    }

    private func endLaunch() {
        Task {
            withAnimation(.easeOut(duration: 0.4)) {
                bgOpacity = 0
                flameScale = 0
            }
            try? await Task.sleep(for: .milliseconds(500))
            phase = 0
            countdownText = ""
            rocketY = 280
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
