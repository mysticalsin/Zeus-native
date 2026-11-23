import Testing
@testable import ZeusCore

@Suite("Talk chord registration")
struct TalkChordRegistrationTests {
    private let chord = Shortcut(keyCode: 49, modifiers: [.control, .option])

    @Test func pauseClearsAHeldChord() {
        var registration = TalkChordRegistration()
        #expect(registration.sync(chord, listening: true) == [.register(chord)])
        registration.noteRegistered(true)
        #expect(registration.state == .holding(chord))
        #expect(registration.pause() == [.unregister])
        #expect(registration.state == .clear)
        #expect(registration.sync(chord, listening: true) == [])
        #expect(registration.state == .clear)
        #expect(registration.resume() == [.register(chord)])
    }

    @Test func aRefusalIsRetriedOnTheNextSync() {
        var registration = TalkChordRegistration()
        #expect(registration.sync(chord, listening: true) == [.register(chord)])
        registration.noteRegistered(false)
        #expect(registration.state == .refused(chord))
        #expect(registration.sync(chord, listening: true) == [.register(chord)])
        registration.noteRegistered(true)
        #expect(registration.state == .holding(chord))
        #expect(registration.sync(chord, listening: true) == [])
    }

    @Test func aHeldChordIsIdempotent() {
        var registration = TalkChordRegistration()
        #expect(registration.sync(chord, listening: true) == [.register(chord)])
        registration.noteRegistered(true)
        #expect(registration.sync(chord, listening: true) == [])
        #expect(registration.state == .holding(chord))
    }

    @Test func aSyncThatIsNotListeningWantsNoChord() {
        var registration = TalkChordRegistration()
        #expect(registration.sync(chord, listening: false) == [])
        #expect(registration.state == .clear)
        #expect(registration.sync(chord, listening: true) == [.register(chord)])
        registration.noteRegistered(true)
        #expect(registration.sync(chord, listening: false) == [.unregister])
        #expect(registration.state == .clear)
    }
}
