import Foundation

/// Maps a preferred locale (e.g. `en_AR`) onto one the speech model actually supports.
enum LocaleResolver {
    /// Regional variants to prefer when only the language matches.
    private static let preferredRegion: [String: String] = [
        "en": "en-US", "es": "es-ES", "pt": "pt-BR", "fr": "fr-FR", "de": "de-DE",
        "it": "it-IT", "ja": "ja-JP", "zh": "zh-CN", "ko": "ko-KR", "nl": "nl-NL",
    ]

    static func resolve(preferred: Locale, from supported: [Locale]) -> Locale? {
        let wanted = preferred.identifier(.bcp47)
        if let exact = supported.first(where: { $0.identifier(.bcp47) == wanted }) {
            return exact
        }
        guard let language = preferred.language.languageCode?.identifier else { return nil }
        let sameLanguage = supported.filter { $0.language.languageCode?.identifier == language }
        if let fallback = preferredRegion[language],
           let match = sameLanguage.first(where: { $0.identifier(.bcp47) == fallback }) {
            return match
        }
        return sameLanguage.first
    }
}
