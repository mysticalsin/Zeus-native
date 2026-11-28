import Testing
@testable import ZeusCore

struct ChatPaneDrawTests {
    private func cards(_ plan: ChatPaneDraw) -> [String] {
        plan.draw.marks.compactMap { mark in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
    }

    @Test func theWindowAndThePins() {
        let usual = ChatPaneDraw.plan(window: "Closed", pins: "0")
        #expect(cards(usual) == ["Pane", "Window: Closed", "Pins: 0"])
        #expect(ChatPaneAsk.line(window: "Closed", pins: "0") == "The chat window is closed, and no chats are pinned.")
        #expect(usual.boltCaption(at: 0) == "Pane")
        #expect(usual.boltCaption(at: ExplainBeatSchedule.gap * 2 + 0.001) == "Pins: 0")
        #expect(usual.guideBolt(at: ExplainBeatSchedule.gap * 2 + 0.001) == TalkDraw.Point(x: 920, y: 250))
        #expect(ChatPaneAsk.line(window: "Open", pins: "1") == "The chat window is open, and 1 chat is pinned.")
        #expect(ChatPaneAsk.line(window: "Closed", pins: "3") == "The chat window is closed, and 3 chats are pinned.")
        #expect(cards(ChatPaneDraw.plan(window: "Yes", pins: "0")) == ["Pane", "Can't"])
        #expect(ChatPaneAsk.line(window: "Open", pins: "1000") == "I can't read the chat window.")
    }

    @Test func theSavedCountStaysOffThisAsk() {
        #expect(ChatPaneAsk.matches("is the chat window open"))
        #expect(ChatPaneAsk.matches("Hey Zeus, how many chats are pinned?"))
        #expect(ChatPaneAsk.matches("are any chats pinned"))
        #expect(!ChatPaneAsk.matches("how many chats"))
        #expect(!ChatPaneAsk.matches("is chat history showing"))
        #expect(!ChatPaneAsk.matches("is a new chat open"))
        #expect(!ChatPaneAsk.matches("has zeus been taught about you"))
    }
}
