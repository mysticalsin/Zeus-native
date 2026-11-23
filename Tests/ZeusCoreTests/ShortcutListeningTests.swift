import Testing
@testable import ZeusCore

@Suite("Shortcut listening")
struct ShortcutListeningTests {
    @Test func theFirstBeginPausesAndASecondBeginDoesNotResume() {
        var listening = ShortcutListening()
        #expect(listening.begin() == [.pauseHotkeys])
        #expect(listening.begin() == [])
        #expect(listening.count == 2)
    }

    @Test func theLastEndResumesAndAnExtraEndStaysIdle() {
        var listening = ShortcutListening()
        _ = listening.begin()
        _ = listening.begin()
        #expect(listening.end() == [])
        #expect(listening.count == 1)
        #expect(listening.end() == [.resumeHotkeys])
        #expect(listening.count == 0)
        #expect(listening.end() == [])
        #expect(listening.count == 0)
    }
}
