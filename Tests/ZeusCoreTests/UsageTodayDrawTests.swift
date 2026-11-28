import Testing
@testable import ZeusCore

struct UsageTodayDrawTests {
    private func cards(_ plan: UsageTodayDraw) -> [String] {
        plan.draw.marks.compactMap { mark in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
    }

    @Test func oneAgentDrawsTheNameThenTodaysTokens() throws {
        let word = try #require(UsageTodayAsk.countWord(1_200))
        let facts = [UsageTodayFact(name: "Claude Code", today: 1_200, hasData: true)]
        let plan = UsageTodayDraw.plan(facts: facts)
        #expect(word == String(format: "%.1fk", 1.2))
        #expect(cards(plan) == ["Usage", "Claude Code", word])
        #expect(UsageTodayAsk.line(facts: facts) == "Claude Code used \(word) tokens today.")
        #expect(plan.boltCaption(at: 0) == "Usage")
        #expect(plan.boltCaption(at: ExplainBeatSchedule.gap) == "Claude Code")
        #expect(plan.boltCaption(at: ExplainBeatSchedule.gap * 2) == word)
        #expect(plan.guideBolt(at: ExplainBeatSchedule.gap * 2) == TalkDraw.Point(x: 920, y: 250))
        #expect(cards(UsageTodayDraw.plan(facts: [])) == ["Usage", "Can't"])
        #expect(UsageTodayAsk.line(facts: []) == "I can't read usage yet.")
        #expect(UsageTodayAsk.countWord(-1) == nil)
        #expect(UsageTodayAsk.countWord(980) == "980")
        #expect(UsageTodayAsk.countWord(100_000) == String(format: "%.0fk", 100.0))
        #expect(UsageTodayAsk.countWord(1_500_000) == String(format: "%.1fM", 1.5))
    }

    @Test func severalAgentsNameTheBusiestAndLeaveTheCostOff() throws {
        let facts = [
            UsageTodayFact(name: "Claude Code", today: 1_200, hasData: true),
            UsageTodayFact(name: "Codex", today: 9_000, hasData: true),
        ]
        let word = try #require(UsageTodayAsk.countWord(9_000))
        let plan = UsageTodayDraw.plan(facts: facts)
        #expect(cards(plan) == ["Usage", "2", "Codex", word])
        #expect(UsageTodayAsk.line(facts: facts) == "2 agents. Codex used \(word) tokens today.")
        #expect(plan.boltCaption(at: ExplainBeatSchedule.gap * 3 + 0.001) == word)
        let quiet = [
            UsageTodayFact(name: "Claude Code", today: 0, hasData: false),
            UsageTodayFact(name: "Codex", today: 0, hasData: false),
        ]
        #expect(cards(UsageTodayDraw.plan(facts: quiet)) == ["Usage", "None"])
        #expect(UsageTodayAsk.line(facts: quiet) == "No sessions this week.")
        #expect(UsageTodayAsk.cardName("Claude\nCode") == "Claude Code")
        #expect(UsageTodayAsk.matches("how much did I use today"))
        #expect(UsageTodayAsk.matches("Hey Zeus, what's my usage?"))
        #expect(UsageTodayAsk.matches("how's my usage"))
        #expect(!UsageTodayAsk.matches("how many words today"))
        #expect(!UsageTodayAsk.matches("how many screens"))
        #expect(!UsageTodayAsk.matches("are my earbuds connected"))
        #expect(!UsageTodayAsk.matches("how much time is left"))
        #expect(!UsageTodayAsk.matches("what's playing"))
    }
}
