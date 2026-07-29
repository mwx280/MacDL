import SwiftUI

struct SettingsView: View {
    @Environment(LanguageManager.self) var lang

    var body: some View {
        Form {
            Picker("Language", selection: Bindable(lang).selectedLanguage) {
                ForEach(Language.allCases, id: \.self) { lang in
                    Text(lang.displayName).tag(lang)
                }
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: 400)
    }
}
