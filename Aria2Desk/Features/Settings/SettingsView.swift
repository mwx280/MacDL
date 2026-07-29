import SwiftUI

enum Appearance: String, CaseIterable {
    case system = ""
    case light
    case dark

    var displayName: LocalizedStringKey {
        switch self {
        case .system: "Follow System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
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
            sectionHeader("General")

            VStack(spacing: 1) {
                pickerRow(icon: "globe", title: "Language") {
                    Picker(selection: Bindable(lang).selectedLanguage) {
                        ForEach(Language.allCases, id: \.self) { l in
                            Text(l.displayName).tag(l)
                        }
                    } label: { }
                    .labelsHidden()
                }

                Divider().padding(.leading, 40)

                pickerRow(icon: "circle.lefthalf.filled", title: "Appearance") {
                    Picker(selection: $appearance) {
                        ForEach(Appearance.allCases, id: \.self) { a in
                            Text(a.displayName).tag(a)
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
            sectionHeader("RPC Connection")

            VStack(spacing: 1) {
                HStack(spacing: 16) {
                    Image(systemName: "terminal")
                        .frame(width: 20)
                        .foregroundStyle(.secondary)
                    Text("Engine")
                        .foregroundStyle(.secondary)
                    Spacer()
                    HStack(spacing: 6) {
                        Circle()
                            .fill(engineColor)
                            .frame(width: 8, height: 8)
                        Text(engineText)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)

                Divider()

                VStack(spacing: 8) {
                    inputRow(label: "Host") {
                        TextField("localhost", text: $rpcHost)
                            .textFieldStyle(.plain)
                            .onChange(of: rpcHost) { _, v in client.config.host = v }
                    }

                    inputRow(label: "Port") {
                        TextField("6800", text: $rpcPort)
                            .textFieldStyle(.plain)
                            .onChange(of: rpcPort) { _, v in client.config.port = Int(v) ?? 6800 }
                    }

                    inputRow(label: "Token") {
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
                                    Text("Testing...")
                                }
                            } else {
                                Text("Test Connection")
                            }
                        }
                        .disabled(isTesting)

                        HStack(spacing: 4) {
                            Circle().fill(rpcColor).frame(width: 6, height: 6)
                            Text(rpcText)
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

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.leading, 8)
            .padding(.bottom, 6)
    }

    private func pickerRow<C: View>(icon: String, title: String, @ViewBuilder content: () -> C) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .frame(width: 20)
                .foregroundStyle(.secondary)
            Text(title)
                .foregroundStyle(.primary)
            Spacer()
            content()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func inputRow<C: View>(label: String, @ViewBuilder content: () -> C) -> some View {
        HStack(spacing: 12) {
            Text(label)
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

    private var engineText: String {
        switch client.engineState {
        case .running: "Running"
        case .starting: "Starting..."
        case .stopped: "Stopped"
        case .error(let msg): msg
        }
    }

    private var rpcColor: Color {
        switch client.status {
        case .connected: .green
        case .connecting: .orange
        case .disconnected: .gray
        }
    }

    private var rpcText: String {
        switch client.status {
        case .connected: "Connected"
        case .connecting: "Connecting..."
        case .disconnected: "Disconnected"
        }
    }
}
