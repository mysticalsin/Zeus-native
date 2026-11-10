import Testing
@testable import ZeusCore

@Suite("Dictation shortcut behavior")
struct DictationBehaviorTests {
    @Test func holdStartsOnPressAndFinishesOnRelease() {
        #expect(DictationBehavior.holdToSpeak.actionOnPress(isDictating: false) == .begin)
        #expect(DictationBehavior.holdToSpeak.finishesOnRelease)
    }

    @Test func toggleStartsOrFinishesOnEachPressAndIgnoresRelease() {
        #expect(DictationBehavior.pressToToggle.actionOnPress(isDictating: false) == .begin)
        #expect(DictationBehavior.pressToToggle.actionOnPress(isDictating: true) == .finish)
        #expect(!DictationBehavior.pressToToggle.finishesOnRelease)
    }

    @Test func sharedTalkKeyOnlyOffersHoldBehavior() {
        #expect(DictationBehavior.choices(sharedWithTalkKey: true) == [.holdToSpeak])
        #expect(DictationBehavior.choices(sharedWithTalkKey: false) == DictationBehavior.allCases)
    }
}
