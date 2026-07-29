import SwiftUI
import Observation

enum Language: String, CaseIterable {
    case system = ""
    case en = "en"
    case zh = "zh-Hans"

    var displayKey: String {
        switch self {
        case .system: "Follow System"
        case .en: "English"
        case .zh: "中文"
        }
    }
}

@Observable
final class LanguageManager {
    static let shared = LanguageManager()

    var selectedLanguage: Language {
        didSet {
            UserDefaults.standard.set(selectedLanguage.rawValue, forKey: "appLanguage")
        }
    }

    private init() {
        let raw = UserDefaults.standard.string(forKey: "appLanguage") ?? ""
        selectedLanguage = Language(rawValue: raw) ?? .system
    }

    var bundle: Bundle {
        let code: String
        switch selectedLanguage {
        case .system:
            let preferred = Locale.preferredLanguages.first ?? "en"
            code = preferred.hasPrefix("zh") ? "zh-Hans" : "en"
        case .en: code = "en"
        case .zh: code = "zh-Hans"
        }
        if let path = Bundle.main.path(forResource: code, ofType: "lproj"),
           let b = Bundle(path: path) { return b }
        return .main
    }

    func localized(_ key: String) -> String {
        bundle.localizedString(forKey: key, value: key, table: nil)
    }
}
