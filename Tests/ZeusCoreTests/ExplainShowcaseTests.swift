import Foundation
import Testing
@testable import ZeusCore

@Suite struct ExplainShowcaseTests {
    private static let tesla = "explain how the Tesla car can fly"

    @Test func sentenceIndexOneIsNotDroppedAsABoolean() throws {
        let parsed = try #require(TalkDrawParser.parse(
            #"{"s":1,"m":[{"k":"ring","x":10,"y":20,"r":8,"at":1},{"k":"card","x":30,"y":40,"t":"weight","at":0},{"k":"ink","pts":[[1,2],[3,4]],"at":2}]}"#
        ))
        #expect(parsed.marks.map(\.at) == [1, 0, 2])
        guard case .ring(_, let radius) = parsed.marks[0].shape else {
            Issue.record("index 1 was not the ring")
            return
        }
        #expect(radius == 8)
    }

    @Test func anExplainRequestProducesWordsAndAShowcasePlan() throws {
        let showcase = try #require(ExplainShowcase.plan(for: Self.tesla))
        #expect(showcase.sentences.count == 3)
        #expect(showcase.travels)
        #expect(showcase.explanation.contains("Weight holds"))
        #expect(showcase.explanation.contains("Lift would have to exceed"))
        #expect(showcase.explanation.contains("does not prove that the end happens"))
        #expect(showcase.draw.marks.count == 6)
        #expect(TalkDrawParser.parse(showcase.draw.json) == showcase.draw)
        #expect(showcase.schedule.indexes == [0, 1, 2])
        #expect(Set(showcase.draw.marks.map(\.at)) == [0, 1, 2])
    }

    @Test func theTeslaLineTravelsAnOpenStroke() throws {
        let showcase = try #require(ExplainShowcase.plan(for: Self.tesla))
        let strokes: [(at: Int, points: [TalkDraw.Point])] = showcase.draw.marks.compactMap { mark in
            if case .ink(let points) = mark.shape { return (mark.at, points) }
            return nil
        }.sorted { $0.at < $1.at }
        #expect(strokes.map(\.at) == [0, 1, 2])
        #expect(strokes.allSatisfy { $0.points.first != $0.points.last })
        #expect(strokes[0].points.last == strokes[1].points.first)
        #expect(strokes[1].points.last == strokes[2].points.first)
        let all = strokes.flatMap(\.points)
        #expect(all.first != all.last)
    }

    @Test func beatsStayOnEarlierMarksUntilTheirTime() throws {
        let showcase = try #require(ExplainShowcase.plan(for: Self.tesla))
        let schedule = showcase.schedule
        #expect(ExplainBeatSchedule.gap == 0.7)
        #expect(schedule.revealed(at: 0) == [0])
        #expect(schedule.revealed(at: 0.2) == [0])
        #expect(schedule.revealed(at: 0.85) == [0, 1])
        #expect(schedule.revealed(at: 1.6) == [0, 1, 2])
        #expect(schedule.revealed(at: 0) != schedule.indexes)
    }

    @Test func theTeslaRequestNamesTheMechanismAndDoesNotClaimFlight() throws {
        let showcase = try #require(ExplainShowcase.plan(for: "Explain how the Tesla car can fly."))
        let spoken = showcase.explanation.lowercased()
        #expect(spoken.contains("tesla car"))
        #expect(spoken.contains("weight"))
        #expect(spoken.contains("lift"))
        #expect(spoken.contains("the asked end is fly"))
        #expect(spoken.contains("does not prove that the end happens"))
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
        #expect(ExplainShowcase.plan(for: "explain how photosynthesis works")?.travels == false)
        #expect(ExplainShowcase.blocksModelRace("what time is it") == false)
        #expect(ExplainShowcase.blocksModelRace("explain") == true)
        #expect(ExplainShowcase.blocksModelRace(Self.tesla) == true)
    }

    @Test func thePlanScalesOntoTheDisplayThePresenterUses() throws {
        let showcase = try #require(ExplainShowcase.plan(for: Self.tesla))
        let pixels = ExplainShowcase.pixelSize(width: 1440, height: 900, scale: 2)
        #expect(pixels.width == 2880)
        #expect(pixels.height == 1800)
        let fitted = showcase.scaled(toWidth: 640, toHeight: 360)
        #expect(fitted.marks.count == showcase.draw.marks.count)
        guard case .ink(let points) = fitted.marks.first(where: {
            if case .ink = $0.shape { return $0.at == 0 }
            return false
        })?.shape else {
            Issue.record("scaled plan lost the first stroke")
            return
        }
        #expect(abs(points[0].x - 100) < 0.001)
        #expect(abs(points[0].y - 250) < 0.001)
        guard case .ring(let center, let radius) = fitted.marks.first(where: {
            if case .ring = $0.shape { return true }
            return false
        })?.shape else {
            Issue.record("scaled plan lost the ring")
            return
        }
        #expect(abs(center.x - 100) < 0.001)
        #expect(abs(center.y - 250) < 0.001)
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
            case .ink(let stroke):
                #expect(stroke.allSatisfy { $0.x >= 0 && $0.x <= 640 && $0.y >= 0 && $0.y <= 360 })
            }
        }
    }
}
