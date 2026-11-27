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
        #expect(TalkDrawParser.parse(#"{"m":[{"k":"ring","x":true,"y":2,"r":8,"at":1}]}"#) == nil)
        #expect(TalkDrawParser.parse(#"{"m":[{"k":"ring","x":false,"y":2,"r":8}]}"#) == nil)
    }

    @Test func anExplainRequestProducesWordsAndAShowcasePlan() throws {
        let showcase = try #require(ExplainShowcase.plan(for: Self.tesla))
        #expect(showcase.sentences.count == 3)
        #expect(showcase.travels)
        #expect(showcase.explanation.contains("upward force greater than its weight"))
        #expect(showcase.explanation.contains("No source is on file"))
        #expect(showcase.explanation.contains("does not prove that the end happens"))
        #expect(showcase.stroke.count >= 4)
        #expect(showcase.draw.marks.count == 4)
        #expect(TalkDrawParser.parse(showcase.draw.json) == showcase.draw)
        let first = try #require(showcase.penFrame(at: 0))
        #expect(first.pointCount == 2)
        #expect(first.bolt == showcase.stroke[1])
        #expect(first.finished == false)
    }

    @Test func theTeslaLineTravelsAnOpenStroke() throws {
        let showcase = try #require(ExplainShowcase.plan(for: Self.tesla))
        #expect(showcase.stroke.first != showcase.stroke.last)
        let start = try #require(showcase.penFrame(at: 0))
        let next = try #require(showcase.penFrame(at: ExplainBeatSchedule.gap))
        guard case .ink(let early) = start.draw.marks.first(where: { if case .ink = $0.shape { return true }; return false })?.shape,
              case .ink(let later) = next.draw.marks.first(where: { if case .ink = $0.shape { return true }; return false })?.shape else {
            Issue.record("pen frames have no ink")
            return
        }
        #expect(early.count == 2)
        #expect(later.count == early.count + 1)
        #expect(later.starts(with: early))
        #expect(start.bolt == early.last)
        #expect(next.bolt == later.last)
    }

    @Test func beatsStayOnEarlierMarksUntilTheirTime() throws {
        let showcase = try #require(ExplainShowcase.plan(for: Self.tesla))
        #expect(ExplainBeatSchedule.gap == 0.7)
        let quiet = try #require(showcase.penFrame(at: 0.8))
        let voiced = try #require(showcase.penFrame(at: 0.8, audioStarts: [0, 2, 4]))
        #expect(quiet.pointCount == 3)
        #expect(voiced.pointCount == 2)
        #expect(voiced.pointCount < quiet.pointCount)
        #expect(showcase.penFrame(at: 0)?.finished == false)
    }

    @Test func theTeslaRequestNamesTheMechanismAndDoesNotClaimFlight() throws {
        let showcase = try #require(ExplainShowcase.plan(for: "Explain how the Tesla car can fly."))
        let spoken = showcase.explanation.lowercased()
        #expect(spoken.contains("tesla car"))
        #expect(spoken.contains("upward force"))
        #expect(spoken.contains("no source is on file"))
        #expect(spoken.contains("wing or a rotor"))
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

    @Test func aStillExplainMovesTheBoltWithEachBeat() throws {
        let showcase = try #require(ExplainShowcase.plan(for: "explain how photosynthesis works"))
        #expect(showcase.travels == false)
        let first = try #require(showcase.guideBolt(at: 0))
        #expect(first == TalkDraw.Point(x: 320, y: 320))
        let second = try #require(showcase.guideBolt(at: ExplainBeatSchedule.gap))
        #expect(second == TalkDraw.Point(x: 690, y: 320))
        let third = try #require(showcase.guideBolt(at: ExplainBeatSchedule.gap * 2))
        #expect(third == TalkDraw.Point(x: 920, y: 280))
        #expect(first != second && second != third)
    }

    @Test func aMovingExplainKeepsTheBoltOnThePenTip() throws {
        let showcase = try #require(ExplainShowcase.plan(for: Self.tesla))
        let frame = try #require(showcase.penFrame(at: 0))
        #expect(showcase.guideBolt(at: 0) == frame.bolt)
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
        #expect(abs(center.x - 520) < 0.001)
        #expect(abs(center.y - 100) < 0.001)
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
