import Foundation
import Testing
@testable import ZeusCore

@Suite struct ExplainShowcaseTests {
    private static let tesla = "explain how the Tesla car can fly"

    @Test func anExplainRequestProducesWordsAndAShowcasePlan() throws {
        let showcase = try #require(ExplainShowcase.plan(for: Self.tesla))
        #expect(!showcase.explanation.isEmpty)
        #expect(showcase.sentences.count == 3)
        #expect(showcase.explanation.contains("closed box"))
        #expect(showcase.explanation.contains("arrow"))
        #expect(showcase.explanation.contains("does not show that it happens"))
        #expect(showcase.draw.marks.count == 5)
        #expect(TalkDrawParser.parse(showcase.draw.json) == showcase.draw)
        #expect(Set(showcase.draw.marks.map(\.at)) == [0, 1, 2])
        let figure = showcase.draw.marks.filter { $0.at == 0 }
        #expect(figure.contains { if case .ink = $0.shape { return true }; return false })
        #expect(figure.contains { if case .ring = $0.shape { return true }; return false })
        #expect(showcase.draw.marks.contains { mark in
            if case .arrow = mark.shape { return mark.at == 1 }
            return false
        })
        #expect(showcase.draw.marks.contains { mark in
            if case .card = mark.shape { return mark.at == 2 }
            return false
        })
    }

    @Test func theTeslaLineDrawsTheFigureBeforeTheArrow() throws {
        let showcase = try #require(ExplainShowcase.plan(for: Self.tesla))
        guard case .ink(let points) = showcase.draw.marks.first(where: {
            if case .ink = $0.shape { return $0.at == 0 }
            return false
        })?.shape else {
            Issue.record("beat 0 has no ink")
            return
        }
        #expect(points.count >= 4)
        #expect(points.first == points.last)
        let arrowIndex = try #require(showcase.draw.marks.firstIndex { if case .arrow = $0.shape { return true }; return false })
        let inkIndex = try #require(showcase.draw.marks.firstIndex { if case .ink = $0.shape { return true }; return false })
        #expect(inkIndex < arrowIndex)
        #expect(showcase.draw.marks[inkIndex].at < showcase.draw.marks[arrowIndex].at)
    }

    @Test func theTeslaRequestNamesTheAskAndDoesNotClaimFlight() throws {
        let showcase = try #require(ExplainShowcase.plan(for: "Explain how the Tesla car can fly."))
        let spoken = showcase.explanation.lowercased()
        #expect(spoken.contains("tesla car"))
        #expect(spoken.contains("the asked end is fly"))
        #expect(spoken.contains("does not show that it happens"))
        #expect(!spoken.contains("it flies"))
        #expect(!spoken.contains("cars fly"))
        #expect(!spoken.contains("can fly"))
        guard case .card(_, let text) = showcase.draw.marks.last?.shape else {
            Issue.record("the asked end is not on a card")
            return
        }
        #expect(text == "fly?")
        #expect(showcase.draw.marks.last?.at == 2)
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
        #expect(abs(center.x - 160) < 0.001)
        #expect(abs(center.y - 160) < 0.001)
        #expect(radius <= TalkDraw.maxRingRadius)
        #expect(radius >= TalkDraw.minRingRadius)
        guard case .ink(let points) = fitted.marks.first(where: {
            if case .ink = $0.shape { return true }
            return false
        })?.shape else {
            Issue.record("scaled plan lost the ink")
            return
        }
        #expect(abs(points[0].x - 90) < 0.001)
        #expect(abs(points[0].y - 110) < 0.001)
        for mark in fitted.marks {
            switch mark.shape {
            case .ring(let center, _):
                #expect(center.x >= 0 && center.x <= 640 && center.y >= 0 && center.y <= 360)
            case .arrow(let from, let to):
                #expect(from.x >= 0 && from.x <= 640 && to.x <= 640 && to.y >= 0 && to.y <= 360)
            case .card(let origin, let text):
                #expect(origin.x >= 0 && origin.y >= 0 && !text.isEmpty)
            case .ink(let stroke):
                #expect(stroke.allSatisfy { $0.x >= 0 && $0.x <= 640 && $0.y >= 0 && $0.y <= 360 })
            }
        }
    }
}
