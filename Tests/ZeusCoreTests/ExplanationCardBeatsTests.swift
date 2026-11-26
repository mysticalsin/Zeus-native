import Foundation
import Testing
@testable import ZeusCore

/// Phase 4 card beats (`docs/POINTING-ASSISTANT-PLAN.md`).
/// The share is the current beat's non-capture creates and connects.
/// The caption is the speech unchanged. A visible card lingers 25 seconds
/// after a normal finish, and a zero-width space is not a blank caption.
@Suite("Explanation card beats")
struct ExplanationCardBeatsTests {
    private typealias Beats = ExplanationCardBeats

    private func beat(_ id: String, _ speech: String, _ marks: [Beats.Mark] = []) -> Beats.Beat {
        Beats.Beat(id: id, speech: speech, marks: marks)
    }

    private func shown(_ turn: inout Beats.Turn, _ item: Beats.Beat) -> Beats.Share? {
        if case .shown(let share) = turn.admit(item) { return share }
        return nil
    }

    @Test func theClockContractMatchesTheCardAndTheProtocolLimits() {
        #expect(Beats.lingerSeconds == 25)
        #expect(Beats.speechByteLimit == 1600)
        #expect(Beats.identifierByteLimit == 64)
        #expect(Beats.maxBeats == 64)
        #expect(Beats.Space.canvas.rawValue == "canvas")
        #expect(Beats.Space.world.rawValue == "world")
        #expect(Beats.Space.capture.rawValue == "capture")
    }

    @Test func aBeatContributesCreatesAndConnectsOutsideCapture() {
        let marks: [Beats.Mark] = [
            .create(id: "ring", space: .canvas),
            .connect(id: "flow", space: .world),
            .create(id: "mark", space: .capture),
            .connect(id: "overlay", space: .capture),
            .other(id: "ring"),
            .create(id: "ring", space: .canvas),
            .create(id: "", space: .canvas),
            .create(id: "kept", space: .canvas),
            .create(id: "kept", space: .capture),
            .other(id: "kept"),
            .connect(id: "axle", space: .world),
        ]
        let ids = Beats.objectIDs(in: marks)
        #expect(ids == ["ring", "flow", "", "kept", "axle"])
        #expect(ids.contains("mark") == false)
        #expect(ids.contains("overlay") == false)
        #expect(Beats.objectIDs(in: []) == [])
        #expect(Beats.objectIDs(in: [.other(id: "ring"), .create(id: "mark", space: .capture)]) == [])
    }

    @Test func theNextBeatReplacesTheShareAndKeepsTheSpokenCaption() {
        var turn = Beats.Turn()
        let first = shown(&turn, beat("b0", "  Share  ", [
            .create(id: "ring", space: .canvas),
            .create(id: "mark", space: .capture),
        ]))
        #expect(first?.beatID == "b0")
        #expect(first?.caption == "  Share  ")
        #expect(first?.objectIDs == ["ring"])
        #expect(turn.share == first)
        #expect(turn.admitted == ["b0"])

        let second = shown(&turn, beat("b1", "a\nb", [
            .connect(id: "flow", space: .world),
            .other(id: "ring"),
        ]))
        #expect(second?.caption == "a\nb")
        #expect(second?.objectIDs == ["flow"])
        #expect(turn.share?.objectIDs.contains("ring") == false)
        #expect(turn.admitted == ["b0", "b1"])

        let spoken = shown(&turn, beat("b2", "\u{200B}"))
        #expect(spoken?.caption == "\u{200B}")
        #expect(spoken?.objectIDs == [])
        #expect(turn.phase == .open)
    }

    @Test func aZeroWidthSpaceIsACaptionAndTheSpeechIsNotTrimmed() {
        var turn = Beats.Turn()
        let samples = [
            "\u{200B}",
            "a\u{200B}b",
            "\u{3000}\u{200B}\u{3000}",
            "\u{200C}",
            "  Share  ",
            "\nShare",
            "a\tb",
            "a\u{00A0}b",
            "a\u{3000}b",
            "Share",
        ]
        for (index, speech) in samples.enumerated() {
            let share = shown(&turn, beat("s\(index)", speech))
            #expect(share?.caption == speech)
            #expect(share?.objectIDs == [])
        }
        #expect(turn.admit(beat("blank", "")) == .refused(.speech))
        #expect(turn.admit(beat("blank", " ")) == .refused(.speech))
        #expect(turn.admit(beat("blank", "\n")) == .refused(.speech))
        #expect(turn.admit(beat("blank", "\t")) == .refused(.speech))
        #expect(turn.admit(beat("blank", "\u{00A0}")) == .refused(.speech))
        #expect(turn.admit(beat("blank", " \t\n\u{00A0}")) == .refused(.speech))
        #expect(turn.admit(beat("blank", "\u{2028}")) == .refused(.speech))
        #expect(turn.admit(beat("blank", "\u{2029}")) == .refused(.speech))
        #expect(turn.admit(beat("blank", "\u{3000}")) == .refused(.speech))
        #expect(turn.admit(beat("blank", "\u{0085}")) == .refused(.speech))
        #expect(turn.admit(beat("blank", "\u{1680}")) == .refused(.speech))
        #expect(turn.admit(beat("blank", "\r")) == .refused(.speech))
        #expect(turn.admit(beat("blank", "a\rb")) == .refused(.speech))
        #expect(turn.admit(beat("blank", "a\u{0000}b")) == .refused(.speech))
        #expect(turn.admit(beat("blank", "a\u{000B}b")) == .refused(.speech))
        #expect(turn.admit(beat("blank", "a\u{007F}b")) == .refused(.speech))
        #expect(turn.share?.beatID == "s9")
        #expect(turn.admitted == (0..<samples.count).map { "s\($0)" })
    }

    @Test func speechBoundsUseUTF8BytesAndStayInsideTheLimit() {
        var turn = Beats.Turn()
        let exact = String(repeating: "a", count: Beats.speechByteLimit)
        #expect(exact.utf8.count == 1600)
        #expect(shown(&turn, beat("full", exact))?.caption == exact)
        let over = String(repeating: "a", count: Beats.speechByteLimit + 1)
        #expect(turn.admit(beat("over", over)) == .refused(.speech))
        let accented = String(repeating: "é", count: 800)
        #expect(accented.utf8.count == 1600)
        #expect(shown(&turn, beat("accent", accented))?.caption == accented)
        let accentedOver = String(repeating: "é", count: 801)
        #expect(accentedOver.utf8.count == 1602)
        #expect(turn.admit(beat("accentOver", accentedOver)) == .refused(.speech))
        #expect(turn.share?.beatID == "accent")
    }

    @Test func aBadIdentifierIsRefusedBeforeSpeechAndALegalIdIsAdmitted() {
        var turn = Beats.Turn()
        let legal = ["b0", "beat_1", "A-1", "b_0-1", String(repeating: "a", count: 64)]
        for (index, id) in legal.enumerated() {
            #expect(shown(&turn, beat(id, "ok \(index)"))?.beatID == id)
        }
        let illegal = [
            "",
            " ",
            "b.0",
            "bé",
            "b0\n",
            "b 0",
            String(repeating: "a", count: 65),
            "b0 ",
        ]
        for id in illegal {
            #expect(turn.admit(beat(id, "")) == .refused(.identifier))
            #expect(turn.admit(beat(id, "ok")) == .refused(.identifier))
        }
        #expect(turn.share?.beatID == String(repeating: "a", count: 64))
        #expect(turn.admitted.count == legal.count)
    }

    @Test func aRepeatedBeatDoesNotReplaceTheShareAndTheTurnStopsAtSixtyFour() {
        var turn = Beats.Turn()
        #expect(shown(&turn, beat("b0", "first", [.create(id: "ring", space: .canvas)]))?.caption == "first")
        #expect(turn.admit(beat("b0", "second", [.create(id: "other", space: .world)])) == .refused(.duplicate))
        #expect(turn.share?.caption == "first")
        #expect(turn.share?.objectIDs == ["ring"])
        #expect(turn.admit(beat("b0", "")) == .refused(.speech))
        #expect(turn.admitted == ["b0"])

        for index in 1..<Beats.maxBeats {
            #expect(shown(&turn, beat("b\(index)", "n\(index)"))?.beatID == "b\(index)")
        }
        #expect(turn.admitted.count == 64)
        #expect(turn.admit(beat("b0", "again")) == .refused(.duplicate))
        #expect(turn.admit(beat("b64", "past")) == .refused(.budget))
        #expect(turn.share?.beatID == "b63")
        #expect(turn.share?.caption == "n63")
        #expect(turn.admitted.count == 64)
    }

    @Test func aVisibleCardLingersTwentyFiveSecondsAndABadTickDoesNotMoveIt() {
        var hidden = Beats.Turn()
        #expect(hidden.finish(visible: true) == .ended)
        #expect(hidden.phase == .ended)
        #expect(hidden.share == nil)

        var quiet = Beats.Turn()
        #expect(shown(&quiet, beat("b0", "Share")) != nil)
        #expect(quiet.finish(visible: false) == .ended)
        #expect(quiet.share == nil)
        #expect(quiet.tick(25) == .idle)

        var turn = Beats.Turn()
        let share = shown(&turn, beat("b0", "Share", [.create(id: "ring", space: .canvas)]))
        #expect(turn.finish(visible: true) == .lingering)
        #expect(turn.phase == .lingering)
        #expect(turn.share == share)
        #expect(turn.lingerElapsed == 0)
        #expect(turn.tick(0) == .advanced(remaining: 25))
        #expect(turn.tick(10) == .advanced(remaining: 15))
        #expect(turn.lingerElapsed == 10)
        #expect(turn.finish(visible: true) == .lingering)
        #expect(turn.lingerElapsed == 10)
        let elapsed = turn.lingerElapsed
        for step in [Double.nan, Double.infinity, -Double.infinity, -1, -0.1] {
            #expect(turn.tick(step) == .refused)
            #expect(turn.lingerElapsed == elapsed)
            #expect(turn.phase == .lingering)
            #expect(turn.share == share)
        }
        #expect(turn.tick(14.5) == .advanced(remaining: 0.5))
        #expect(turn.tick(0.5) == .ended)
        #expect(turn.phase == .ended)
        #expect(turn.share == nil)
        #expect(turn.lingerElapsed == 25)
        #expect(turn.tick(1) == .idle)

        var huge = Beats.Turn()
        #expect(shown(&huge, beat("b0", "Share")) != nil)
        #expect(huge.finish(visible: true) == .lingering)
        #expect(huge.tick(Double.greatestFiniteMagnitude) == .ended)
        #expect(huge.lingerElapsed == 25)
        #expect(huge.phase == .ended)
        #expect(huge.share == nil)
    }

    @Test func cancelDismissAndANewTurnCloseTheCard() {
        var turn = Beats.Turn()
        #expect(shown(&turn, beat("b0", "Share", [.create(id: "ring", space: .canvas)])) != nil)
        #expect(turn.finish(visible: true) == .lingering)
        #expect(turn.admit(beat("b1", "late")) == .refused(.finished))
        #expect(turn.share?.beatID == "b0")
        turn.cancel()
        #expect(turn.phase == .ended)
        #expect(turn.share == nil)
        #expect(turn.lingerElapsed == 0)
        #expect(turn.tick(25) == .idle)
        #expect(turn.admit(beat("b1", "late")) == .refused(.finished))

        turn.begin()
        #expect(turn.phase == .open)
        #expect(turn.admitted == [])
        let again = shown(&turn, beat("b0", "again"))
        #expect(again?.caption == "again")

        turn.dismiss()
        #expect(turn.phase == .dismissed)
        #expect(turn.share == nil)
        #expect(turn.admit(beat("", "")) == .refused(.dismissed))
        #expect(turn.admit(beat("b1", "next")) == .refused(.dismissed))
        #expect(turn.tick(25) == .idle)
        turn.cancel()
        #expect(turn.phase == .dismissed)
        turn.begin()
        #expect(shown(&turn, beat("b1", "next"))?.caption == "next")
        #expect(turn.phase == .open)
    }
}
