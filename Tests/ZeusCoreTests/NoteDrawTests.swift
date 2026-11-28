import Testing
@testable import ZeusCore

struct NoteDrawTests {
    private func cards(_ plan: NoteDraw) -> [String] {
        plan.draw.marks.compactMap { mark in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
    }

    @Test func aNoteDrawsTheWords() {
        let plan = NoteDraw.plan(text: "Buy milk")
        #expect(plan.map(cards) == ["Note", "Buy milk"])
        #expect(NoteAsk.line("Buy milk") == "Buy milk.")
        #expect(NoteAsk.line("Buy milk.") == "Buy milk.")
        #expect(plan?.boltCaption(at: 0) == "Note")
        #expect(plan?.boltCaption(at: ExplainBeatSchedule.gap) == "Buy milk")
        #expect(plan?.guideBolt(at: ExplainBeatSchedule.gap) == TalkDraw.Point(x: 920, y: 180))
        #expect(NoteDraw.plan(text: " ") == nil)
        #expect(NoteDraw.plan(text: "my password is swordfish") == nil)
        let long = String(repeating: "word ", count: 30)
        let clipped = NoteDraw.plan(text: long)
        #expect((clipped?.note.count ?? 99) <= 60)
        #expect(clipped?.note.hasSuffix("word") == true)
    }

    @Test func anEmptyNoteDrawsNoneAndAReminderIsNotThisAsk() {
        #expect(cards(NoteDraw.none()) == ["Note", "None"])
        #expect(cards(NoteDraw.secret()) == ["Note", "Not stored"])
        #expect(NoteAsk.none == "There's no note.")
        #expect(NoteAsk.secret == "I can't read that.")
        #expect(NoteAsk.refuses("the CVV is 123"))
        #expect(NoteAsk.refuses("social security 111"))
        #expect(!NoteAsk.refuses("Buy milk"))
        #expect(NoteAsk.matches("read my note"))
        #expect(NoteAsk.matches("Hey Zeus, what's my note?"))
        #expect(!NoteAsk.matches("new reminder: pay rent"))
        #expect(!NoteAsk.matches("remember that I take tea at 4"))
        #expect(!NoteAsk.matches("what's the date"))
        #expect(!NoteAsk.matches("what's next"))
    }
}
