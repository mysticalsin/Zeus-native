import Testing
@testable import ZeusCore

struct SecretFieldDrawTests {
    @Test func aPasswordFieldIsLeftForYou() throws {
        let spoken = "That's a password or payment field, so I left it."
        let plan = try #require(SecretFieldDraw.from(line: spoken))
        func cards(_ plan: SecretFieldDraw) -> [String] {
            plan.draw.marks.compactMap { mark in
                if case .card(_, let text) = mark.shape { return text }
                return nil
            }
        }
        #expect(cards(plan) == ["Secret", "You"])
        #expect(plan.boltCaption(at: 0) == "Secret")
        #expect(plan.boltCaption(at: 100) == "You")
        #expect(plan.guideBolt(at: 0) == TalkDraw.Point(x: 320, y: 320))
        #expect(plan.guideBolt(at: ExplainBeatSchedule.gap) == TalkDraw.Point(x: 920, y: 180))
        #expect(SecretFieldDraw.from(line: "That's a password or payment field. Please type it yourself.") != nil)
        #expect(SecretFieldDraw.from(line: "That's a password or payment field, so I left it for you. Type it yourself and tell me when to carry on.") != nil)
    }

    @Test func otherStopsAreNotASecretField() {
        #expect(SecretFieldDraw.from(line: "") == nil)
        #expect(SecretFieldDraw.from(line: "Okay, I didn't type anything.") == nil)
        #expect(SecretFieldDraw.from(line: "That's it, you're done.") == nil)
        #expect(SecretFieldDraw.from(line: "I'm stuck: the login form.") == nil)
    }
}
