import Testing
@testable import ZeusCore

@Suite struct DictationWingTextTests {
    @Test func heardWordsReplaceTheWaveOnlyWhileListening() {
        #expect(DictationWingText.line(listening: false, partial: "hello there") == nil)
        #expect(DictationWingText.line(listening: true, partial: "   ") == nil)
        #expect(DictationWingText.line(listening: true, partial: "hello there") == "hello there")
    }

    @Test func aLongPartialIsCutOnAWord() throws {
        let partial = "this is a long dictation that will not fit on the closed notch wing"
        let line = DictationWingText.line(listening: true, partial: partial)
        let shown = try #require(line)
        #expect(shown.count <= DictationWingText.limit)
        #expect(shown.hasSuffix("…"))
        #expect(partial.hasPrefix(String(shown.dropLast())))
        #expect(!shown.hasSuffix(" …"))
    }
}
