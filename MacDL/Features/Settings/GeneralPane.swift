import SwiftUI
import AppKit

struct GeneralPane: View {
    @Environment(LanguageManager.self) var lang
    @AppStorage("appearance") private var appearance: Appearance = .system
    @AppStorage("launchInBackground") private var launchInBackground = true
    @State private var launchAtLogin = LaunchAtLoginService.isEnabled
    @State private var launchAtLoginFailed = false

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
                    .pickerStyle(.menu)
                    .fixedSize()
                    .frame(minWidth: 140, alignment: .trailing)
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
                    .pickerStyle(.menu)
                    .fixedSize()
                    .frame(minWidth: 140, alignment: .trailing)
                }

                divider

                prefRow("power", "Launch at Login") {
                    Toggle("", isOn: Binding(
                        get: { launchAtLogin },
                        set: { newValue in
                            do {
                                try LaunchAtLoginService.setEnabled(newValue)
                                launchAtLogin = newValue
                            } catch {
                                launchAtLoginFailed = true
                            }
                        }
                    ))
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                }

                divider

                prefRow("eye.slash", "Launch in Background") {
                    Toggle("", isOn: $launchInBackground)
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                        .help(LanguageManager.shared.localized("Launch in Background description"))
                }
            }
            .alert(LanguageManager.shared.localized("Launch at Login"), isPresented: $launchAtLoginFailed) {
                Button(LanguageManager.shared.localized("OK"), role: .cancel) { }
            } message: {
                LocalizedText(key: "Launch at Login requires the app to run from the Applications folder.")
            }
        }
        .padding(20)
    }
}
