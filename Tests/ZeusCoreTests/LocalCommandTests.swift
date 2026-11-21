import Foundation
import Testing
@testable import ZeusCore

/// Acceptance tests for `specs/011-fast-local-commands/spec.md`.
/// The grammar is closed: every accepted row is listed, and the rejected rows must not act.
@Suite struct LocalCommandTests {
    private static let origin = ContinuousClock.now

    private final class ScriptedClock: @unchecked Sendable {
        var instant: ContinuousClock.Instant
        init(_ instant: ContinuousClock.Instant) { self.instant = instant }
        var clock: LocalCommandClock { LocalCommandClock { self.instant } }
    }

    private static func clock(after milliseconds: Int) -> LocalCommandClock {
        clock(at: origin.advanced(by: .milliseconds(milliseconds)))
    }

    private static func clock(at instant: ContinuousClock.Instant) -> LocalCommandClock {
        ScriptedClock(instant).clock
    }

    private static let harbor = LocalApp(
        name: "Harbor", bundleID: "example.harbor", path: "/Apps/Harbor.app",
        aliases: ["harbour"], isRunning: true, hasUnsavedState: false)
    private static let fieldNotes = LocalApp(
        name: "Field Notes", bundleID: "example.fieldnotes", path: "/Apps/Field Notes.app",
        aliases: ["notes"], isRunning: true, hasUnsavedState: nil)
    private static let quickNotes = LocalApp(
        name: "Quick Notes", bundleID: "example.quicknotes", path: "/Apps/Quick Notes.app",
        aliases: ["notes"], isRunning: true, hasUnsavedState: nil)
    private static let catalog = [harbor, fieldNotes, quickNotes]

    private struct Accepted {
        let phrase: String
        let command: LocalCommand
    }

    /// Every row of the intent table, plus surface forms that normalise onto a row.
    private static let accepted: [Accepted] = [
        Accepted(phrase: "play", command: .media(.play)),
        Accepted(phrase: "play music", command: .media(.play)),
        Accepted(phrase: "play the music", command: .media(.play)),
        Accepted(phrase: "resume", command: .media(.play)),
        Accepted(phrase: "resume music", command: .media(.play)),
        Accepted(phrase: "resume the music", command: .media(.play)),
        Accepted(phrase: "resume playback", command: .media(.play)),
        Accepted(phrase: "start music", command: .media(.play)),
        Accepted(phrase: "start the music", command: .media(.play)),
        Accepted(phrase: "Play.", command: .media(.play)),
        Accepted(phrase: "hey zeus play", command: .media(.play)),

        Accepted(phrase: "pause", command: .media(.pause)),
        Accepted(phrase: "pause music", command: .media(.pause)),
        Accepted(phrase: "pause the music", command: .media(.pause)),
        Accepted(phrase: "pause the song", command: .media(.pause)),
        Accepted(phrase: "pause playback", command: .media(.pause)),
        Accepted(phrase: "pause the music please", command: .media(.pause)),

        Accepted(phrase: "next", command: .media(.next)),
        Accepted(phrase: "next song", command: .media(.next)),
        Accepted(phrase: "next track", command: .media(.next)),
        Accepted(phrase: "skip", command: .media(.next)),
        Accepted(phrase: "skip song", command: .media(.next)),
        Accepted(phrase: "skip track", command: .media(.next)),
        Accepted(phrase: "skip this song", command: .media(.next)),
        Accepted(phrase: "skip this track", command: .media(.next)),
        Accepted(phrase: "Next.", command: .media(.next)),

        Accepted(phrase: "volume up", command: .volume(.up)),
        Accepted(phrase: "louder", command: .volume(.up)),
        Accepted(phrase: "turn it up", command: .volume(.up)),
        Accepted(phrase: "turn the volume up", command: .volume(.up)),
        Accepted(phrase: "turn up the volume", command: .volume(.up)),
        Accepted(phrase: "louder please", command: .volume(.up)),

        Accepted(phrase: "volume down", command: .volume(.down)),
        Accepted(phrase: "quieter", command: .volume(.down)),
        Accepted(phrase: "turn it down", command: .volume(.down)),
        Accepted(phrase: "turn the volume down", command: .volume(.down)),
        Accepted(phrase: "turn down the volume", command: .volume(.down)),

        Accepted(phrase: "mute", command: .volume(.mute)),
        Accepted(phrase: "mute it", command: .volume(.mute)),
        Accepted(phrase: "unmute", command: .volume(.unmute)),
        Accepted(phrase: "unmute it", command: .volume(.unmute)),

        Accepted(phrase: "set the volume to 30", command: .volume(.set(30))),
        Accepted(phrase: "set volume to 45", command: .volume(.set(45))),
        Accepted(phrase: "set the volume to 30 percent", command: .volume(.set(30))),
        Accepted(phrase: "set the volume to 30%", command: .volume(.set(30))),
        Accepted(phrase: "volume 70", command: .volume(.set(70))),
        Accepted(phrase: "volume to 12", command: .volume(.set(12))),
        Accepted(phrase: "volume at 0", command: .volume(.set(0))),
        Accepted(phrase: "volume 100", command: .volume(.set(100))),
        Accepted(phrase: "change the volume to 15", command: .volume(.set(15))),
        Accepted(phrase: "change volume to 9", command: .volume(.set(9))),
        Accepted(phrase: "change the volume at 4", command: .volume(.set(4))),
        Accepted(phrase: "put the volume to 8", command: .volume(.set(8))),
        Accepted(phrase: "put the volume at 7", command: .volume(.set(7))),
        Accepted(phrase: "put volume to 6", command: .volume(.set(6))),
        Accepted(phrase: "put volume at 5", command: .volume(.set(5))),
        Accepted(phrase: "turn the volume to 3", command: .volume(.set(3))),
        Accepted(phrase: "turn the volume at 2", command: .volume(.set(2))),
        Accepted(phrase: "turn volume to 1", command: .volume(.set(1))),
        Accepted(phrase: "make the volume to 11", command: .volume(.set(11))),
        Accepted(phrase: "make the volume at 100", command: .volume(.set(100))),
        Accepted(phrase: "set the volume at 40", command: .volume(.set(40))),
        Accepted(phrase: "set volume at 41", command: .volume(.set(41))),
        Accepted(phrase: "volume to fifty", command: .volume(.set(50))),
        Accepted(phrase: "set the volume to fifty", command: .volume(.set(50))),
        Accepted(phrase: "set the volume to twenty five", command: .volume(.set(25))),
        Accepted(phrase: "volume ninety nine", command: .volume(.set(99))),
        Accepted(phrase: "set volume to zero", command: .volume(.set(0))),
        Accepted(phrase: "volume hundred", command: .volume(.set(100))),

        Accepted(phrase: "open harbor", command: .open("harbor")),
        Accepted(phrase: "launch harbor", command: .open("harbor")),
        Accepted(phrase: "start harbor", command: .open("harbor")),
        Accepted(phrase: "run harbor", command: .open("harbor")),
        Accepted(phrase: "fire up harbor", command: .open("harbor")),
        Accepted(phrase: "bring up harbor", command: .open("harbor")),
        Accepted(phrase: "pull up harbor", command: .open("harbor")),
        Accepted(phrase: "open the harbor", command: .open("harbor")),
        Accepted(phrase: "open the harbor app", command: .open("harbor")),
        Accepted(phrase: "open my harbor", command: .open("harbor")),
        Accepted(phrase: "Hey Zeus, open Harbor please.", command: .open("harbor")),
        Accepted(phrase: "can you open harbor", command: .open("harbor")),
        Accepted(phrase: "could you please open harbor for me", command: .open("harbor")),
        Accepted(phrase: "would you open harbor", command: .open("harbor")),
        Accepted(phrase: "um open harbor", command: .open("harbor")),
        Accepted(phrase: "open field notes", command: .open("field notes")),

        Accepted(phrase: "switch to harbor", command: .switchTo("harbor")),
        Accepted(phrase: "switch harbor", command: .switchTo("harbor")),
        Accepted(phrase: "go to harbor", command: .switchTo("harbor")),
        Accepted(phrase: "switch to the harbor app", command: .switchTo("harbor")),
        Accepted(phrase: "switch to field notes", command: .switchTo("field notes")),

        Accepted(phrase: "quit harbor", command: .quit("harbor")),
        Accepted(phrase: "close harbor", command: .quit("harbor")),
        Accepted(phrase: "exit harbor", command: .quit("harbor")),
        Accepted(phrase: "quit the harbor app", command: .quit("harbor")),
        Accepted(phrase: "hey zeus quit harbor", command: .quit("harbor")),
    ]

    private static let rejected = [
        "what's the weather tomorrow",
        "close this tab",
        "close the window",
        "close this window",
        "open the file",
        "open harbor and then tell me the weather",
        "open harbor and mail",
        "play jazz",
        "play something relaxing",
        "play some music",
        "quit everything",
        "how do I open harbor",
        "tell me a joke",
        "stop",
        "open it",
        "what's playing",
        "hey zeus",
        "",
        "   ",
        "set a timer for 5 minutes",
        "volume",
        "open",
        "switch to",
        "play harbor",
        "close this",
        "quit",
        "next week",
        "pause the meeting",
        "volume up the speaker",
        "set the volume to 150",
        "volume 101",
        "set the volume to 101 percent",
        "make it louder",
    ]

    private static func performed(_ decision: LocalCommandDecision) -> LocalCommandAction? {
        for effect in decision.effects {
            if case .perform(let action) = effect { return action }
        }
        return nil
    }

    private static func spoken(_ decision: LocalCommandDecision) -> String? {
        for effect in decision.effects {
            if case .speak(let line) = effect { return line }
        }
        return nil
    }

    @Test func exhaustiveParserTable() {
        #expect(Self.accepted.count >= 90)
        for row in Self.accepted {
            #expect(LocalCommandParser.parse(row.phrase) == row.command, "\(row.phrase)")
        }
    }

    @Test func unrecognizedFallsThrough() {
        let clock = Self.clock(after: 5)
        for phrase in Self.rejected {
            #expect(LocalCommandParser.parse(phrase) == nil, "parser kept \(phrase)")
            var machine = LocalCommandMachine()
            let decision = machine.receive(phrase, finalAt: Self.origin, clock: clock, apps: Self.catalog)
            #expect(decision.effects == [.fallThrough], "\(phrase)")
            #expect(decision.consumed == false, "\(phrase)")
            #expect(machine.state == .idle, "\(phrase)")
        }

        var machine = LocalCommandMachine()
        for phrase in ["open meadow", "quit meadow", "switch to meadow", "go to sleep", "open harbor repo"] {
            let decision = machine.receive(phrase, finalAt: Self.origin, clock: clock, apps: Self.catalog)
            #expect(decision.effects == [.fallThrough], "\(phrase)")
            #expect(Self.performed(decision) == nil, "\(phrase)")
            #expect(machine.state == .idle, "\(phrase)")
        }
    }

    @Test func latencyBudgetUsesTheInjectedClock() {
        #expect(LocalCommandMachine.latencyBudgetMilliseconds == 150)

        var inside = LocalCommandMachine()
        let acted = inside.receive("open harbor", finalAt: Self.origin, clock: Self.clock(after: 149), apps: Self.catalog)
        #expect(acted.elapsedMilliseconds == 149)
        #expect(Self.performed(acted) == .open(Self.harbor))
        #expect(acted.consumed == true)

        var edge = LocalCommandMachine()
        let missed = edge.receive("pause", finalAt: Self.origin, clock: Self.clock(after: 150), apps: Self.catalog)
        #expect(missed.elapsedMilliseconds == 150)
        #expect(missed.effects == [.fallThrough])
        #expect(Self.performed(missed) == nil)
        #expect(edge.state == .idle)

        var early = LocalCommandMachine()
        let quick = early.receive("next", finalAt: Self.origin, clock: Self.clock(after: 40), apps: Self.catalog)
        #expect(quick.elapsedMilliseconds == 40)
        #expect(Self.performed(quick) == .media(.next))

        var quitting = LocalCommandMachine()
        let dirty = Self.harbor.withUnsaved(nil)
        let asked = quitting.receive("quit harbor", finalAt: Self.origin, clock: Self.clock(after: 10), apps: [dirty])
        #expect(Self.performed(asked) == nil)
        guard case .confirmingQuit = quitting.state else {
            Issue.record("quit should be waiting, state \(quitting.state)")
            return
        }
        let lateYes = quitting.receive("yes", finalAt: Self.origin, clock: Self.clock(after: 150), apps: [dirty])
        #expect(lateYes.effects == [.fallThrough])
        #expect(Self.performed(lateYes) == nil)
        #expect(quitting.state == .idle)
    }

    @Test func ambiguousNameAsksBeforeItActs() {
        let clock = Self.clock(after: 8)
        var machine = LocalCommandMachine()
        let asked = machine.receive("open notes", finalAt: Self.origin, clock: clock, apps: Self.catalog)
        #expect(Self.performed(asked) == nil)
        #expect(Self.spoken(asked) == "Did you mean Field Notes or Quick Notes?")
        #expect(asked.elapsedMilliseconds == 8)
        guard case .confirmingChoice(let verb, let candidates) = machine.state else {
            Issue.record("expected a choice, state \(machine.state)")
            return
        }
        #expect(verb == .open)
        #expect(candidates.map(\.bundleID) == ["example.fieldnotes", "example.quicknotes"])

        let chosen = machine.receive("field notes", finalAt: Self.origin, clock: clock, apps: Self.catalog)
        #expect(Self.performed(chosen) == .open(Self.fieldNotes))
        #expect(Self.spoken(chosen) == "Opening Field Notes.")
        #expect(chosen.consumed == true)

        var declined = LocalCommandMachine()
        _ = declined.receive("open notes", finalAt: Self.origin, clock: clock, apps: Self.catalog)
        let no = declined.receive("no", finalAt: Self.origin, clock: clock, apps: Self.catalog)
        #expect(Self.performed(no) == nil)
        #expect(Self.spoken(no) == "Okay.")
        #expect(declined.state == .idle)

        var unspecific = LocalCommandMachine()
        _ = unspecific.receive("open notes", finalAt: Self.origin, clock: clock, apps: Self.catalog)
        let yes = unspecific.receive("yes", finalAt: Self.origin, clock: clock, apps: Self.catalog)
        #expect(Self.performed(yes) == nil)
        #expect(yes.effects == [.fallThrough])
        #expect(unspecific.state == .idle)

        var exact = LocalCommandMachine()
        let direct = exact.receive("open field notes", finalAt: Self.origin, clock: clock, apps: Self.catalog)
        #expect(Self.performed(direct) == .open(Self.fieldNotes))

        var alias = LocalCommandMachine()
        let harbour = alias.receive("open harbour", finalAt: Self.origin, clock: clock, apps: Self.catalog)
        #expect(Self.performed(harbour) == .open(Self.harbor))
    }

    @Test func quitAsksUnlessUnsavedStateIsKnownClean() {
        let clock = Self.clock(after: 6)

        var unknown = LocalCommandMachine()
        let unsaved = Self.harbor.withUnsaved(nil)
        let asked = unknown.receive("quit harbor", finalAt: Self.origin, clock: clock, apps: [unsaved])
        #expect(Self.performed(asked) == nil)
        #expect(Self.spoken(asked) == "Quit Harbor? It may have unsaved changes.")
        guard case .confirmingQuit(let pending) = unknown.state else {
            Issue.record("expected quit confirmation, state \(unknown.state)")
            return
        }
        #expect(pending.bundleID == Self.harbor.bundleID)
        let yes = unknown.receive("yes", finalAt: Self.origin, clock: clock, apps: [unsaved])
        #expect(Self.performed(yes) == .quit(unsaved))
        #expect(Self.spoken(yes) == "Quitting Harbor.")

        var dirty = LocalCommandMachine()
        let changed = Self.harbor.withUnsaved(true)
        let again = dirty.receive("close harbor", finalAt: Self.origin, clock: clock, apps: [changed])
        #expect(Self.performed(again) == nil)
        let leave = dirty.receive("no", finalAt: Self.origin, clock: clock, apps: [changed])
        #expect(Self.performed(leave) == nil)
        #expect(Self.spoken(leave) == "Leaving it open.")
        #expect(dirty.state == .idle)

        var clean = LocalCommandMachine()
        let immediate = clean.receive("quit harbor", finalAt: Self.origin, clock: clock, apps: [Self.harbor])
        #expect(Self.performed(immediate) == .quit(Self.harbor))
        #expect(Self.spoken(immediate) == "Quitting Harbor.")

        var closed = LocalCommandMachine()
        let stopped = Self.harbor.withRunning(false)
        let missing = closed.receive("quit harbor", finalAt: Self.origin, clock: clock, apps: [stopped])
        #expect(Self.performed(missing) == nil)
        #expect(Self.spoken(missing) == "Harbor isn't open.")
        #expect(closed.state == .idle)
    }

    /// "ok", "sure", and a bare "quit" are not a confirmation. An explicit phrase still is.
    @Test func quitConfirmationRequiresAnExplicitPhrase() {
        let unsaved = Self.harbor.withUnsaved(nil)
        let clock = Self.clock(after: 6)
        for phrase in ["ok", "sure", "quit", "OK", "Sure."] {
            var machine = LocalCommandMachine()
            _ = machine.receive("quit harbor", finalAt: Self.origin, clock: clock, apps: [unsaved])
            let reply = machine.receive(phrase, finalAt: Self.origin, clock: clock, apps: [unsaved])
            #expect(Self.performed(reply) == nil, "\(phrase) must not quit")
            #expect(reply.effects == [.fallThrough], "\(phrase)")
            #expect(machine.state == .idle, "\(phrase)")
        }
        var explicit = LocalCommandMachine()
        _ = explicit.receive("quit harbor", finalAt: Self.origin, clock: clock, apps: [unsaved])
        let confirmed = explicit.receive("quit it", finalAt: Self.origin, clock: clock, apps: [unsaved])
        #expect(Self.performed(confirmed) == .quit(unsaved))
    }

    /// The pending quit lasts 10 seconds, or until the next turn ends, whichever comes first.
    @Test func quitConfirmationExpiresAtTenSecondsOrTheNextTurn() {
        let unsaved = Self.harbor.withUnsaved(nil)
        let askedAt = Self.origin.advanced(by: .milliseconds(6))

        var stillOpen = LocalCommandMachine()
        _ = stillOpen.receive("quit harbor", finalAt: Self.origin, clock: Self.clock(at: askedAt), apps: [unsaved])
        let soon = askedAt.advanced(by: .milliseconds(9_999))
        let yes = stillOpen.receive("yes", finalAt: soon.advanced(by: .milliseconds(-4)),
                                     clock: Self.clock(at: soon), apps: [unsaved])
        #expect(Self.performed(yes) == .quit(unsaved))

        var timedOut = LocalCommandMachine()
        _ = timedOut.receive("quit harbor", finalAt: Self.origin, clock: Self.clock(at: askedAt), apps: [unsaved])
        let deadline = askedAt.advanced(by: .seconds(10))
        let late = timedOut.receive("yes", finalAt: deadline.advanced(by: .milliseconds(-4)),
                                     clock: Self.clock(at: deadline), apps: [unsaved])
        #expect(Self.performed(late) == nil)
        #expect(late.effects == [.fallThrough])
        #expect(timedOut.state == .idle)

        var replaced = LocalCommandMachine()
        _ = replaced.receive("quit harbor", finalAt: Self.origin, clock: Self.clock(at: askedAt), apps: [unsaved])
        let paused = replaced.receive("pause", finalAt: deadline.advanced(by: .milliseconds(-4)),
                                       clock: Self.clock(at: deadline), apps: [unsaved])
        #expect(Self.performed(paused) == .media(.pause))

        var ended = LocalCommandMachine()
        _ = ended.receive("quit harbor", finalAt: Self.origin, clock: Self.clock(at: askedAt), apps: [unsaved])
        ended.armQuitExpiryAtEndOfNextTurn()
        ended.endTurn()
        let afterTurn = askedAt.advanced(by: .seconds(2))
        let ignored = ended.receive("yes", finalAt: afterTurn.advanced(by: .milliseconds(-4)),
                                     clock: Self.clock(at: afterTurn), apps: [unsaved])
        #expect(Self.performed(ignored) == nil)
        #expect(ignored.effects == [.fallThrough])
        #expect(ended.state == .idle)
    }

    /// The spoken catalog is /Applications and the user's Applications folder. Nothing else.
    @Test func localCatalogIsApplicationsAndTheUserApplicationsFolder() {
        let home = "/Users/ada"
        #expect(LocalAppCatalog.included("/Applications/Harbor.app", home: home))
        #expect(LocalAppCatalog.included("/Applications/Utilities/Terminal.app", home: home))
        #expect(LocalAppCatalog.included("/Users/ada/Applications/Field Notes.app", home: home))
        #expect(LocalAppCatalog.included("/Users/ada/Applications/Set/Field Notes.app", home: home))
        #expect(!LocalAppCatalog.included("/System/Applications/Calendar.app", home: home))
        #expect(!LocalAppCatalog.included("/System/Applications/Utilities/Terminal.app", home: home))
        #expect(!LocalAppCatalog.included("/System/Library/CoreServices/Finder.app", home: home))
        #expect(!LocalAppCatalog.included("/ApplicationsExtra/Harbor.app", home: home))
        #expect(!LocalAppCatalog.included("/Users/ada/ApplicationsExtra/Harbor.app", home: home))
        #expect(!LocalAppCatalog.included("/opt/homebrew/Caskroom/Harbor.app", home: home))
        #expect(!LocalAppCatalog.included("", home: home))
        #expect(!LocalAppCatalog.included("/Applications/Harbor.app", home: ""))
    }
}

extension LocalApp {
    fileprivate func withUnsaved(_ state: Bool?) -> LocalApp {
        var copy = self
        copy.hasUnsavedState = state
        return copy
    }

    fileprivate func withRunning(_ running: Bool) -> LocalApp {
        var copy = self
        copy.isRunning = running
        return copy
    }
}
