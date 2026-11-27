import Testing
@testable import ZeusCore

struct EndpointMissDrawTests {
    @Test func anEndpointZeusCouldNotUseShowsWhy() throws {
        let setup = try #require(EndpointMissDraw.from(line: "The Any LLM endpoint isn't set up."))
        let silent = try #require(EndpointMissDraw.from(line: "The Any LLM endpoint didn't answer."))
        func cards(_ plan: EndpointMissDraw) -> [String] {
            plan.draw.marks.compactMap { mark in
                if case .card(_, let text) = mark.shape { return text }
                return nil
            }
        }
        #expect(cards(setup) == ["Endpoint", "Setup"])
        #expect(setup.boltCaption(at: 0) == "Endpoint")
        #expect(setup.boltCaption(at: 100) == "Setup")
        #expect(setup.guideBolt(at: 0) == TalkDraw.Point(x: 320, y: 320))
        #expect(setup.guideBolt(at: ExplainBeatSchedule.gap) == TalkDraw.Point(x: 920, y: 180))
        #expect(cards(silent) == ["Endpoint", "No answer"])
        #expect(silent.boltCaption(at: 100) == "No answer")
    }

    @Test func aMissingVaultAndAMissingAIAreNotThisEndpoint() {
        #expect(EndpointMissDraw.from(line: "") == nil)
        #expect(EndpointMissDraw.from(line: "I looked in your vault and didn't find notes about tides.") == nil)
        #expect(EndpointMissDraw.from(line: "no AI is connected. Connect one in Settings, Integrations.") == nil)
        #expect(EndpointMissDraw.from(line: "the separate browser isn't set up yet. Open Settings, Features.") == nil)
        #expect(EndpointMissDraw.from(line: "The AI failed; try again.") == nil)
        #expect(EndpointMissDraw.from(line: "No AI answered in time; try again.") == nil)
    }
}
