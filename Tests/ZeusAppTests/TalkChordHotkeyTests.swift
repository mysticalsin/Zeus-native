import Carbon.HIToolbox
import Foundation
import Testing
import ZeusCore
@testable import Zeus

/// The Carbon hot key behind the talk chord (docs/ULTRON-CHORD-PLAN.md): registered once while the chord is active, let go
/// of when it is not or while a recorder listens, and its handler answers only its own signature.
@Suite("Talk chord hot key", .serialized) @MainActor
struct TalkChordHotkeyTests {
    private final class Log {
        var registered: [(UInt32, UInt32)] = []
        var unregistered = 0
        var succeed = true
    }

    private func make(_ log: Log) -> TalkChordHotkey {
        TalkChordHotkey(registrar: .init(register: { code, mods in log.registered.append((code, mods)); return log.succeed },
                                         unregister: { log.unregistered += 1 }))
    }

    @Test func itRegistersOnceForTheChordAndLetsGoWhenItIsNil() {
        let log = Log()
        let hotkey = make(log)
        hotkey.sync(VoiceKey.talkChord)
        hotkey.sync(VoiceKey.talkChord)
        #expect(log.registered.count == 1 && hotkey.isRegistered && hotkey.problem == nil)
        #expect(log.registered.first?.0 == UInt32(kVK_Space))
        #expect(log.registered.first?.1 == UInt32(controlKey | optionKey))
        hotkey.sync(nil)
        hotkey.sync(nil)
        #expect(log.unregistered == 1 && !hotkey.isRegistered)
        hotkey.sync(VoiceKey.talkChord)
        #expect(log.registered.count == 2, "a chord that comes back registers again")
    }

    @Test func aRecorderPausesItAndResumeTakesItBack() {
        let log = Log()
        let hotkey = make(log)
        hotkey.sync(VoiceKey.talkChord)
        hotkey.setPaused(true)
        #expect(log.unregistered == 1 && !hotkey.isRegistered)
        hotkey.sync(VoiceKey.talkChord)
        #expect(log.registered.count == 1, "nothing registers while a recorder listens")
        hotkey.setPaused(false)
        #expect(log.registered.count == 2 && hotkey.isRegistered, "the chord is back once it stops")
        hotkey.setPaused(false)
        #expect(log.registered.count == 2)
    }

    @Test func aFailedRegistrationIsSaidInPlainWords() {
        let log = Log()
        log.succeed = false
        let hotkey = make(log)
        hotkey.sync(VoiceKey.talkChord)
        #expect(hotkey.problem == "Another app uses Control-Option-Space. Hold Control + Option alone to talk.")
        #expect(!hotkey.isRegistered)
        hotkey.sync(nil)
        #expect(hotkey.problem == nil)
    }

    @Test func aRefusedRegistrationIsAskedAgainOnTheNextSync() {
        let log = Log()
        log.succeed = false
        let hotkey = make(log)
        hotkey.sync(VoiceKey.talkChord)
        #expect(!hotkey.isRegistered && hotkey.problem != nil)
        log.succeed = true // the other holder let go
        hotkey.sync(VoiceKey.talkChord)
        #expect(log.registered.count == 2 && hotkey.isRegistered && hotkey.problem == nil, "a chord that was refused once takes the key when it frees")
        hotkey.sync(VoiceKey.talkChord)
        #expect(log.registered.count == 2, "a registered chord is not asked again")
    }

    @Test func itTakesTheKeyOnlyWhileTheTalkMonitorCanHearKeys() {
        let log = Log()
        let hotkey = make(log)
        hotkey.sync(VoiceKey.talkChord, listening: false)
        #expect(log.registered.isEmpty && !hotkey.isRegistered && hotkey.problem == nil,
                "with no Input Monitoring a taken Space would be lost and nothing would talk")
        hotkey.sync(VoiceKey.talkChord, listening: true)
        #expect(log.registered.count == 1 && hotkey.isRegistered, "access came: the chord takes the key")
        hotkey.sync(VoiceKey.talkChord, listening: false)
        #expect(log.unregistered == 1 && !hotkey.isRegistered, "access went: the key is given back")
    }

    @Test func itsHandlerAnswersOnlyItsOwnSignature() {
        #expect(TalkChordHotkey.answers(signature: CarbonHotkeySignature.talkChord.rawValue))
        #expect(!TalkChordHotkey.answers(signature: CarbonHotkeySignature.chat.rawValue))
        #expect(!TalkChordHotkey.answers(signature: CarbonHotkeySignature.center.rawValue))
        #expect(!TalkChordHotkey.answers(signature: 0))
    }
}
