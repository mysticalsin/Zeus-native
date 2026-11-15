import CoreGraphics
import Foundation
import Testing
@testable import ZeusCore

/// Control+Option is the Zeus voice key (docs/VOICE-KEY.md): default, one-time migration, one owner per hold.
@Suite("Voice key")
struct VoiceKeyTests {
    private func defaults() -> UserDefaults {
        let suite = "zeus.voicekey.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        return d
    }

    // MARK: Default and migration

    @Test func aFreshInstallTalksOnControlOption() {
        let d = defaults()
        let talk = ShortcutStore.loadTalk(d)
        #expect(talk == .controlOption)
        #expect(d.string(forKey: ShortcutStore.talkKey) == Shortcut.stored(.controlOption))
        #expect(d.bool(forKey: ShortcutStore.talkMigrationKey))
        #expect(!d.bool(forKey: ShortcutStore.talkChosenKey))
    }

    @Test func anAutoWrittenOptionCommandMovesToControlOption() {
        let d = defaults()
        d.set(Shortcut.stored(.optionCommand), forKey: ShortcutStore.talkKey)
        let talk = ShortcutStore.loadTalk(d)
        #expect(talk == .controlOption)
        #expect(d.string(forKey: ShortcutStore.talkKey) == Shortcut.stored(.controlOption))
    }

    @Test func anAutoWrittenRightCommandMovesToControlOption() {
        let d = defaults()
        d.set(Shortcut.stored(.rightCommand), forKey: ShortcutStore.talkKey)
        let talk = ShortcutStore.loadTalk(d)
        #expect(talk == .controlOption)
    }

    @Test func legacyFixedNamesMigrate() {
        for (name, expected) in [("rightCommand", Shortcut.controlOption), ("controlOption", .controlOption),
                                 ("rightOption", .rightOption), ("function", .function)] {
            let d = defaults()
            d.set(name, forKey: ShortcutStore.legacyTalk)
            let talk = ShortcutStore.loadTalk(d)
            #expect(talk == expected, "\(name)")
            let chosen = d.bool(forKey: ShortcutStore.talkChosenKey)
            #expect(chosen == (expected != .controlOption), "\(name)")
        }
    }

    @Test func anExplicitChoiceIsKept() {
        let d = defaults()
        ShortcutStore.recordTalkChoice(.optionCommand, in: d)
        let talk = ShortcutStore.loadTalk(d)
        #expect(talk == .optionCommand)
        let other = defaults()
        ShortcutStore.recordTalkChoice(.rightCommand, in: other)
        let otherTalk = ShortcutStore.loadTalk(other)
        #expect(otherTalk == .rightCommand)
    }

    @Test func aRecordedNonDefaultKeyIsKeptWithoutTheFlagToo() {
        let d = defaults()
        let space = Shortcut(keyCode: 49, modifiers: .option)
        d.set(Shortcut.stored(space), forKey: ShortcutStore.talkKey)
        let talk = ShortcutStore.loadTalk(d)
        #expect(talk == space)
    }

    @Test func theMigrationRunsOnce() {
        let d = defaults()
        d.set(Shortcut.stored(.optionCommand), forKey: ShortcutStore.talkKey)
        let first = ShortcutStore.loadTalk(d)
        #expect(first == .controlOption)
        // Later, Option+Command is written again (an older build, an import): it is not moved a second time.
        d.set(Shortcut.stored(.optionCommand), forKey: ShortcutStore.talkKey)
        let second = ShortcutStore.loadTalk(d)
        #expect(second == .optionCommand)
    }

    // MARK: One owner per hold

    private func owner(_ chord: Shortcut, talk: Shortcut = .controlOption, dictation: Shortcut? = .rightCommand,
                       pointing: Shortcut = .controlOption, pointingOn: Bool = true, voiceOver: Bool = false,
                       screen: Bool = true) -> VoiceKey.Owner? {
        VoiceKey.owner(ofHold: chord, talk: talk, dictation: dictation, pointing: pointing,
                       pointingEnabled: pointingOn, voiceOverOn: voiceOver, screenRecording: screen)
    }

    @Test func talkEqualToPointingIsOneScreenAwareTalkTurn() {
        #expect(owner(.controlOption) == .talk(screenAware: true))
        #expect(!VoiceKey.pointingStartsTurns(talk: .controlOption, pointing: .controlOption, pointingEnabled: true))
    }

    @Test func withPointingOffTheHoldIsATalkTurn() {
        #expect(owner(.controlOption, pointingOn: false) == .talk(screenAware: true))
        #expect(!VoiceKey.pointingStartsTurns(talk: .optionCommand, pointing: .controlOption, pointingEnabled: false))
    }

    @Test func withoutScreenRecordingItIsAPlainTalkTurn() {
        #expect(owner(.controlOption, screen: false) == .talk(screenAware: false))
    }

    @Test func aSeparatePointingKeyKeepsItsOwnTurn() {
        #expect(owner(.rightOption, pointing: .rightOption) == .pointing)
        #expect(owner(.controlOption, pointing: .rightOption) == .talk(screenAware: true))
        #expect(owner(.controlOption, talk: .optionCommand) == .pointing)
        #expect(owner(.optionCommand, talk: .optionCommand) == .talk(screenAware: true))
    }

    @Test func voiceOverKeepsControlOptionAndTalkMovesToAFallback() {
        #expect(owner(.controlOption, voiceOver: true) == nil)
        #expect(owner(.optionCommand, voiceOver: true) == .talk(screenAware: true))
        #expect(VoiceKey.effectiveTalkKey(chosen: .controlOption, dictation: .rightCommand, pointing: nil, voiceOverOn: false) == .controlOption)
        #expect(VoiceKey.effectiveTalkKey(chosen: .controlOption, dictation: .optionCommand, pointing: nil, voiceOverOn: true) == .rightOption)
        #expect(VoiceKey.effectiveTalkKey(chosen: .function, dictation: nil, pointing: nil, voiceOverOn: true) == .function)
        // A separate Control+Option pointing key pauses too while VoiceOver runs.
        #expect(owner(.controlOption, talk: .optionCommand, voiceOver: true) == nil)
    }

    @Test func everyHoldHasAtMostOneOwner() {
        let keys: [Shortcut] = [.controlOption, .optionCommand, .rightOption, .function, .rightCommand]
        for talk in keys {
            for pointing in [Shortcut.controlOption, .rightOption, .function] {
                for pointingOn in [true, false] {
                    for voiceOver in [true, false] {
                        let starts = VoiceKey.pointingStartsTurns(talk: talk, pointing: pointing, pointingEnabled: pointingOn)
                        // Pointing never starts a turn on the talk key, so the two monitors never both answer a hold.
                        #expect(!(starts && pointing == talk))
                        let listened = VoiceKey.effectiveTalkKey(chosen: talk, dictation: .rightCommand,
                                                                 pointing: pointingOn ? pointing : nil, voiceOverOn: voiceOver)
                        #expect(!(starts && listened == pointing), "talk \(talk.title) pointing \(pointing.title)")
                    }
                }
            }
        }
    }

    // MARK: Conflicts and pointer context

    @Test func theShippedVoiceKeysDoNotWarn() {
        let d = defaults()
        let talk = ShortcutStore.loadTalk(d)
        let dictation = ShortcutStore.loadDictation(d)
        #expect(ShortcutConflicts.warnings(for: talk, other: dictation, otherName: "Dictation").isEmpty)
        #expect(ShortcutConflicts.pointingWarnings(pointing: .controlOption, talk: talk, dictation: dictation,
                                                   chat: .off, doubleControlTextEntry: false).isEmpty)
        // A real conflict still warns: dictation on the talk key.
        #expect(!ShortcutConflicts.warnings(for: talk, other: .controlOption, otherName: "Dictation").isEmpty)
        let voiceOver = ShortcutConflicts.warnings(for: .controlOption, other: nil, otherName: "", voiceOverOn: true,
                                                   voiceOverFallback: .optionCommand)
        #expect(voiceOver.contains { $0.contains("Option + Command") })
    }

    @Test func theCursorIsGivenInScreenshotPixels() {
        let frame = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let top = ScreenAwareness.cursorPixel(CGPoint(x: 720, y: 900), frame: frame, width: 1280, height: 800)
        #expect(top == CGPoint(x: 640, y: 0))
        let second = CGRect(x: 1440, y: -100, width: 1000, height: 1000)
        let corner = ScreenAwareness.cursorPixel(CGPoint(x: 1440, y: -100), frame: second, width: 1000, height: 1000)
        #expect(corner == CGPoint(x: 0, y: 1000))
    }

    // MARK: The Control-Option-Space chord (docs/ULTRON-CHORD-PLAN.md)

    private typealias Holder = (name: String, shortcut: Shortcut?)
    private let chordSpace = Shortcut(keyCode: 49, modifiers: [.control, .option])

    @Test func theChordIsOnlyOnTheBareControlOptionTalkKey() {
        let free = VoiceKey.talkChord(heard: .controlOption, shared: false, voiceOverOn: false, holders: [])
        #expect(free.chord == chordSpace && free.chord == VoiceKey.talkChord && free.heldBy == nil)
        // Only the bare Control-Option pair, as heard.
        for heard in [Shortcut.function, .rightOption, .optionCommand, .rightCommand, chordSpace,
                      Shortcut(keyCode: 8, modifiers: [.control, .option])] {
            let result = VoiceKey.talkChord(heard: heard, shared: false, voiceOverOn: false, holders: [])
            #expect(result.chord == nil && result.heldBy == nil, "\(heard.symbol) has no chord")
        }
        // Not shared with dictation, and not with VoiceOver on (Control-Option-Space is VoiceOver's own key).
        #expect(VoiceKey.talkChord(heard: .controlOption, shared: true, voiceOverOn: false, holders: []).chord == nil)
        #expect(VoiceKey.talkChord(heard: .controlOption, shared: false, voiceOverOn: true, holders: []).chord == nil)
        // A Carbon shortcut that holds Control-Option-Space keeps it, and is named.
        for name in ["Chat", "Agent picker", "Quick to-do"] {
            let held: [Holder] = [("Another", Shortcut(keyCode: 8, modifiers: [.control, .option])), (name, chordSpace)]
            let result = VoiceKey.talkChord(heard: .controlOption, shared: false, voiceOverOn: false, holders: held)
            #expect(result.chord == nil && result.heldBy == name, "\(name) holds the chord")
        }
        let off: [Holder] = [("Chat", nil), ("Agent picker", Shortcut(keyCode: 8, modifiers: [.control, .option]))]
        #expect(VoiceKey.talkChord(heard: .controlOption, shared: false, voiceOverOn: false, holders: off).chord == chordSpace)
    }

    @Test func theChordYieldsToAnExplicitChatChoice() {
        func chat(_ raw: String?) -> [Holder] { [("Chat", ChatHotkey.stored(raw).shortcut)] }
        let fresh = VoiceKey.talkChord(heard: .controlOption, shared: false, voiceOverOn: false, holders: chat(nil))
        #expect(fresh.chord == chordSpace, "a fresh install puts Chat on Control-Option-C, so the chord is free")
        let kept = VoiceKey.talkChord(heard: .controlOption, shared: false, voiceOverOn: false, holders: chat("controlOptionSpace"))
        #expect(kept.chord == nil && kept.heldBy == "Chat", "an explicit stored Control-Option-Space is kept, and Chat wins")
        let other = VoiceKey.talkChord(heard: .controlOption, shared: false, voiceOverOn: false, holders: chat("optionSpace"))
        #expect(other.chord == chordSpace)
        #expect(VoiceKey.talkChord(heard: .controlOption, shared: false, voiceOverOn: false, holders: chat("off")).chord == chordSpace)
    }

    @Test func theChatClashIsNamedWithItsFix() {
        let cOption = Shortcut(keyCode: 8, modifiers: [.control, .option])
        func clash(talk: Shortcut = .controlOption, heard: Shortcut? = nil, chat: ChatHotkey, shared: Bool = false,
                   voiceOverOn: Bool = false) -> VoiceKey.ChatClash? {
            VoiceKey.chatClash(talk: talk, heard: heard ?? talk, chat: chat, shared: shared, voiceOverOn: voiceOverOn, holders: [])
        }
        let both = clash(chat: .controlOptionSpace)
        #expect(both?.sentence == "Control-Option-Space also talks to Zeus. While Chat uses it, it opens Chat instead.")
        #expect(both?.fix == .controlOptionC)
        #expect(clash(chat: .controlOptionC) == nil, "the default clashes with nothing")
        #expect(clash(chat: .off) == nil && clash(chat: .optionSpace) == nil)
        #expect(clash(chat: .controlOptionSpace, shared: true) == nil, "no chord in shared mode, so nothing to clash")
        #expect(clash(heard: .optionCommand, chat: .controlOptionSpace, voiceOverOn: true) == nil, "VoiceOver has the key")
        let keyed = clash(talk: chordSpace, chat: .controlOptionSpace)
        #expect(keyed?.sentence == "This is also your Talk to Zeus key. Chat takes it.")
        #expect(keyed?.fix == .controlOptionC)
        let keyedC = clash(talk: cOption, chat: .controlOptionC)
        #expect(keyedC?.sentence == "This is also your Talk to Zeus key. Chat takes it.")
        #expect(keyedC?.fix == .off, "moving Chat to C would clash again, so the fix is to turn it off")
        #expect(clash(talk: cOption, chat: .controlOptionSpace) == nil, "a keyed talk key on C leaves Space to Chat")
    }
}
