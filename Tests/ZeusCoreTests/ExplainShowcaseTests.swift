import Foundation
import Testing
@testable import ZeusCore

@Suite struct ExplainShowcaseTests {
    private static let tesla = "explain how the Tesla car can fly"

    @Test func anExplainRequestProducesWordsAndAShowcasePlan() throws {
        let plan = ExplainShowcase.plan(for: Self.tesla)
        #expect(plan != nil)
        let showcase = try #require(plan)
        #expect(!showcase.explanation.isEmpty)
        #expect(showcase.sentences.count == 3)
        #expect(showcase.explanation.contains("illustration"))
        #expect(showcase.explanation.contains("not a sourced claim"))
        #expect(showcase.draw.marks.count == 4)
        #expect(TalkDrawParser.parse(showcase.draw.json) == showcase.draw)
        let sentences = Set(showcase.draw.marks.map(\.at))
        #expect(sentences == [0, 1, 2])
        #expect(showcase.draw.marks.contains { mark in
            if case .ring = mark.shape { return mark.at == 1 }
            return false
        })
        #expect(showcase.draw.marks.contains { mark in
            if case .arrow = mark.shape { return mark.at == 1 }
            return false
        })
    }

    @Test func theTeslaRequestIsQuotedAndNotClaimedAsFlight() throws {
        let showcase = try #require(ExplainShowcase.plan(for: "Explain how the Tesla car can fly."))
        let spoken = showcase.explanation.lowercased()
        #expect(spoken.contains("tesla"))
        #expect(spoken.contains("you asked:"))
        #expect(spoken.contains("not a sourced claim"))
        #expect(!spoken.contains("it flies"))
        #expect(!spoken.contains("cars fly"))
        guard case .card(_, let text) = showcase.draw.marks.last?.shape else {
            Issue.record("the question is not on a card")
            return
        }
        #expect(text.contains("tesla"))
        #expect(text.count <= TalkDraw.maxTextCharacters)
    }

    @Test func aCommandOrABareExplainProducesNoShowcase() {
        #expect(ExplainShowcase.plan(for: "what time is it") == nil)
        #expect(ExplainShowcase.plan(for: "open Safari") == nil)
        #expect(ExplainShowcase.plan(for: "explain") == nil)
        #expect(ExplainShowcase.plan(for: "") == nil)
        #expect(ExplainShowcase.blocksModelRace("what time is it") == false)
        #expect(ExplainShowcase.blocksModelRace("explain") == true)
        #expect(ExplainShowcase.blocksModelRace(Self.tesla) == true)
    }

    @Test func thePlanScalesOntoTheCanvasThePresenterAlreadyUses() throws {
        let showcase = try #require(ExplainShowcase.plan(for: Self.tesla))
        let fitted = showcase.scaled(toWidth: 640, toHeight: 360)
        #expect(fitted.marks.count == showcase.draw.marks.count)
        guard case .ring(let center, let radius) = fitted.marks.first(where: {
            if case .ring = $0.shape { return true }
            return false
        })?.shape else {
            Issue.record("scaled plan lost the ring")
            return
        }
        #expect(abs(center.x - 320) < 0.001)
        #expect(abs(center.y - 180) < 0.001)
        #expect(radius <= TalkDraw.maxRingRadius)
        #expect(radius >= TalkDraw.minRingRadius)
        for mark in fitted.marks {
            switch mark.shape {
            case .ring(let center, _):
                #expect(center.x >= 0 && center.x <= 640 && center.y >= 0 && center.y <= 360)
            case .arrow(let from, let to):
                #expect(from.x >= 0 && from.x <= 640 && to.y >= 0 && to.y <= 360)
            case .card(let origin, let text):
                #expect(origin.x >= 0 && origin.y >= 0 && !text.isEmpty)
            case .ink:
                break
            }
        }
    }
}
