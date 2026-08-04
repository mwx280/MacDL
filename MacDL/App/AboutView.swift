import SwiftUI

struct AboutView: View {
    @Environment(LanguageManager.self) private var lang
    @State private var iconTapCount = 0

    @State private var flashIndex = -1
    @State private var phase = 0
    @State private var terminalLines: [String] = []
    @State private var progress: Double = 0
    @State private var bgOpacity: Double = 0
    @State private var showCursor = true
    @State private var matrixChars: [(x: CGFloat, char: String, speed: Double)] = []
    @State private var isComplete = false

    private let flashColors: [Color] = [.red, .orange, .yellow, .green, .blue, .purple, .pink]

    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }
    private var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }
    private var totalSpeed: Int64 { 12_582_912 }

    var body: some View {
        ZStack {
            contentView.opacity(phase == 0 ? 1 : 0.15)
            if phase > 0 { terminalScene }
        }
        .frame(width: 380, height: 460)
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

            Text("MacDL")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(flashIndex >= 0 ? flashColors[flashIndex] : .primary)

            Text(String(format: lang.localized("Version %@ (build %@)"), version, build))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            Divider()

            VStack(spacing: 8) {
                sectionHeader(lang.localized("Tech Stack"))
                Text("SwiftUI · URLSession")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Divider()

            VStack(spacing: 8) {
                sectionHeader(lang.localized("Developer"))
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
                    Text(verbatim: lang.localized("If you like this project, please give it a star ⭐"))
                        .font(.system(size: 11))
                } icon: {
                    Image(systemName: "star.fill")
                        .foregroundStyle(.yellow)
                        .font(.system(size: 10))
                }
            }
            .padding(.vertical, 4)

            VStack(spacing: 4) {
                Text("GPL-3.0 License")
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
            Color.black.opacity(0.95 * bgOpacity)

            TimelineView(.animation(minimumInterval: 0.05)) { _ in
                Canvas { ctx, size in
                    for c in matrixChars {
                        ctx.draw(Text(c.char).font(.system(size: 10, design: .monospaced)).foregroundColor(.green.opacity(0.15)), at: CGPoint(x: c.x, y: (CACurrentMediaTime() * c.speed * 30).truncatingRemainder(dividingBy: size.height + 20) - 10))
                    }
                }
            }
            .opacity(bgOpacity)

            VStack(alignment: .leading, spacing: 10) {
                Spacer().frame(height: 12)

                ForEach(Array(terminalLines.enumerated()), id: \.offset) { i, line in
                    HStack(spacing: 0) {
                        Text(line)
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundStyle(.green)
                            .glow(color: .green, radius: i == terminalLines.count - 1 && !isComplete ? 2 : 1)
                        if i == terminalLines.count - 1 && showCursor && !isComplete {
                            Text("█")
                                .font(.system(size: 13, design: .monospaced))
                                .foregroundStyle(.green)
                        }
                    }
                }

                if terminalLines.count >= 4 && !isComplete {
                    ProgressView(value: progress)
                        .tint(.green)
                        .frame(width: 280)
                }

                if isComplete {
                    Spacer().frame(height: 8)
                    Text("🖱  " + lang.localized("Click anywhere to exit"))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.green.opacity(showCursor ? 0.8 : 0.3))
                }
            }
            .padding(20)

            VStack { Spacer(); scanlineOverlay; Spacer().frame(height: 0) }
        }
        .onTapGesture { if isComplete { endTerminal() } }
    }

    private var scanlineOverlay: some View {
        Rectangle()
            .fill(.black.opacity(0.04))
            .frame(height: 2)
            .offset(y: CGFloat.random(in: -200...200))
            .opacity(0.5)
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
        isComplete = false
        matrixChars = (0..<25).map { _ in
            (CGFloat.random(in: 10...370), String(UnicodeScalar(Int.random(in: 0x30A0...0x30FF))!), Double.random(in: 0.3...1))
        }
        showCursor = true
        phase = 1

        Task {
            while phase == 1 {
                try? await Task.sleep(for: .milliseconds(500))
                await MainActor.run { showCursor.toggle() }
            }
        }

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
            typeLine("> \(lang.localized("Initializing download sequence..."))")
            try? await Task.sleep(for: .milliseconds(400))
            typeLine("> \(lang.localized("Connecting to server..."))")
            try? await Task.sleep(for: .milliseconds(400))
            typeLine("> " + String(format: lang.localized("Download speed: %@"), barSpeed))
            try? await Task.sleep(for: .milliseconds(300))
            typeLine("> \(lang.localized("Downloading classified data..."))")

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
            typeLine("> \(lang.localized("Access granted."))")
            try? await Task.sleep(for: .milliseconds(600))
            typeLine("> \(lang.localized("You found the easter egg!"))")
            try? await Task.sleep(for: .milliseconds(400))
            isComplete = true
        }
    }

    private func typeLine(_ text: String) {
        terminalLines.append(text)
    }

    private func endTerminal() {
        phase = 0
        Task {
            withAnimation(.easeOut(duration: 0.3)) { bgOpacity = 0 }
            try? await Task.sleep(for: .milliseconds(300))
            terminalLines = []
            progress = 0
            isComplete = false
        }
    }
}

extension View {
    func glow(color: Color, radius: CGFloat) -> some View {
        self.shadow(color: color, radius: radius)
            .shadow(color: color, radius: radius * 2)
    }
}
