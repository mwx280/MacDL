import SwiftUI
import AppKit

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
        .frame(width: 420, height: 180)
    }
}

private struct GeneralPane: View {
    @Environment(LanguageManager.self) var lang
    @AppStorage("appearance") private var appearance: Appearance = .system

    var body: some View {
        VStack(spacing: 16) {
            card {
                prefRow("globe", "Language") {
                    Picker(selection: Bindable(lang).selectedLanguage) {
                        ForEach(Language.allCases, id: \.self) { l in
                            LocalizedText(key: l.displayKey).tag(l)
                        }
                    } label: { }
                    .labelsHidden()
                    .frame(width: 140)
                }
                .id(lang.selectedLanguage)

                divider

                prefRow("circle.lefthalf.filled", "Appearance") {
                    Picker(selection: $appearance) {
                        ForEach(Appearance.allCases, id: \.self) { a in
                            LocalizedText(key: a.displayKey).tag(a)
                        }
                    } label: { }
                    .labelsHidden()
                    .frame(width: 140)
                }
            }
        }
        .padding(20)
    }
}

private struct DownloadPane: View {
    @Environment(Aria2RPCClient.self) var client
    @State private var maxConnections: String
    @State private var maxConcurrent: String

    init() {
        _maxConnections = State(initialValue: String(SettingsStore.shared.maxConnections))
        _maxConcurrent = State(initialValue: String(SettingsStore.shared.maxConcurrentDownloads))
    }

    var body: some View {
        VStack(spacing: 16) {
            card {
                prefRow("number", "Max Connections") {
                    TextField("16", text: $maxConnections)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 72)
                        .multilineTextAlignment(.trailing)
                        .onChange(of: maxConnections) { _, v in
                            SettingsStore.shared.maxConnections = Int(v) ?? 16
                        }
                }

                divider

                prefRow("arrow.down.to.line", "Max Downloads") {
                    TextField("5", text: $maxConcurrent)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 72)
                        .multilineTextAlignment(.trailing)
                        .onChange(of: maxConcurrent) { _, v in
                            SettingsStore.shared.maxConcurrentDownloads = Int(v) ?? 5
                        }
                }
            }

        }
        .padding(20)
    }
}

private func card(@ViewBuilder content: () -> some View) -> some View {
    VStack(spacing: 0) { content() }
        .background(.fill.quaternary)
        .clipShape(RoundedRectangle(cornerRadius: 8))
}

private func prefRow<C: View>(_ icon: String, _ label: String, @ViewBuilder control: () -> C) -> some View {
    HStack(spacing: 10) {
        Image(systemName: icon)
            .font(.body)
            .frame(width: 18)
            .foregroundStyle(.secondary)
        LocalizedText(key: label)
            .font(.body)
        Spacer()
        control()
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 8)
}

private var divider: some View { Divider().padding(.leading, 42) }
