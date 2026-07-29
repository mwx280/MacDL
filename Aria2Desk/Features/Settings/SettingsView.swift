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
    @AppStorage("appearance") private var appearance: Appearance = .system

    var body: some View {
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
        }
        .formStyle(.grouped)
        .frame(maxWidth: 400)
    }
}
