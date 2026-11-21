import Testing
import ZeusCore

@Suite("Dictate control press")
struct DictationPressTests {
    @Test func aPressWhileTypingCancelsDictation() {
        #expect(DictationPress.action(for: .transcribing) == .cancel)
        #expect(DictationPress.action(for: .rewriting) == .cancel)
        #expect(DictationPress.action(for: .listening) == .finish)
        #expect(DictationPress.action(for: .idle) == .begin)
        #expect(DictationPress.action(for: .done) == .begin)
        #expect(DictationPress.action(for: .failed("no")) == .begin)
    }

    @Test func typingPhaseLabelMatchesTheVisibleTitle() {
        for phase in [DictationPhase.transcribing, .rewriting] {
            let copy = DictationPress.label(for: phase, holding: false)
            #expect(copy.title == "Typing")
            #expect(copy.accessibilityLabel == copy.title)
            #expect(copy.help == "Cancel typing")
        }
    }

    @Test func listeningAndIdleCopyStayTheWordsTheButtonAlreadyDraws() {
        let listening = DictationPress.label(for: .listening, holding: false)
        #expect(listening.title == "Stop")
        #expect(listening.accessibilityLabel == "Stop dictation")
        #expect(listening.help == "Stop and type it")
        #expect(DictationPress.label(for: .listening, holding: true).title == "Release")
        let idle = DictationPress.label(for: .idle, holding: false)
        #expect(idle.title == "Dictate")
        #expect(idle.accessibilityLabel == "Start dictation")
        #expect(idle.help == "Dictate into the app you're in")
        #expect(DictationPress.label(for: .done, holding: true).title == "Dictate")
    }
}
