import Foundation
import Testing
@testable import Zeus

@Suite("Step zero music position")
struct StepZeroMusicTests {
    private let title = "Name"
    private let artist = "Artist"
    private let album = "Album"
    private let longKey = String(repeating: "k", count: 65)
    private let fullKey = String(repeating: "m", count: 64)

    @Test func positionKeysAreClosedAndTheCharactersAreDropped() {
        #expect(MusicPositionSection.isPositionKey("Playback Position"))
        #expect(MusicPositionSection.isPositionKey("Player Position"))
        #expect(MusicPositionSection.isPositionKey("Elapsed"))
        for key in ["elapsed", "Elapsed ", "Player position", "Playback position", "Name", "Total Time", "Duration", ""] {
            #expect(MusicPositionSection.isPositionKey(key) == false, "\(key)")
        }
        #expect(MusicPositionSection.isPositionKey(longKey) == false)
        #expect(MusicPositionSection.noticeName == "com.apple.Music.playerInfo")

        let state = drive([
            .begin,
            .continueAsked,
            .notice(["Playback Position", title, artist, album, "Player State"]),
        ]).0
        #expect(state.facts[.play]?.positionKey == true)
        #expect(state.facts[.play]?.posted == true)
        let stored = storedStrings(state)
        #expect(stored.contains("Playback Position") == false)
        #expect(stored.contains(title) == false)
        #expect(stored.contains(artist) == false)
        #expect(stored.contains(album) == false)
        #expect(stored.contains("Player State") == false)
        #expect(stored.contains(MusicPositionSection.noticeName) == false)
    }

    @Test func aNoticeDuringPlayDoesNotFillTheNextAction() {
        let (state, effects) = drive([
            .begin,
            .continueAsked,
            .notice([title, "Total Time"]),
            .waited(milliseconds: 15_000),
        ])
        #expect(effects == [.arm, .disarm])
        #expect(state.facts[.play] == MusicPositionSection.Fact(
            posted: true, positionKey: false, noticesTaken: 1, keysRead: 2
        ))
        #expect(state.facts[.pause] == nil)
        #expect(state.marks[.play] == .ran)
        #expect(state.marks[.pause] == nil)
        #expect(state.phase == .gate)
        #expect(state.armed == false)
        #expect(storedStrings(state).contains(title) == false)
        #expect(storedStrings(state).contains("Total Time") == false)
    }

    @Test func theWatchStaysUpUntilAPositionKeyArrives() {
        let (state, effects) = drive([
            .begin,
            .continueAsked,
            .notice([title]),
            .waited(milliseconds: 4_000),
            .notice(["Artist", "Player Position"]),
        ])
        #expect(effects == [.arm, .disarm])
        #expect(state.facts[.play]?.posted == true)
        #expect(state.facts[.play]?.positionKey == true)
        #expect(state.facts[.play]?.noticesTaken == 2)
        #expect(state.facts[.play]?.keysRead == 3)
        #expect(state.clockMs == 0)
        #expect(state.phase == .gate)
        #expect(storedStrings(state).contains("Player Position") == false)
        #expect(storedStrings(state).contains("Artist") == false)
    }

    @Test func silenceAtFifteenSecondsIsNotPostedAndTheBoundaryHolds() {
        let open = drive([
            .begin,
            .continueAsked,
            .waited(milliseconds: 14_999),
        ])
        #expect(open.1 == [.arm])
        #expect(open.0.phase == .watching)
        #expect(open.0.facts[.play] == nil)
        #expect(open.0.clockMs == 14_999)

        let closed = drive([
            .begin,
            .continueAsked,
            .waited(milliseconds: 10_000),
            .waited(milliseconds: 5_000),
        ])
        #expect(closed.1 == [.arm, .disarm])
        #expect(closed.0.facts[.play] == MusicPositionSection.Fact(
            posted: false, positionKey: false, noticesTaken: 0, keysRead: 0
        ))
        #expect(closed.0.marks[.play] == .ran)
        #expect(closed.0.phase == .gate)

        let inside = drive([
            .begin,
            .continueAsked,
            .waited(milliseconds: 14_999),
            .notice(["Elapsed"]),
        ])
        #expect(inside.0.facts[.play]?.posted == true)
        #expect(inside.0.facts[.play]?.positionKey == true)
        #expect(inside.1.filter { $0 == .disarm }.count == 1)

        let late = drive([
            .begin,
            .continueAsked,
            .waited(milliseconds: 15_000),
            .notice(["Elapsed", title]),
        ])
        #expect(late.0.facts[.play]?.posted == false)
        #expect(late.0.facts[.play]?.positionKey == false)
        #expect(late.0.facts[.play]?.noticesTaken == 0)
        #expect(late.1 == [.arm, .disarm])
        #expect(storedStrings(late.0).contains("Elapsed") == false)
        #expect(storedStrings(late.0).contains(title) == false)
    }

    @Test func aNoticePastTheCapIsNotRead() {
        let plain = Array(repeating: MusicPositionSection.Event.notice([title]), count: 64)
        let dropped = drive([.begin, .continueAsked] + plain + [.notice(["Elapsed"])]).0
        #expect(dropped.noticesTaken == 64)
        #expect(dropped.sawNotice)
        #expect(dropped.sawPosition == false)
        #expect(dropped.facts[.play] == nil)
        #expect(dropped.phase == .watching)

        let held = drive([
            .begin, .continueAsked,
        ] + plain + [
            .notice(["Elapsed"]),
            .waited(milliseconds: 15_000),
        ]).0
        #expect(held.facts[.play]?.positionKey == false)
        #expect(held.facts[.play]?.noticesTaken == 64)
        #expect(held.marks[.play] == .ran)
        #expect(storedStrings(held).contains("Elapsed") == false)
    }

    @Test func keysPastThirtyTwoAndOverlongKeysAreNotRead() {
        var buried = Array(repeating: title, count: 32)
        buried.append("Elapsed")
        let missed = drive([.begin, .continueAsked, .notice(buried), .waited(milliseconds: 15_000)]).0
        #expect(missed.facts[.play]?.keysRead == 32)
        #expect(missed.facts[.play]?.positionKey == false)
        #expect(missed.facts[.play]?.noticesTaken == 1)

        let skippedLong = drive([
            .begin, .continueAsked,
            .notice([longKey, "Elapsed"]),
        ]).0
        #expect(skippedLong.facts[.play]?.keysRead == 1)
        #expect(skippedLong.facts[.play]?.positionKey == true)
        #expect(storedStrings(skippedLong).contains(longKey) == false)

        let sixtyFour = drive([
            .begin, .continueAsked,
            .notice([fullKey]),
            .waited(milliseconds: 15_000),
        ]).0
        #expect(sixtyFour.facts[.play]?.keysRead == 1)
        #expect(sixtyFour.facts[.play]?.positionKey == false)
        #expect(storedStrings(sixtyFour).contains(fullKey) == false)
    }

    @Test func skipArmsNothingAndASecondBeginDoesNothing() {
        let skipped = drive([.begin, .skip, .skip, .skip, .skip])
        #expect(skipped.1.isEmpty)
        #expect(skipped.0.phase == .done)
        #expect(skipped.0.marks[.play] == .skipped)
        #expect(skipped.0.marks[.pause] == .skipped)
        #expect(skipped.0.marks[.trackChange] == .skipped)
        #expect(skipped.0.marks[.scrub] == .skipped)
        #expect(skipped.0.facts.isEmpty)
        #expect(skipped.0.armed == false)

        let ignored = drive([
            .notice(["Elapsed"]),
            .skip,
            .waited(milliseconds: 15_000),
            .begin,
            .begin,
        ])
        #expect(ignored.0.phase == .gate)
        #expect(ignored.0.cursor == 0)
        #expect(ignored.1.isEmpty)
        #expect(ignored.0.facts.isEmpty)
    }

    @Test func zeroAndNegativeWaitsDoNotCloseTheWindow() {
        let (state, effects) = drive([
            .begin,
            .continueAsked,
            .waited(milliseconds: 0),
            .waited(milliseconds: -15_000),
            .notice([]),
        ])
        #expect(effects == [.arm])
        #expect(state.phase == .watching)
        #expect(state.clockMs == 0)
        #expect(state.sawNotice)
        #expect(state.sawPosition == false)
        #expect(state.noticesTaken == 1)
        #expect(state.keysRead == 0)
        #expect(state.facts[.play] == nil)
    }

    @Test func theFourActionsRecordPostedAndPositionWithoutATitle() {
        let (state, effects) = drive([
            .begin,
            .continueAsked,
            .notice(["Name", "Elapsed"]),
            .continueAsked,
            .notice(["Player State"]),
            .waited(milliseconds: 15_000),
            .skip,
            .continueAsked,
            .notice(["Playback Position"]),
        ])
        #expect(effects == [.arm, .disarm, .arm, .disarm, .arm, .disarm])
        #expect(state.facts[.play]?.posted == true)
        #expect(state.facts[.play]?.positionKey == true)
        #expect(state.facts[.pause]?.posted == true)
        #expect(state.facts[.pause]?.positionKey == false)
        #expect(state.facts[.trackChange] == nil)
        #expect(state.marks[.trackChange] == .skipped)
        #expect(state.facts[.scrub]?.posted == true)
        #expect(state.facts[.scrub]?.positionKey == true)
        #expect(state.phase == .done)
        #expect(state.armed == false)
        let stored = storedStrings(state)
        #expect(stored.contains("Name") == false)
        #expect(stored.contains("Player State") == false)
        #expect(stored.contains("Playback Position") == false)
        #expect(stored.contains("Elapsed") == false)
    }

    @Test func aNoticeOutsideTheWatchIsIgnored() {
        let before = drive([
            .notice(["Elapsed"]),
            .begin,
            .notice([title]),
        ])
        #expect(before.1.isEmpty)
        #expect(before.0.phase == .gate)
        #expect(before.0.facts.isEmpty)

        let after = drive([
            .begin, .skip, .skip, .skip, .skip,
            .notice(["Elapsed"]),
            .continueAsked,
        ])
        #expect(after.0.phase == .done)
        #expect(after.0.facts.isEmpty)
        #expect(after.1.isEmpty)
        #expect(storedStrings(after.0).isEmpty)
    }

    private func drive(_ events: [MusicPositionSection.Event]) -> (MusicPositionSection.State, [MusicPositionSection.Effect]) {
        var state = MusicPositionSection.fresh()
        var effects: [MusicPositionSection.Effect] = []
        for event in events {
            let reduced = MusicPositionSection.reduce(state, event)
            state = reduced.state
            effects.append(contentsOf: reduced.effects)
        }
        return (state, effects)
    }

    private func storedStrings(_ state: MusicPositionSection.State) -> [String] {
        var found: [String] = []
        func walk(_ value: Any) {
            if let text = value as? String {
                found.append(text)
                return
            }
            let mirror = Mirror(reflecting: value)
            if mirror.displayStyle == .optional {
                if let child = mirror.children.first {
                    walk(child.value)
                }
                return
            }
            for child in mirror.children {
                walk(child.value)
            }
        }
        walk(state)
        return found
    }
}
