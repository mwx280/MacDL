import SwiftUI

struct LocalizedText: View {
    let key: String
    @Environment(LanguageManager.self) var lang

    var body: some View {
        Text(verbatim: lang.localized(key))
    }
}
