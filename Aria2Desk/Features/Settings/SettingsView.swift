import SwiftUI

struct SettingsView: View {
    @Environment(LanguageManager.self) var lang

    var body: some View {
        Form {
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
        .formStyle(.grouped)
        .frame(maxWidth: 400)
    }
}
