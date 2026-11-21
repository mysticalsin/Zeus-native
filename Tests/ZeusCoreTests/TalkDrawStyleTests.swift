import CoreGraphics
import Foundation
import Testing
@testable import ZeusCore

/// Drawing styles the existing canvas already paints: a ring, an arrow, an underline, a label and a path.
@Suite struct TalkDrawStyleTests {
    private static func shot() -> ScreenShot {
        ScreenShot(jpegData: Data(), label: "screen", pixelWidth: 1280, pixelHeight: 800,
                   displayFrame: CGRect(x: 0, y: 0, width: 1280, height: 800))
    }

    /// One mark of each canvas style. The path belongs to sentence 2; the others belong to sentence 0.
    private static let fixtureMarks = """
    {"k":"ring","x":120,"y":90,"r":16,"at":0},\
    {"k":"arrow","from":[40,40],"to":[200,120],"at":0},\
    {"k":"underline","from":[30,160],"to":[240,168],"at":0},\
    {"k":"label","x":80,"y":220,"t":"Save","at":0},\
    {"k":"path","pts":[[12,12],[40,48],[70,20]],"at":2}
    """

    private static func fixture() -> TalkDraw {
        TalkDrawParser.parse(#"{"s":1,"m":[\#(fixtureMarks)]}"#)!
    }

    @Test func aFixtureMarkListHasOneOfEachStyle() {
        let draw = Self.fixture()
        #expect(draw.marks.map(\.shape.style) == [.ring, .arrow, .underline, .label, .path])
        #expect(draw.marks.map(\.at) == [0, 0, 0, 0, 2])
        #expect(TalkDrawParser.parse(draw.json) == draw)
    }

    @Test func outOfRangePointsDrop() {
        let draw = TalkDrawParser.parse(#"""
        {"s":1,"m":[
        {"k":"ring","x":-1,"y":10,"r":8,"at":0},
        {"k":"arrow","from":[10,10],"to":[10,801],"at":0},
        {"k":"underline","from":[1281,20],"to":[1300,20],"at":0},
        {"k":"path","pts":[[1,1],[2,2],[-4,3]],"at":0},
        {"k":"ring","x":20,"y":20,"r":8,"at":0}
        ]}
        """#)!
        let kept = TalkDrawScene.objects(draw, shot: Self.shot(), captureID: UUID()).values.flatMap { $0 }
        #expect(kept.count == 1)
        #expect(kept[0].geometry.kind == .ring)
        #expect(kept[0].transform.position.x == 20 && kept[0].transform.position.y == 20)
    }

    @Test func aCardClampsInsideTheShot() {
        let draw = TalkDrawParser.parse(#"""
        {"s":1,"m":[
        {"k":"card","x":1275,"y":2,"t":"Export as PDF","at":0},
        {"k":"card","x":-40,"y":900,"t":"Save","at":0}
        ]}
        """#)!
        let cards = TalkDrawScene.frame(draw, shot: Self.shot(), captureID: UUID(), sentence: 0, reduceMotion: true).objects
        #expect(cards.count == 2)
        for card in cards {
            #expect(card.geometry.kind == .label)
            let size = TalkDrawScene.estimatedLabelSize(text: card.text ?? "")
            let p = card.transform.position
            #expect(p.x >= 0 && p.x + size.width <= 1280)
            #expect(p.y - size.height / 2 >= 0 && p.y + size.height / 2 <= 800)
        }
    }

    @Test func underReducedMotionRevealIsOneAndDurationIsZero() {
        let frame = TalkDrawScene.frame(Self.fixture(), shot: Self.shot(), captureID: UUID(), sentence: 0, reduceMotion: true)
        #expect(frame.reveal == 1)
        #expect(frame.duration == 0)
        #expect(!frame.objects.isEmpty)
        #expect(frame.objects.allSatisfy { $0.reveal == 1 })
    }

    @Test func aMarkForSentenceTwoIsNotInTheFrameForSentenceZero() {
        let shot = Self.shot()
        let draw = Self.fixture()
        let id = UUID()
        let sentenceZero = TalkDrawScene.frame(draw, shot: shot, captureID: id, sentence: 0, reduceMotion: true)
        let kinds = Set(sentenceZero.objects.map(\.geometry.kind))
        #expect(kinds == [.ring, .arrow, .underline, .label])
        #expect(!kinds.contains(.path))
        let sentenceTwo = TalkDrawScene.frame(draw, shot: shot, captureID: id, sentence: 2, reduceMotion: true)
        #expect(sentenceTwo.objects.map(\.geometry.kind) == [.path])
        #expect(sentenceTwo.objects.allSatisfy { $0.captureID == id && $0.space == .capture })
    }

    @Test func anUnknownStyleDrops() {
        #expect(TalkDrawParser.parse(#"{"m":[{"k":"shader","x":1,"y":2},{"k":"script"},{"k":"photo"},{"k":"image","url":"https://example.invalid/a.png"}]}"#) == nil)
        let kept = TalkDrawParser.parse(#"""
        {"m":[{"k":"shader"},{"k":"ring","x":10,"y":10,"r":6,"url":"https://example.invalid/a.png"},{"k":"underline","from":[4,4],"to":[20,6]}]}
        """#)
        #expect(kept?.marks.count == 1)
        #expect(kept?.marks[0].shape.style == .underline)
    }

    @Test func atMostSixMarks() {
        let underline = #"{"k":"underline","from":[1,1],"to":[8,4],"at":0}"#
        let many = TalkDrawParser.parse(#"{"m":[\#(Array(repeating: underline, count: 8).joined(separator: ","))]}"#)
        #expect(many?.marks.count == TalkDraw.maxMarks)
        #expect(many?.marks.count == 6)
        #expect(many?.marks.allSatisfy { $0.shape.style == .underline } == true)
    }
}
