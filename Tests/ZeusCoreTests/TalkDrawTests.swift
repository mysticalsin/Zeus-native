import CoreGraphics
import Foundation
import Testing
@testable import ZeusCore

@Suite struct TalkDrawTests {
    private static func shot(frame: CGRect, pixels: (Int, Int)) -> ScreenShot {
        ScreenShot(jpegData: Data(), label: "screen", pixelWidth: pixels.0, pixelHeight: pixels.1, displayFrame: frame)
    }

    private static func draw(_ marks: String, screen: Int = 1) -> TalkDraw {
        TalkDrawParser.parse(#"{"s":\#(screen),"m":[\#(marks)]}"#)!
    }

    // MARK: Limits

    @Test func theMarkCountInkPointsTextAndSentenceIndexAreLimited() {
        let ring = #"{"k":"ring","x":10,"y":10,"r":5,"at":0}"#
        let many = TalkDrawParser.parse(#"{"m":[\#(Array(repeating: ring, count: 9).joined(separator: ","))]}"#)
        #expect(many?.marks.count == TalkDraw.maxMarks)

        let points = (0..<40).map { "[\($0),\($0 + 1)]" }.joined(separator: ",")
        let ink = Self.draw(#"{"k":"ink","pts":[\#(points)],"at":1}"#)
        guard case .ink(let kept) = ink.marks[0].shape else { Issue.record("not ink"); return }
        #expect(kept.count == TalkDraw.maxInkPoints)

        let long = String(repeating: "x", count: 90)
        let card = Self.draw(#"{"k":"card","x":1,"y":2,"t":"\#(long)","at":12}"#)
        guard case .card(_, let text) = card.marks[0].shape else { Issue.record("not a card"); return }
        #expect(text.count == TalkDraw.maxTextCharacters)
        #expect(card.marks[0].at == TalkDraw.maxSentenceIndex)
    }

    @Test func aRingRadiusIsClampedSoOneMarkCannotCoverTheScreen() {
        let huge = Self.draw(#"{"k":"ring","x":10,"y":10,"r":5000}"#)
        guard case .ring(_, let radius) = huge.marks[0].shape else { Issue.record("not a ring"); return }
        #expect(radius == TalkDraw.maxRingRadius)
        let tiny = Self.draw(#"{"k":"ring","x":10,"y":10,"r":0.5}"#)
        guard case .ring(_, let small) = tiny.marks[0].shape else { Issue.record("not a ring"); return }
        #expect(small == TalkDraw.minRingRadius)
    }

    @Test func unknownIncompleteAndEmptyMarksAreDropped() {
        #expect(TalkDrawParser.parse(#"{"m":[{"k":"star","x":1,"y":2}]}"#) == nil)
        #expect(TalkDrawParser.parse(#"{"m":[{"k":"ring","x":1,"y":2}]}"#) == nil)
        #expect(TalkDrawParser.parse(#"{"m":[{"k":"ink","pts":[[1,2]]}]}"#) == nil)
        #expect(TalkDrawParser.parse(#"{"m":[{"k":"card","x":1,"y":2,"t":"  "}]}"#) == nil)
        #expect(TalkDrawParser.parse(#"{"m":[{"k":"ring","x":true,"y":2,"r":3}]}"#) == nil)
        let mixed = TalkDrawParser.parse(#"{"m":[{"k":"star"},{"k":"ring","x":1,"y":2,"r":3}]}"#)
        #expect(mixed?.marks.count == 1)
        #expect(mixed?.screen == 1)
    }

    @Test func theTagTextReadsBackAsTheSameDraw() {
        let draw = Self.draw(#"{"k":"ring","x":412,"y":88,"r":24,"at":0},{"k":"arrow","from":[600,300],"to":[430,100],"at":1},{"k":"ink","pts":[[1,2],[3,4]],"at":1},{"k":"card","x":440,"y":120,"t":"Export as PDF","at":2}"#, screen: 2)
        #expect(TalkDrawParser.parse(draw.json) == draw)
    }

    // MARK: Scene

    @Test func marksOutsideTheImageAreDroppedAndGroupedBySentence() {
        let shot = Self.shot(frame: CGRect(x: 0, y: 0, width: 1280, height: 800), pixels: (1280, 800))
        let draw = Self.draw("""
        {"k":"ring","x":100,"y":100,"r":20,"at":0},
        {"k":"ring","x":1281,"y":100,"r":20,"at":0},
        {"k":"arrow","from":[10,10],"to":[10,900],"at":1},
        {"k":"arrow","from":[10,10],"to":[200,300],"at":1},
        {"k":"ink","pts":[[1,1],[2,2],[-5,3]],"at":2},
        {"k":"ink","pts":[[1,1],[2,2],[5,3]],"at":2}
        """)
        let objects = TalkDrawScene.objects(draw, shot: shot, captureID: UUID())
        #expect(objects[0]?.count == 1)
        #expect(objects[1]?.count == 1)
        #expect(objects[2]?.count == 1)
        #expect(objects.keys.sorted() == [0, 1, 2])
        for object in objects.values.joined() {
            #expect(object.space == .capture)
            #expect(!object.accessibleDescription.isEmpty)
        }
    }

    @Test func aCardIsClampedInsideTheImage() {
        let shot = Self.shot(frame: CGRect(x: 0, y: 0, width: 1280, height: 800), pixels: (1280, 800))
        let draw = Self.draw(#"{"k":"card","x":1275,"y":2,"t":"Export as PDF"},{"k":"card","x":-40,"y":900,"t":"Save"}"#)
        let cards = TalkDrawScene.objects(draw, shot: shot, captureID: UUID())[0] ?? []
        #expect(cards.count == 2)
        for card in cards {
            #expect(card.geometry.kind == .card)
            let size = TalkDrawScene.estimatedLabelSize(text: card.text ?? "")
            let p = card.transform.position
            #expect(p.x >= 0 && p.x + size.width <= 1280)
            #expect(p.y >= 0 && p.y + size.height <= 800)
        }
    }

    @Test func aCardInsideTheImageIsLeftWhereItWas() {
        let shot = Self.shot(frame: CGRect(x: 0, y: 0, width: 1280, height: 800), pixels: (1280, 800))
        let card = TalkDrawScene.objects(Self.draw(#"{"k":"card","x":440,"y":120,"t":"Export as PDF"}"#), shot: shot, captureID: UUID())[0]?.first
        #expect(card?.transform.position.x == 440 && card?.transform.position.y == 120)
        #expect(card?.text == "Export as PDF")
    }

    // MARK: Mapping

    /// The drawn position, through the capture geometry, must land where `[POINT]` lands.
    private func expectMarksLandWherePointDoes(shots: [ScreenShot], screen: Int, scale: Double) throws {
        let shot = shots[screen - 1]
        let captureID = UUID()
        let geometry = try TalkDrawScene.geometry(shot: shot, displayID: UInt32(screen), backingScale: scale, captureID: captureID)
        let w = Double(shot.pixelWidth), h = Double(shot.pixelHeight)
        // Whole pixels: `[POINT]` is an integer tag, so both paths are fed the same values.
        let pixels = [(0.0, 0.0), ((w / 2).rounded(.down), (h / 2).rounded(.down)), (w - 1, h - 1), ((w * 0.31).rounded(.down), (h * 0.77).rounded(.down)), (412, 88)]
        for (x, y) in pixels {
            let draw = TalkDraw(screen: screen, marks: [.init(shape: .ring(center: .init(x: x, y: y), radius: 10), at: 0)])
            let ring = try #require(TalkDrawScene.objects(draw, shot: shot, captureID: captureID)[0]?.first)
            #expect(ring.captureID == captureID)
            let global = try #require(geometry.globalPoint(fromImage: ring.transform.position, current: geometry.display))
            let expected = try #require(PresentPointMapping.screenPoint(x: Int(x), y: Int(y), screen: screen, in: shots))
            #expect(abs(global.x - Double(expected.x)) < 0.01, "x for (\(x), \(y)) on \(shot.displayFrame)")
            #expect(abs(global.y - Double(expected.y)) < 0.01, "y for (\(x), \(y)) on \(shot.displayFrame)")
        }
    }

    @Test func marksLandWherePointDoesOnA1xDisplay() throws {
        let shots = [Self.shot(frame: CGRect(x: 0, y: 0, width: 1280, height: 800), pixels: (1280, 800))]
        try expectMarksLandWherePointDoes(shots: shots, screen: 1, scale: 1)
    }

    @Test func marksLandWherePointDoesOnA2xDisplay() throws {
        let shots = [Self.shot(frame: CGRect(x: 0, y: 0, width: 1440, height: 900), pixels: (2880, 1800))]
        try expectMarksLandWherePointDoes(shots: shots, screen: 1, scale: 2)
    }

    @Test func marksLandWherePointDoesOnADownscaledShot() throws {
        let shots = [Self.shot(frame: CGRect(x: 0, y: 0, width: 1728, height: 1117), pixels: (1280, 827))]
        try expectMarksLandWherePointDoes(shots: shots, screen: 1, scale: 2)
    }

    @Test func marksLandWherePointDoesOnASecondaryDisplayAtNegativeX() throws {
        let shots = [
            Self.shot(frame: CGRect(x: 0, y: 0, width: 1728, height: 1117), pixels: (1280, 827)),
            Self.shot(frame: CGRect(x: -1920, y: 40, width: 1920, height: 1080), pixels: (1280, 720)),
        ]
        try expectMarksLandWherePointDoes(shots: shots, screen: 2, scale: 1)
    }
}
