import Foundation
import Testing
@testable import ZeusCore

@Suite struct ShortcutTests {
    // Virtual key codes used below.
    static let cmdL: UInt16 = 55, cmdR: UInt16 = 54, optL: UInt16 = 58, shiftL: UInt16 = 56, fnKey: UInt16 = 63
    static let space: UInt16 = 49, z: UInt16 = 6, c: UInt16 = 8

    @Test func encodesAndDecodesEveryKind() {
        for shortcut in [Shortcut.optionCommand, .rightCommand, .rightOption, .controlOption, .function,
                         Shortcut(keyCode: Self.space, modifiers: .option), Shortcut(keyCode: Self.z, modifiers: [.control, .option])] {
            #expect(Shortcut.parse(Shortcut.stored(shortcut)) == shortcut, "\(shortcut.title)")
        }
        #expect(Shortcut.stored(nil) == "off")
        #expect(Shortcut.parse("off") == nil)
        #expect(Shortcut.parse("not json") == nil)
        // A bare letter would hijack typing and is refused on load too.
        #expect(Shortcut.parse(Shortcut.stored(Shortcut(keyCode: Self.z, modifiers: []))) == nil)
    }

    @Test func titlesAreReadable() {
        #expect(Shortcut.optionCommand.title == "Option + Command")
        #expect(Shortcut.rightCommand.title == "Right Command")
        #expect(Shortcut.controlOption.title == "Control + Option")
        #expect(Shortcut.function.title == "Fn (Globe)")
        #expect(Shortcut(keyCode: Self.space, modifiers: .option).title == "⌥ Space")
        #expect(Shortcut(keyCode: Self.z, modifiers: [.control, .option]).symbol == "⌃⌥Z")
        #expect(Shortcut.rightCommand.symbol == "right ⌘")
    }

    private func defaults() -> UserDefaults {
        let suite = "zeus.shortcuts.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        return d
    }

    @Test func freshInstallDefaults() {
        let d = defaults()
        #expect(ShortcutStore.loadTalk(d) == .optionCommand)
        #expect(ShortcutStore.loadDictation(d) == .rightCommand)
    }

    @Test func shippedDefaultKeysNeverShowOverlapWarning() {
        let d = defaults()
        let talk = ShortcutStore.loadTalk(d)
        let dictation = ShortcutStore.loadDictation(d)
        #expect(ShortcutConflicts.warningsForShippedDefaults(talk: talk, dictation: dictation).isEmpty)
        #expect(ShortcutConflicts.warnings(for: dictation!, other: talk, otherName: "Talk to Zeus").isEmpty)
    }

    @Test func oldSavedKeysMigrate() {
        // Tony's earlier build forced Right Command for talk and dictation: talk moves to Option+Command, dictation keeps it.
        let forced = defaults()
        forced.set("rightCommand", forKey: "pushToTalk")
        forced.set("rightCommand", forKey: "dictation.key")
        #expect(ShortcutStore.loadTalk(forced) == .optionCommand)
        #expect(ShortcutStore.loadDictation(forced) == .rightCommand)
        // A deliberate other choice survives, and dictation "off" stays off.
        let chosen = defaults()
        chosen.set("function", forKey: "pushToTalk")
        chosen.set("off", forKey: "dictation.key")
        #expect(ShortcutStore.loadTalk(chosen) == .function)
        #expect(ShortcutStore.loadDictation(chosen) == nil)
        // The migrated value is saved, so a second load agrees and never re-migrates.
        #expect(ShortcutStore.loadTalk(chosen) == .function)
        chosen.set("rightOption", forKey: "pushToTalk")
        #expect(ShortcutStore.loadTalk(chosen) == .function)
    }

    @Test func recordedChoiceBeatsLegacy() {
        let d = defaults()
        d.set("rightOption", forKey: "pushToTalk")
        d.set(Shortcut.stored(Shortcut(keyCode: Self.space, modifiers: .option)), forKey: ShortcutStore.talkKey)
        #expect(ShortcutStore.loadTalk(d) == Shortcut(keyCode: Self.space, modifiers: .option))
    }

    // MARK: Held detection from a fake event stream

    private func held(_ events: [ShortcutEvent], _ shortcut: Shortcut, exact: Bool = true) -> Bool {
        var state = ShortcutState()
        events.forEach { state.apply($0) }
        return state.isHeld(shortcut, exact: exact)
    }

    @Test func optionCommandChord() {
        let option = ShortcutEvent.flags(keyCode: Self.optL, modifiers: .option)
        let both = ShortcutEvent.flags(keyCode: Self.cmdL, modifiers: [.option, .command])
        #expect(!held([option], .optionCommand))
        #expect(held([option, both], .optionCommand))
        // One key released: no longer held.
        #expect(!held([option, both, .flags(keyCode: Self.optL, modifiers: .command)], .optionCommand))
        // Extra Shift: not the chord (exact), but fine for the shared key (loose).
        let shift = ShortcutEvent.flags(keyCode: Self.shiftL, modifiers: [.option, .command, .shift])
        #expect(!held([option, both, shift], .optionCommand))
        #expect(held([option, both, shift], .optionCommand, exact: false))
    }

    @Test func aKeyPressedDuringTheChordSpoilsIt() {
        let events: [ShortcutEvent] = [.flags(keyCode: Self.optL, modifiers: .option),
                                       .flags(keyCode: Self.cmdL, modifiers: [.option, .command]),
                                       .keyDown(keyCode: Self.c, modifiers: [.option, .command]), .keyUp(keyCode: Self.c)]
        #expect(!held(events, .optionCommand))
        // Command first, C, then Option joins: still not a chord press.
        let late: [ShortcutEvent] = [.flags(keyCode: Self.cmdL, modifiers: .command),
                                     .keyDown(keyCode: Self.c, modifiers: .command), .keyUp(keyCode: Self.c),
                                     .flags(keyCode: Self.optL, modifiers: [.command, .option])]
        #expect(!held(late, .optionCommand))
        // After everything is released, the chord works again.
        let again = late + [.flags(keyCode: Self.optL, modifiers: .command), .flags(keyCode: Self.cmdL, modifiers: []),
                            .flags(keyCode: Self.optL, modifiers: .option), .flags(keyCode: Self.cmdL, modifiers: [.option, .command])]
        #expect(held(again, .optionCommand))
    }

    @Test func rightCommandIsNotLeftCommand() {
        let left = ShortcutEvent.flags(keyCode: Self.cmdL, modifiers: .command)
        let right = ShortcutEvent.flags(keyCode: Self.cmdR, modifiers: .command)
        #expect(!held([left], .rightCommand))
        #expect(held([right], .rightCommand))
        // Both down, then the right one lets go: the left Command alone is not "Right Command".
        let both = ShortcutEvent.flags(keyCode: Self.cmdR, modifiers: .command)
        #expect(!held([left, both, .flags(keyCode: Self.cmdR, modifiers: .command)], .rightCommand))
        #expect(held([left], Shortcut(modifiers: .command)))
    }

    // Regression (QA7 P0 item J, real E2E, `tools/e2e-once.sh`): a repeated flagsChanged for a
    // key that's still down (the physical hold is a level, not an edge -- some real and
    // synthetic sources, e.g. CGEventPost, repeat it) used to *toggle* `deviceKeys`, so the
    // second "still down" notification read as a release and silently dropped every other
    // hold-to-dictate key press in a fast back-to-back sequence.
    @Test func repeatedFlagsChangedWhileHeldDoesNotReadAsARelease() {
        let down = ShortcutEvent.flags(keyCode: Self.cmdR, modifiers: .command)
        #expect(held([down, down], .rightCommand), "a duplicate 'still down' notification must not clear the hold")
        #expect(held([down, down, down], .rightCommand))
        let up = ShortcutEvent.flags(keyCode: Self.cmdR, modifiers: [])
        #expect(!held([down, down, up], .rightCommand), "release still clears it")
        // A second genuine down-up-down-up cycle right after must still be seen.
        #expect(held([down, down, up, down], .rightCommand))
    }

    // Regression (QA7 P0 item J, real E2E): an unrelated Command+key shortcut elsewhere on the
    // Mac (even one Zeus's own auto-insert paste sends right after a dictation turn) must not
    // "spoil" a later, unrelated bare-modifier hold -- only a key pressed while *our* tracked
    // modifier(s) are genuinely down (via a real flagsChanged) should.
    @Test func anUnrelatedCommandShortcutElsewhereDoesNotSpoilALaterBareModifierHold() {
        let pasteVKeyDown = ShortcutEvent.keyDown(keyCode: 9, modifiers: .command) // Cmd+V, no flagsChanged for Command ever seen
        let pasteVKeyUp = ShortcutEvent.keyUp(keyCode: 9)
        let rightCommandDown = ShortcutEvent.flags(keyCode: Self.cmdR, modifiers: .command)
        #expect(held([pasteVKeyDown, pasteVKeyUp, rightCommandDown], .rightCommand),
                "a keyDown whose own modifiers field carries Command, with none of our device keys down, must not block the next real hold")
    }

    @Test func fnAloneAndKeyedShortcuts() {
        #expect(held([.flags(keyCode: Self.fnKey, modifiers: .function)], .function))
        let optionSpace = Shortcut(keyCode: Self.space, modifiers: .option)
        let opt = ShortcutEvent.flags(keyCode: Self.optL, modifiers: .option)
        #expect(held([opt, .keyDown(keyCode: Self.space, modifiers: .option)], optionSpace))
        #expect(!held([opt, .keyDown(keyCode: Self.space, modifiers: .option), .keyUp(keyCode: Self.space)], optionSpace))
        // Without Option it is a plain space.
        #expect(!held([.keyDown(keyCode: Self.space, modifiers: [])], optionSpace))
        // Extra Command: a different shortcut.
        #expect(!held([.keyDown(keyCode: Self.space, modifiers: [.option, .command])], optionSpace))
        // Arrow and F keys carry fn on their own; that must not break ⌃⌥ + arrow.
        let ctrlOptRight = Shortcut(keyCode: 124, modifiers: [.control, .option])
        #expect(held([.keyDown(keyCode: 124, modifiers: [.control, .option, .function])], ctrlOptRight))
    }

    // MARK: Hold versus double-tap: monitor logic against a fake clock

    /// What HotkeyMonitor does for the talk binding: held-state edges drive TalkKeyLatch.
    private struct Rig {
        var state = ShortcutState()
        var latch = TalkKeyLatch()
        var down = false
        var actions: [TalkKeyLatch.Action] = []
        let shortcut: Shortcut
        mutating func feed(_ event: ShortcutEvent, at t: TimeInterval) {
            state.apply(event)
            let pressed = state.isHeld(shortcut)
            if pressed, !down { down = true; if let a = latch.keyDown(at: t) { actions.append(a) } }
            else if !pressed, down { down = false; if let a = latch.keyUp(at: t) { actions.append(a) } }
        }
        mutating func chord(down t: TimeInterval) {
            feed(.flags(keyCode: ShortcutTests.optL, modifiers: .option), at: t)
            feed(.flags(keyCode: ShortcutTests.cmdL, modifiers: [.option, .command]), at: t)
        }
        mutating func release(at t: TimeInterval) {
            feed(.flags(keyCode: ShortcutTests.cmdL, modifiers: .option), at: t)
            feed(.flags(keyCode: ShortcutTests.optL, modifiers: []), at: t)
        }
    }

    @Test func holdToTalkStartsAndStops() {
        var rig = Rig(shortcut: .optionCommand)
        rig.chord(down: 0)
        rig.release(at: 1.2)
        #expect(rig.actions == [.start, .stop])
    }

    @Test func doubleTapLatchesUntilTheNextTap() {
        var rig = Rig(shortcut: .optionCommand)
        rig.chord(down: 0); rig.release(at: 0.1)        // quick tap: stop only after the gap
        rig.chord(down: 0.25); rig.release(at: 0.35)    // second quick tap: latched
        #expect(rig.actions == [.start, .stopLater(0.4), .cancelPendingStop])
        #expect(rig.latch.isLatched)
        rig.chord(down: 4); rig.release(at: 4.1)        // any later tap ends it
        #expect(rig.actions.last == .stop)
        #expect(!rig.latch.isLatched)
    }

    @Test func aSingleTapStopsAfterTheGap() {
        var rig = Rig(shortcut: .optionCommand)
        rig.chord(down: 0); rig.release(at: 0.1)
        #expect(rig.latch.pendingStopFired() == .stop)
    }

    // MARK: Recorder

    private func record(_ events: [ShortcutEvent]) -> ShortcutRecorderState.Output? {
        var recorder = ShortcutRecorderState()
        var result: ShortcutRecorderState.Output?
        for event in events { if let out = recorder.feed(event) { result = out } }
        return result
    }

    @Test func recorderCapturesModifierChordsOnRelease() {
        let out = record([.flags(keyCode: Self.optL, modifiers: .option), .flags(keyCode: Self.cmdL, modifiers: [.option, .command]),
                          .flags(keyCode: Self.cmdL, modifiers: .option), .flags(keyCode: Self.optL, modifiers: [])])
        #expect(out == .captured(.optionCommand))
        #expect(record([.flags(keyCode: Self.optL, modifiers: .option)]) == nil) // still held
    }

    @Test func recorderKnowsRightCommandAndFn() {
        #expect(record([.flags(keyCode: Self.cmdR, modifiers: .command), .flags(keyCode: Self.cmdR, modifiers: [])]) == .captured(.rightCommand))
        #expect(record([.flags(keyCode: Self.cmdL, modifiers: .command), .flags(keyCode: Self.cmdL, modifiers: [])])
                == .captured(Shortcut(modifiers: .command, side: .left)))
        #expect(record([.flags(keyCode: Self.fnKey, modifiers: .function), .flags(keyCode: Self.fnKey, modifiers: [])]) == .captured(.function))
        let controlOption = record([.flags(keyCode: 59, modifiers: .control), .flags(keyCode: Self.optL, modifiers: [.control, .option]),
                                    .flags(keyCode: Self.optL, modifiers: .control), .flags(keyCode: 59, modifiers: [])])
        #expect(controlOption == .captured(.controlOption))
    }

    @Test func recorderCapturesKeysWithModifiersImmediately() {
        #expect(record([.flags(keyCode: Self.optL, modifiers: .option), .keyDown(keyCode: Self.space, modifiers: .option)])
                == .captured(Shortcut(keyCode: Self.space, modifiers: .option)))
        #expect(record([.flags(keyCode: 59, modifiers: .control), .flags(keyCode: Self.optL, modifiers: [.control, .option]),
                        .keyDown(keyCode: Self.z, modifiers: [.control, .option])])
                == .captured(Shortcut(keyCode: Self.z, modifiers: [.control, .option])))
        // The key's own Command-held keyDown after a chord is a keyed shortcut, not Option+Command.
        #expect(record([.keyDown(keyCode: 122, modifiers: [.function])]) == .captured(Shortcut(keyCode: 122, modifiers: [])))
    }

    @Test func recorderEscapeCancelsAndBareLettersAreIgnored() {
        #expect(record([.keyDown(keyCode: 53, modifiers: [])]) == .cancelled)
        #expect(record([.keyDown(keyCode: Self.z, modifiers: [])]) == nil)
    }

    // MARK: Conflicts

    @Test func warnsAboutSystemShortcutsAndOverlap() {
        let spotlight = ShortcutConflicts.warnings(for: Shortcut(keyCode: Self.space, modifiers: .command), other: nil, otherName: "")
        #expect(spotlight.contains { $0.contains("Spotlight") })
        #expect(ShortcutConflicts.warnings(for: .optionCommand, other: .rightCommand, otherName: "Dictation").isEmpty)
        let anyCommand = Shortcut(modifiers: .command)
        #expect(ShortcutConflicts.warnings(for: anyCommand, other: .rightCommand, otherName: "Dictation").contains { $0.contains("Overlaps") })
        #expect(ShortcutConflicts.warnings(for: .rightCommand, other: .rightCommand, otherName: "Dictation").contains { $0.contains("double-tap") })
        #expect(ShortcutConflicts.warnings(for: .optionCommand, other: .function, otherName: "Dictation").isEmpty)
        #expect(ShortcutConflicts.warnings(for: .controlOption, other: nil, otherName: "").contains { $0.contains("VoiceOver") })
    }
}

@Suite struct VoiceAccessTests {
    @Test func permissionStatesDecideWhatToDo() {
        #expect(VoiceAccess.decide(mic: .authorized, speech: .authorized) == .ready)
        #expect(VoiceAccess.decide(mic: .notDetermined, speech: .notDetermined) == .needsPrompt)
        #expect(VoiceAccess.decide(mic: .authorized, speech: .notDetermined) == .needsPrompt)
        #expect(VoiceAccess.decide(mic: .denied, speech: .notDetermined) == .denied(mic: true, speech: false))
        #expect(VoiceAccess.decide(mic: .authorized, speech: .denied) == .denied(mic: false, speech: true))
    }

    @Test func promptsOnlyWhenUndecidedAndExpected() {
        let ask = VoiceAccess.needsPrompt
        #expect(ask.shouldPrompt(wakeOn: true, explicit: false))      // launch with Hey Zeus on
        #expect(!ask.shouldPrompt(wakeOn: false, explicit: false))    // launch with it off: stay quiet
        #expect(ask.shouldPrompt(wakeOn: false, explicit: true))      // switch on, talk key, onboarding
        #expect(!VoiceAccess.ready.shouldPrompt(wakeOn: true, explicit: true))
        #expect(!VoiceAccess.denied(mic: true, speech: false).shouldPrompt(wakeOn: true, explicit: true)) // never a second prompt
    }

    @Test func deniedGetsACueAndTheRightPane() {
        let mic = VoiceAccess.denied(mic: true, speech: false)
        #expect(mic.deniedCue == "Zeus can't hear you: allow the microphone")
        #expect(mic.deniedPane == "Privacy_Microphone")
        #expect(VoiceAccess.denied(mic: false, speech: true).deniedPane == "Privacy_SpeechRecognition")
        #expect(VoiceAccess.ready.deniedCue == nil)
    }

    @Test func permissionStateBecomesTheWakeGateDecision() {
        var gate = WakeGate()
        gate.micAllowed = false; gate.speechAllowed = false
        #expect(!gate.mayListen)
        #expect(gate.statusLine(listening: false) == "no permission")
        gate.micAllowed = true; gate.speechAllowed = true
        #expect(gate.mayListen)
        #expect(gate.statusLine(listening: true) == "listening")
        gate.dictating = true
        #expect(gate.statusLine(listening: false) == "paused (dictation)")
        gate.enabled = false
        #expect(gate.statusLine(listening: false) == "off")
        // Other pauses still apply with access granted.
        gate = WakeGate(); gate.micAllowed = true; gate.speechAllowed = true
        gate.speaking = true
        #expect(gate.pauseReason == "Zeus is speaking")
        gate.speaking = false; gate.cooldown = true
        #expect(gate.pauseReason == "just woke")
    }

    @Test func wakePhraseSplitsTheSameBreathCommand() {
        #expect(WakePhrase.spot("Hey Zeus, open Spotify and play jazz")?.request == "open Spotify and play jazz")
        #expect(WakePhrase.spot("hey zeus")?.request == "")
        #expect(WakePhrase.spot("um okay Zeus what time is it")?.request == "what time is it")
        #expect(WakePhrase.spot("heyzeus lock the screen")?.request == "lock the screen")
        #expect(WakePhrase.spot("open Spotify") == nil)
        #expect(WakePhrase.spot("so um hey Zeus's thing")?.skippedWords == 2)
    }

    @Test func speechActivityFindsTheSpokenPart() {
        let rate = 16_000.0
        var samples = [Float](repeating: 0, count: Int(rate))                       // 1 s quiet
        samples += (0..<Int(rate * 1.2)).map { 0.2 * sin(Float($0) * 0.1) }         // 1.2 s of "speech"
        samples += [Float](repeating: 0, count: Int(rate * 2))                      // 2 s quiet
        let segments = VoiceSegments.find(samples: samples, sampleRate: rate)
        #expect(segments.count == 1)
        if let segment = segments.first {
            #expect(segment.start > 0.9 && segment.start < 1.4)
            #expect(segment.end > 2.0 && segment.end < 2.6)
        }
        #expect(VoiceSegments.find(samples: [Float](repeating: 0, count: 32_000), sampleRate: rate).isEmpty)
    }
}
