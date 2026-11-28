import Testing
@testable import ZeusCore

struct ChatCountDrawTests {
    private func cards(_ plan: ChatCountDraw) -> [String] {
        plan.draw.marks.compactMap { mark in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
    }

    @Test func severalChatsDrawTheCountAndLeaveTitlesOff() {
        let plan = ChatCountDraw.plan(writing: false, count: 4, countsOnly: false)
        #expect(cards(plan) == ["Chats", "4"])
        #expect(ChatCountAsk.line(writing: false, count: 4, countsOnly: false) == "You have 4 chats.")
        #expect(ChatCountAsk.line(writing: false, count: 1, countsOnly: false) == "You have 1 chat.")
        #expect(plan.boltCaption(at: 0) == "Chats")
        #expect(plan.boltCaption(at: ExplainBeatSchedule.gap) == "4")
        #expect(plan.guideBolt(at: ExplainBeatSchedule.gap) == TalkDraw.Point(x: 920, y: 180))
        #expect(!cards(plan).joined(separator: " ").contains("password"))
        let empty = ChatCountDraw.plan(writing: false, count: 0, countsOnly: false)
        #expect(cards(empty) == ["Chats", "None"])
        #expect(ChatCountAsk.line(writing: false, count: 0, countsOnly: false) == "No chats yet.")
        #expect(cards(ChatCountDraw.plan(writing: false, count: -1, countsOnly: false)) == ["Chats", "Can't"])
        #expect(ChatCountAsk.line(writing: false, count: -1, countsOnly: false) == "I can't read the chats.")
    }

    @Test func writingDrawsThePageWordUnlessTheAskIsTheCount() {
        let writing = ChatCountDraw.plan(writing: true, count: 4, countsOnly: false)
        #expect(cards(writing) == ["Chats", ChatCountAsk.writing])
        #expect(ChatCountAsk.line(writing: true, count: 4, countsOnly: false) == "Zeus is writing.")
        #expect(cards(ChatCountDraw.plan(writing: true, count: 4, countsOnly: true)) == ["Chats", "4"])
        #expect(ChatCountAsk.matches("how many chats"))
        #expect(ChatCountAsk.matches("Hey Zeus, how's chat?"))
        #expect(ChatCountAsk.wantsCount("how many conversations"))
        #expect(!ChatCountAsk.wantsCount("how's chat"))
        #expect(!ChatCountAsk.matches("what are my agents doing"))
        #expect(!ChatCountAsk.matches("is dictation on"))
        #expect(!ChatCountAsk.matches("is translation on"))
        #expect(!ChatCountAsk.matches("where's the sound going"))
    }
}
