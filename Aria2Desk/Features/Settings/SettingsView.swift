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

    @State private var rpcHost: String
    @State private var rpcPort: String
    @State private var rpcToken: String
    @State private var isTesting = false

    init() {
        let config = Aria2RPCClient.shared.config
        _rpcHost = State(initialValue: config.host)
        _rpcPort = State(initialValue: String(config.port))
        _rpcToken = State(initialValue: config.secretToken)
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
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader(key: "General")

            VStack(spacing: 1) {
                pickerRow(icon: "globe", titleKey: "Language") {
                    Picker(selection: Bindable(lang).selectedLanguage) {
                        ForEach(Language.allCases, id: \.self) { l in
                            LocalizedText(key: l.displayKey).tag(l)
                        }
                    } label: { }
                    .labelsHidden()
                }
                .id(lang.selectedLanguage)

                Divider().padding(.leading, 40)

                pickerRow(icon: "circle.lefthalf.filled", titleKey: "Appearance") {
                    Picker(selection: $appearance) {
                        ForEach(Appearance.allCases, id: \.self) { a in
                            LocalizedText(key: a.displayKey).tag(a)
                        }
                    } label: { }
                    .labelsHidden()
                }
            }
            .background(.quaternary.opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private var rpcSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader(key: "RPC Connection")

            VStack(spacing: 1) {
                HStack(spacing: 16) {
                    Image(systemName: "terminal")
                        .frame(width: 20)
                        .foregroundStyle(.secondary)
                    LocalizedText(key: "Engine")
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
                .padding(.horizontal, 12)
                .padding(.vertical, 10)

                Divider()

                VStack(spacing: 8) {
                    inputRow(labelKey: "Host") {
                        TextField("localhost", text: $rpcHost)
                            .textFieldStyle(.plain)
                            .onChange(of: rpcHost) { _, v in client.config.host = v }
                    }

                    inputRow(labelKey: "Port") {
                        TextField("6800", text: $rpcPort)
                            .textFieldStyle(.plain)
                            .onChange(of: rpcPort) { _, v in client.config.port = Int(v) ?? 6800 }
                    }

                    inputRow(labelKey: "Token") {
                        SecureField("Secret Token", text: $rpcToken)
                            .textFieldStyle(.plain)
                            .onChange(of: rpcToken) { _, v in client.config.secretToken = v }
                    }

                    HStack(spacing: 10) {
                        Button {
                            Task {
                                isTesting = true
                                _ = await client.testConnection()
                                isTesting = false
                            }
                        } label: {
                            if isTesting {
                                HStack(spacing: 6) {
                                    ProgressView().controlSize(.small)
                                    LocalizedText(key: "Testing...")
                                }
                            } else {
                                LocalizedText(key: "Test Connection")
                            }
                        }
                        .disabled(isTesting)

                        HStack(spacing: 4) {
                            Circle().fill(rpcColor).frame(width: 6, height: 6)
                            LocalizedText(key: rpcStatusKey)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.leading, 64)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
            }
            .background(.quaternary.opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private func sectionHeader(key: String) -> some View {
        LocalizedText(key: key)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.leading, 8)
            .padding(.bottom, 6)
    }

    private func pickerRow<C: View>(icon: String, titleKey: String, @ViewBuilder content: () -> C) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .frame(width: 20)
                .foregroundStyle(.secondary)
            LocalizedText(key: titleKey)
                .foregroundStyle(.primary)
            Spacer()
            content()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func inputRow<C: View>(labelKey: String, @ViewBuilder content: () -> C) -> some View {
        HStack(spacing: 12) {
            LocalizedText(key: labelKey)
                .foregroundStyle(.secondary)
                .frame(width: 52, alignment: .leading)
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

    private var rpcColor: Color {
        switch client.status {
        case .connected: .green
        case .connecting: .orange
        case .disconnected: .gray
        }
    }

    private var rpcStatusKey: String {
        switch client.status {
        case .connected: "Connected"
        case .connecting: "Connecting..."
        case .disconnected: "Disconnected"
        }
    }
}
