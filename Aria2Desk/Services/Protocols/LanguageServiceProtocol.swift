protocol LanguageServiceProtocol {
    var selectedLanguage: Language { get set }
    func localized(_ key: String) -> String
}
