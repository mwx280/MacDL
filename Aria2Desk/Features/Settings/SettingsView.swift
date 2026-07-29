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
        Form {
            Section {
                settingsRow("globe", "Language") {
                    Picker(selection: Bindable(lang).selectedLanguage) {
                        ForEach(Language.allCases, id: \.self) { l in
                            LocalizedText(key: l.displayKey).tag(l)
                        }
                    } label: { }
                    .labelsHidden()
                }
                .id(lang.selectedLanguage)

                settingsRow("circle.lefthalf.filled", "Appearance") {
                    Picker(selection: $appearance) {
                        ForEach(Appearance.allCases, id: \.self) { a in
                            LocalizedText(key: a.displayKey).tag(a)
                        }
                    } label: { }
                    .labelsHidden()
                }
            } header: {
                LocalizedText(key: "General")
            }

            Section {
                settingsRow("antenna.radiowaves.left.and.right", "Status") { engineStatusContent }

                settingsRow("number", "Max Connections") {
                    TextField("16", text: $maxConnections)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 72)
                        .multilineTextAlignment(.trailing)
                        .onChange(of: maxConnections) { _, v in
                            client.config.maxConnections = Int(v) ?? 16
                        }
                }

                settingsRow("arrow.down.to.line", "Max Downloads") {
                    TextField("5", text: $maxConcurrent)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 72)
                        .multilineTextAlignment(.trailing)
                        .onChange(of: maxConcurrent) { _, v in
                            client.config.maxConcurrentDownloads = Int(v) ?? 5
                        }
                }
            } header: {
                LocalizedText(key: "Engine")
            }

            Section {
                LocalizedText(key: "Changes require engine restart.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .formStyle(.grouped)
    }

    private func settingsRow<C: View>(_ icon: String, _ label: String, @ViewBuilder content: () -> C) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .frame(width: 16)
                .foregroundStyle(.secondary)
            LocalizedText(key: label)
            Spacer()
            content()
        }
    }

    @ViewBuilder
    private var engineStatusContent: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(engineColor)
                .frame(width: 8, height: 8)
            LocalizedText(key: engineStatusKey)
                .foregroundStyle(engineColor)
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
