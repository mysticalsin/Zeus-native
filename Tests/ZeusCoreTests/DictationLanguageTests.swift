import Testing
@testable import ZeusCore

@Suite("Dictation language")
struct DictationLanguageTests {
    @Test func persistedCatalogLabelsResolveToLocales() {
        #expect(DictationLanguage(persistedValue: nil) == .automatic)
        #expect(DictationLanguage(persistedValue: "English (US)") == .englishUS)
        #expect(DictationLanguage(persistedValue: "pt-BR") == .portugueseBrazil)
        #expect(DictationLanguage(persistedValue: "unsupported") == .automatic)
        #expect(DictationLanguage.automatic.localeIdentifier == nil)
        #expect(DictationLanguage.persian.localeIdentifier == "fa-IR")
    }

    @Test func localModelsReceiveLanguageCodes() {
        #expect(DictationLanguage.engineLanguageCode(for: nil) == nil)
        #expect(DictationLanguage.engineLanguageCode(for: "automatic") == nil)
        #expect(DictationLanguage.engineLanguageCode(for: "en-US") == "en")
        #expect(DictationLanguage.engineLanguageCode(for: "pt_BR") == "pt")
        #expect(DictationLanguage.engineLanguageCode(for: "fa-IR") == "fa")
    }
}
