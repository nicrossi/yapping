import Foundation
import Testing
@testable import Yapping

struct LocaleResolverTests {
    private let supported = ["en-US", "en-GB", "es-ES", "es-MX", "de-DE"].map(Locale.init(identifier:))

    @Test func exactMatchWins() {
        let r = LocaleResolver.resolve(preferred: Locale(identifier: "en-GB"), from: supported)
        #expect(r?.identifier(.bcp47) == "en-GB")
    }

    @Test func unsupportedRegionFallsBackToPreferredRegion() {
        let r = LocaleResolver.resolve(preferred: Locale(identifier: "en_AR"), from: supported)
        #expect(r?.identifier(.bcp47) == "en-US")
    }

    @Test func spanishArgentinaFallsBackToSpanish() {
        let r = LocaleResolver.resolve(preferred: Locale(identifier: "es_AR"), from: supported)
        #expect(r?.identifier(.bcp47) == "es-ES")
    }

    @Test func languageWithoutPreferredRegionTakesFirstMatch() {
        let r = LocaleResolver.resolve(preferred: Locale(identifier: "de_AT"), from: supported)
        #expect(r?.identifier(.bcp47) == "de-DE")
    }

    @Test func unknownLanguageReturnsNil() {
        #expect(LocaleResolver.resolve(preferred: Locale(identifier: "xh_ZA"), from: supported) == nil)
    }
}
