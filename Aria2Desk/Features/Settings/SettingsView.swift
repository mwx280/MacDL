import SwiftUI
import AppKit

enum Appearance: String, CaseIterable {
    case system = "system"
    case light
    case dark

    var displayKey: String {
        switch self {
        case .system: "Follow System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    func apply() {
        switch self {
        case .system:
            NSApp.appearance = nil
        case .light:
            NSApp.appearance = NSAppearance(named: .aqua)
        case .dark:
            NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }
}

struct SettingsView: View {
    @Environment(LanguageManager.self) var lang
    @Environment(Aria2RPCClient.self) var client
    @AppStorage("appearance") private var appearance: Appearance = .system

    @State private var maxConnections: String
    @State private var maxConcurrent: String

    init() {
        let config = Aria2RPCClient.shared.config
        _maxConnections = State(initialValue: String(config.maxConnections))
        _maxConcurrent = State(initialValue: String(config.maxConcurrentDownloads))
    }

    var body: some View {
        ScrollView(.vertical) {
            VStack(spacing: 24) {
                generalSection
                rpcSection
            }
            .padding(24)
        }
    }

    private var generalSection: some View {
        GroupBox {
            VStack(spacing: 12) {
                HStack {
                    Label(title: { LocalizedText(key: "Language") }, icon: { Image(systemName: "globe") })
                        .foregroundStyle(.secondary)
                    Spacer()
                    Picker(selection: Bindable(lang).selectedLanguage) {
                        ForEach(Language.allCases, id: \.self) { l in
                            LocalizedText(key: l.displayKey).tag(l)
                        }
                    } label: { }
                    .labelsHidden()
                }
                .id(lang.selectedLanguage)

                Divider()

                HStack {
                    Label(title: { LocalizedText(key: "Appearance") }, icon: { Image(systemName: "circle.lefthalf.filled") })
                        .foregroundStyle(.secondary)
                    Spacer()
                    Picker(selection: $appearance) {
                        ForEach(Appearance.allCases, id: \.self) { a in
                            LocalizedText(key: a.displayKey).tag(a)
                        }
                    } label: { }
                    .labelsHidden()
                }
            }
            .padding(.vertical, 4)
        } label: {
            Label(title: { LocalizedText(key: "General") }, icon: { Image(systemName: "gear") })
        }
    }

    private var rpcSection: some View {
        GroupBox {
            VStack(spacing: 12) {
                engineStatusRow
                Divider()
                labeledRow(labelKey: "Max Connections", systemImage: "number") {
                    TextField("16", text: $maxConnections)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                        .onChange(of: maxConnections) { _, v in
                            client.config.maxConnections = Int(v) ?? 16
                        }
                }
                labeledRow(labelKey: "Max Downloads", systemImage: "arrow.down.to.line") {
                    TextField("5", text: $maxConcurrent)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                        .onChange(of: maxConcurrent) { _, v in
                            client.config.maxConcurrentDownloads = Int(v) ?? 5
                        }
                }
                HStack {
                    Spacer()
                    LocalizedText(key: "Changes require engine restart.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.vertical, 4)
        } label: {
            Label(title: { LocalizedText(key: "Engine") }, icon: { Image(systemName: "gearshape.2") })
        }
    }

    private var engineStatusRow: some View {
        HStack {
            Label(title: { LocalizedText(key: "Status") }, icon: { Image(systemName: "antenna.radiowaves.left.and.right") })
                .foregroundStyle(.secondary)
            Spacer()
            HStack(spacing: 6) {
                Circle()
                    .fill(engineColor)
                    .frame(width: 8, height: 8)
                LocalizedText(key: engineStatusKey)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func labeledRow<C: View>(labelKey: String, systemImage: String, @ViewBuilder content: () -> C) -> some View {
        HStack {
            Label(title: { LocalizedText(key: labelKey) }, icon: { Image(systemName: systemImage) })
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            content()
        }
    }

    private var engineColor: Color {
        switch client.engineState {
        case .running: .green
        case .starting: .orange
        case .stopped: .gray
        case .error: .red
        }
    }

    private var engineStatusKey: String {
        switch client.engineState {
        case .running: "Running"
        case .starting: "Starting..."
        case .stopped: "Stopped"
        case .error: "Error"
        }
    }

}
