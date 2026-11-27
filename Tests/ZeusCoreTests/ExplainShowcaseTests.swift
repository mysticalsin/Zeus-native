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

    @Test func theBoltCaptionFollowsTheSpokenBeat() throws {
        let still = try #require(ExplainShowcase.plan(for: "explain how photosynthesis works"))
        let first = still.boltCaption(at: 0)
        let second = still.boltCaption(at: ExplainBeatSchedule.gap)
        let third = still.boltCaption(at: ExplainBeatSchedule.gap * 2)
        #expect(first != second)
        #expect(second != third)
        #expect(first.count <= 40)
        #expect(second.count <= 40)
        #expect(third.count <= 40)
        #expect(still.sentences[0].hasPrefix(first))
        #expect(still.sentences[1].hasPrefix(second))
        #expect(still.sentences[2].hasPrefix(third))
        #expect(still.boltCaption(at: .nan) == first)
        #expect(still.boltCaption(at: -1) == first)
        let moving = try #require(ExplainShowcase.plan(for: "explain how the Tesla car can fly"))
        #expect(moving.boltCaption(at: 0) == moving.boltCaption(at: .nan))
        #expect(moving.sentences[0].hasPrefix(moving.boltCaption(at: 0)))
        let later = moving.boltCaption(at: ExplainBeatSchedule.gap * 4)
        #expect(later != moving.boltCaption(at: 0))
        #expect(moving.sentences.contains { $0.hasPrefix(later) })
    }

    @Test func anExplainHowItWorksNamesTheThingAndDrawsTheChange() throws {
        let showcase = try #require(ExplainShowcase.plan(for: "explain how photosynthesis works"))
        #expect(showcase.sentences[0] == "You asked about photosynthesis.")
        #expect(showcase.sentences[1] == "Next is how photosynthesis works.")
        #expect(showcase.sentences[2].contains("does not prove that the end happens"))
        #expect(!showcase.explanation.lowercased().contains("question"))
        let cards = showcase.draw.marks.compactMap { mark -> String? in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
        #expect(cards.contains("photosynthesis"))
        #expect(cards.contains("works?"))
        #expect(!cards.contains("question?"))
        let walk = try #require(ExplainShowcase.plan(for: "walk me through sharing this window"))
        #expect(walk.sentences[0] == "You asked about sharing this window.")
        #expect(!walk.explanation.lowercased().contains("question"))
    }

    @Test func aDrawingStillAppearsWhenSpeechIsOff() {
        #expect(TalkDrawReveal.sentenceReady(index: 0, speak: false, drawingReady: true) == 0)
        #expect(TalkDrawReveal.sentenceReady(index: 2, speak: false, drawingReady: true) == 2)
        #expect(TalkDrawReveal.sentenceReady(index: 0, speak: false, drawingReady: false) == nil)
        #expect(TalkDrawReveal.sentenceReady(index: 1, speak: true, drawingReady: true) == nil)
        #expect(TalkDrawReveal.sentenceReady(index: -1, speak: false, drawingReady: true) == nil)
        #expect(TalkDrawReveal.catchUp(spokenSentences: 0) == [])
        #expect(TalkDrawReveal.catchUp(spokenSentences: -3) == [])
        #expect(TalkDrawReveal.catchUp(spokenSentences: 3) == [0, 1, 2])
    }

    @Test func aStillQuestionDrawsTheBoxOneSideAtATime() throws {
        let showcase = try #require(ExplainShowcase.plan(for: "explain how photosynthesis works"))
        #expect(showcase.travels == false)
        #expect(showcase.stroke.count == 5)
        let opening = try #require(showcase.builtFrame(at: 0))
        let early = inkPoints(opening)
        #expect(early.count == 2)
        #expect(early == Array(showcase.stroke.prefix(2)))
        #expect(hasShape(opening, ring: true))
        #expect(!hasShape(opening, arrow: true))
        let closed = try #require(showcase.builtFrame(at: ExplainBeatSchedule.gap))
        #expect(inkPoints(closed) == showcase.stroke)
        #expect(hasShape(closed, arrow: true))
        #expect(!cardTexts(closed).contains("works?"))
        let last = try #require(showcase.builtFrame(at: ExplainBeatSchedule.gap * 2))
        #expect(inkPoints(last) == showcase.stroke)
        #expect(cardTexts(last).contains("works?"))
        let broken = try #require(showcase.builtFrame(at: .nan))
        #expect(inkPoints(broken).count == 2)
        #expect(!hasShape(broken, arrow: true))
        #expect(showcase.builtInkCount(at: -1) == 2)
        let moving = try #require(ExplainShowcase.plan(for: Self.tesla))
        #expect(moving.builtFrame(at: 0) == nil)
        #expect(moving.builtInkCount(at: 0) == 0)
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

    @Test func aNonFiniteExplainTimeStaysOnTheFirstBeat() throws {
        let showcase = try #require(ExplainShowcase.plan(for: "explain how photosynthesis works"))
        let first = try #require(showcase.guideBolt(at: 0))
        #expect(showcase.guideBolt(at: .infinity) == first)
        #expect(showcase.guideBolt(at: -.infinity) == first)
        #expect(showcase.guideBolt(at: .nan) == first)
        let schedule = ExplainBeatSchedule(indexes: [0, 1, 2])
        #expect(schedule.revealed(at: .nan) == [0])
        #expect(schedule.revealed(at: .infinity) == [0])
        #expect(schedule.revealed(at: -1) == [0])
        let huge = ExplainBeatSchedule.gap * 10_000
        #expect(schedule.revealed(at: huge) == [0, 1, 2])
    }

    @Test func aNonFiniteMarkDoesNotMoveTheBolt() {
        let broken = TalkDraw.Mark(shape: .ring(center: .init(x: .nan, y: 12), radius: 8), at: 0)
        let card = TalkDraw.Mark(shape: .card(origin: .init(x: 40, y: 50), text: "Here"), at: 0)
        let draw = TalkDraw(screen: 1, marks: [broken, card])
        let showcase = ExplainShowcase(
            sentences: ["Here."], draw: draw, travels: false, schedule: ExplainBeatSchedule(indexes: [0]))
        #expect(showcase.guideBolt(at: 0) == TalkDraw.Point(x: 40, y: 50))
        let only = ExplainShowcase(
            sentences: ["Here."],
            draw: TalkDraw(screen: 1, marks: [broken]),
            travels: false,
            schedule: ExplainBeatSchedule(indexes: [0]))
        #expect(only.guideBolt(at: 0) == nil)
    }

    @Test func aRingWithNoSizeDoesNotTakeTheBolt() {
        let card = TalkDraw.Mark(shape: .card(origin: .init(x: 40, y: 50), text: "Here"), at: 0)
        for radius in [0.0, -4, .nan, .infinity] {
            let ring = TalkDraw.Mark(shape: .ring(center: .init(x: 10, y: 12), radius: radius), at: 0)
            let showcase = ExplainShowcase(
                sentences: ["Here."],
                draw: TalkDraw(screen: 1, marks: [ring, card]),
                travels: false,
                schedule: ExplainBeatSchedule(indexes: [0]))
            #expect(showcase.guideBolt(at: 0) == TalkDraw.Point(x: 40, y: 50))
        }
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
        #expect(ExplainShowcase.pixelSize(width: 100.4, height: 0.2, scale: 2) == (width: 201, height: 1))
        #expect(ExplainShowcase.pixelSize(width: 10, height: 10, scale: 0.5) == (width: 10, height: 10))
        #expect(ExplainShowcase.pixelSize(width: .nan, height: .infinity, scale: .nan) == (width: 1, height: Int(Int32.max)))
        #expect(ExplainShowcase.pixelSize(width: -.infinity, height: 0, scale: 2) == (width: 1, height: 1))
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

    private func inkPoints(_ draw: TalkDraw) -> [TalkDraw.Point] {
        for mark in draw.marks {
            if case .ink(let points) = mark.shape { return points }
        }
        return []
    }

    private func hasShape(_ draw: TalkDraw, ring: Bool = false, arrow: Bool = false) -> Bool {
        draw.marks.contains { mark in
            switch mark.shape {
            case .ring: return ring
            case .arrow: return arrow
            default: return false
            }
        }
    }

    private func cardTexts(_ draw: TalkDraw) -> [String] {
        draw.marks.compactMap { mark in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
    }
}
