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
    var body: some View {
        TabView {
            GeneralPane()
                .tabItem {
                    Label(title: { LocalizedText(key: "General") }, icon: { Image(systemName: "gear") })
                }

            DownloadPane()
                .tabItem {
                    Label(title: { LocalizedText(key: "Download") }, icon: { Image(systemName: "arrow.down.circle") })
                }
        }
        .fixedSize()
    }
}

private struct GeneralPane: View {
    @Environment(LanguageManager.self) var lang
    @AppStorage("appearance") private var appearance: Appearance = .system

    var body: some View {
        VStack(spacing: 0) {
            Form {
                HStack {
                    LocalizedText(key: "Language")
                    Spacer()
                    Picker(selection: Bindable(lang).selectedLanguage) {
                        ForEach(Language.allCases, id: \.self) { l in
                            LocalizedText(key: l.displayKey).tag(l)
                        }
                    } label: { }
                    .labelsHidden()
                    .frame(width: 120)
                }
                .id(lang.selectedLanguage)

                HStack {
                    LocalizedText(key: "Appearance")
                    Spacer()
                    Picker(selection: $appearance) {
                        ForEach(Appearance.allCases, id: \.self) { a in
                            LocalizedText(key: a.displayKey).tag(a)
                        }
                    } label: { }
                    .labelsHidden()
                    .frame(width: 120)
                }
            }
        }
        .padding(20)
        .frame(width: 400, height: 180)
    }
}

private struct DownloadPane: View {
    @Environment(Aria2RPCClient.self) var client
    @State private var maxConnections: String
    @State private var maxConcurrent: String

    init() {
        let config = Aria2RPCClient.shared.config
        _maxConnections = State(initialValue: String(config.maxConnections))
        _maxConcurrent = State(initialValue: String(config.maxConcurrentDownloads))
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                HStack {
                    LocalizedText(key: "Max Connections")
                    Spacer()
                    TextField("16", text: $maxConnections)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 72)
                        .multilineTextAlignment(.trailing)
                        .onChange(of: maxConnections) { _, v in
                            client.config.maxConnections = Int(v) ?? 16
                        }
                }

                HStack {
                    LocalizedText(key: "Max Downloads")
                    Spacer()
                    TextField("5", text: $maxConcurrent)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 72)
                        .multilineTextAlignment(.trailing)
                        .onChange(of: maxConcurrent) { _, v in
                            client.config.maxConcurrentDownloads = Int(v) ?? 5
                        }
                }
            }

            Spacer()

            LocalizedText(key: "Changes require engine restart.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
        }
        .padding(.top, 20)
        .frame(width: 400, height: 160)
    }
}
