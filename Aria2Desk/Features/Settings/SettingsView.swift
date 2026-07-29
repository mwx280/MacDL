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
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                GroupBox {
                    Picker(selection: Bindable(lang).selectedLanguage) {
                        ForEach(Language.allCases, id: \.self) { lang in
                            Text(lang.displayName).tag(lang)
                        }
                    } label: { }
                    .labelsHidden()
                    .frame(maxWidth: .infinity, alignment: .leading)
                } label: {
                    Label("Language", systemImage: "globe")
                }

                GroupBox {
                    Picker(selection: $appearance) {
                        ForEach(Appearance.allCases, id: \.self) { a in
                            Text(a.displayName).tag(a)
                        }
                    } label: { }
                    .labelsHidden()
                    .frame(maxWidth: .infinity, alignment: .leading)
                } label: {
                    Label("Appearance", systemImage: "circle.lefthalf.filled")
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        fieldRow(label: "Host") {
                            TextField("localhost", text: $rpcHost)
                                .textFieldStyle(.roundedBorder)
                                .onChange(of: rpcHost) { _, new in client.config.host = new }
                        }

                        fieldRow(label: "Port") {
                            TextField("6800", text: $rpcPort)
                                .textFieldStyle(.roundedBorder)
                                .onChange(of: rpcPort) { _, new in
                                    client.config.port = Int(new) ?? 6800
                                }
                        }

                        fieldRow(label: "Token") {
                            SecureField("Secret Token", text: $rpcToken)
                                .textFieldStyle(.roundedBorder)
                                .onChange(of: rpcToken) { _, new in
                                    client.config.secretToken = new
                                }
                        }

                        HStack {
                            Button {
                                Task {
                                    isTesting = true
                                    _ = await client.testConnection()
                                    isTesting = false
                                }
                            } label: {
                                if isTesting {
                                    HStack(spacing: 6) {
                                        ProgressView()
                                            .controlSize(.small)
                                        Text("Testing...")
                                    }
                                } else {
                                    Text("Test Connection")
                                }
                            }
                            .disabled(isTesting)

                            Spacer()

                            HStack(spacing: 6) {
                                Circle()
                                    .fill(connectionColor)
                                    .frame(width: 8, height: 8)
                                Text(connectionText)
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(4)
                } label: {
                    Label("RPC Connection", systemImage: "terminal")
                }
            }
            .padding(20)
        }
    }

    private func fieldRow<Content: View>(label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .frame(width: 48, alignment: .trailing)
                .foregroundStyle(.secondary)
            content()
        }
    }

    private var connectionColor: Color {
        switch client.status {
        case .disconnected: .gray
        case .connecting: .orange
        case .connected: .green
        }
    }

    private var connectionText: String {
        switch client.status {
        case .disconnected: "Disconnected"
        case .connecting: "Connecting..."
        case .connected: "Connected"
        }
    }
}
