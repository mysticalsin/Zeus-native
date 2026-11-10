import Foundation
import Testing
@testable import ZeusCore

@Suite("W5 dictation and voice fixes")
struct W5DictVoiceTests {
    @Test func openAIRequestSendsTheChosenLanguage() {
        let request = OpenAITranscription.request(wav: Data([0]), apiKey: "k", prompt: "", keywords: [], language: "fr-FR", boundary: "b")
        let body = String(decoding: request.httpBody ?? Data(), as: UTF8.self)
        #expect(body.contains("name=\"languages[]\"\r\n\r\nfr\r\n"))
    }

    @Test func openAIRequestOmitsLanguageForAutomatic() {
        let request = OpenAITranscription.request(wav: Data([0]), apiKey: "k", prompt: "", keywords: [], language: nil, boundary: "b")
        let body = String(decoding: request.httpBody ?? Data(), as: UTF8.self)
        #expect(!body.contains("name=\"language\""))
    }

    @Test func vocabularyMergeKeepsWordsLearnedSinceLoad() {
        let loaded = Vocabulary(words: ["Zeus"], replacements: [])
        let current = Vocabulary(words: ["Zeus", "Murmure"], replacements: [Replacement(original: "jev", with: "Jev")])
        let edited = Vocabulary(words: ["Zeus", "Laya"], replacements: [])
        let merged = VocabularyMerge.merged(edited: edited, loaded: loaded, current: current)
        #expect(merged.words == ["Zeus", "Laya", "Murmure"])
        #expect(merged.replacements.map(\.original) == ["jev"])
    }

    @Test func vocabularyMergeHonoursDeletionsMadeInTheEditor() {
        let loaded = Vocabulary(words: ["Zeus", "Old"], replacements: [Replacement(original: "a", with: "b")])
        let edited = Vocabulary(words: ["Zeus"], replacements: [])
        let merged = VocabularyMerge.merged(edited: edited, loaded: loaded, current: loaded)
        #expect(merged.words == ["Zeus"])
        #expect(merged.replacements.isEmpty)
    }

    @Test func vocabularyMergeDoesNotDuplicateAnEditedEntry() {
        let loaded = Vocabulary()
        let current = Vocabulary(words: ["Laya"], replacements: [])
        let edited = Vocabulary(words: ["laya"], replacements: [])
        let merged = VocabularyMerge.merged(edited: edited, loaded: loaded, current: current)
        #expect(merged.words == ["laya"])
    }
}
