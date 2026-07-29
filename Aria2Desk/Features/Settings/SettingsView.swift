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

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent {
                        Picker(selection: Bindable(lang).selectedLanguage) {
                            ForEach(Language.allCases, id: \.self) { lang in
                                Text(lang.displayName).tag(lang)
                            }
                        } label: { }
                    } label: {
                        Label("Language", systemImage: "globe")
                    }
                }

                Section {
                    LabeledContent {
                        Picker(selection: $appearance) {
                            ForEach(Appearance.allCases, id: \.self) { a in
                                Text(a.displayName).tag(a)
                            }
                        } label: { }
                    } label: {
                        Label("Appearance", systemImage: "circle.lefthalf.filled")
                    }
                }

                Section {
                    NavigationLink {
                        RPCConfigView()
                    } label: {
                        HStack {
                            Label("RPC Connection", systemImage: "terminal")
                            Spacer()
                            Circle()
                                .fill(connectionColor)
                                .frame(width: 8, height: 8)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .frame(maxWidth: 400)
        }
    }

    private var connectionColor: Color {
        switch client.status {
        case .disconnected: .gray
        case .connecting: .orange
        case .connected: .green
        }
    }
}
