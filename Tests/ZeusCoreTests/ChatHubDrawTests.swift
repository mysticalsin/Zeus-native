import Testing
@testable import ZeusCore

struct ChatHubDrawTests {
    private func cards(_ plan: ChatHubDraw) -> [String] {
        plan.draw.marks.compactMap { mark in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
    }

    @Test func historyAndANewChat() {
        let usual = ChatHubDraw.plan(history: "Off", fresh: "Off")
        #expect(cards(usual) == ["Hub", "History: Off", "New: Off"])
        #expect(ChatHubAsk.line(history: "Off", fresh: "Off") == "Chat history is hidden, and a new chat is not open.")
        #expect(usual.boltCaption(at: 0) == "Hub")
        #expect(usual.boltCaption(at: ExplainBeatSchedule.gap * 2 + 0.001) == "New: Off")
        #expect(usual.guideBolt(at: ExplainBeatSchedule.gap * 2 + 0.001) == TalkDraw.Point(x: 920, y: 250))
        #expect(ChatHubAsk.line(history: "On", fresh: "Off") == "Chat history is showing, and a new chat is not open.")
        #expect(ChatHubAsk.line(history: "Off", fresh: "On") == "Chat history is hidden, and a new chat is open.")
        #expect(cards(ChatHubDraw.plan(history: "Yes", fresh: "Off")) == ["Hub", "Can't"])
        #expect(ChatHubAsk.line(history: "On", fresh: "Maybe") == "I can't read the chat hub.")
    }

    @Test func theChatCountStaysOffThisAsk() {
        #expect(ChatHubAsk.matches("is chat history showing"))
        #expect(ChatHubAsk.matches("Hey Zeus, is a new chat open?"))
        #expect(ChatHubAsk.matches("which chat view is open"))
        #expect(!ChatHubAsk.matches("how many chats"))
        #expect(!ChatHubAsk.matches("chat history"))
        #expect(!ChatHubAsk.matches("which chat model"))
        #expect(!ChatHubAsk.matches("is memory learning on"))
    }
}
