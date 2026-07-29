import SwiftUI

struct RPCConfigView: View {
    @Environment(Aria2RPCClient.self) var client
    @State private var host: String
    @State private var port: String
    @State private var token: String
    @State private var isTesting = false

    init() {
        let config = Aria2RPCClient.shared.config
        _host = State(initialValue: config.host)
        _port = State(initialValue: String(config.port))
        _token = State(initialValue: config.secretToken)
    }

    var body: some View {
        Form {
            Section {
                TextField("localhost", text: $host)
                    .onChange(of: host) { client.config.host = $0 }

                TextField("6800", text: $port)
                    .onChange(of: port) {
                        client.config.port = Int($0) ?? 6800
                    }

                SecureField("Secret Token", text: $token)
                    .onChange(of: token) { client.config.secretToken = $0 }

                HStack {
                    Button {
                        Task {
                            isTesting = true
                            _ = await client.testConnection()
                            isTesting = false
                        }
                    } label: {
                        if isTesting {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Text("Test Connection")
                        }
                    }
                    .disabled(isTesting)

                    Spacer()

                    HStack(spacing: 4) {
                        Circle()
                            .fill(statusColor)
                            .frame(width: 8, height: 8)
                        Text(statusText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: 400)
    }

    private var statusText: String {
        switch client.status {
        case .disconnected: "Disconnected"
        case .connecting: "Connecting..."
        case .connected: "Connected"
        }
    }

    private var statusColor: Color {
        switch client.status {
        case .disconnected: .gray
        case .connecting: .orange
        case .connected: .green
        }
    }
}

#Preview {
    RPCConfigView()
        .environment(Aria2RPCClient.shared)
        .frame(width: 500, height: 300)
}
