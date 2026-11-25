import Foundation
import Testing
@testable import ZeusCore

@Suite("Drawing paints its first sentence on arrival")
struct DrawingPaintLeadTests {
    @Test func theEarliestSentenceIsDueAndLaterSentencesWait() {
        #expect(DrawingPaintLead.sentenceDueOnArrival([2, 0, 5]) == 0)
        #expect(DrawingPaintLead.sentenceDueOnArrival([3, 1]) == 1)
    }

    @Test func aDrawWithNoSentenceHasNothingDue() {
        #expect(DrawingPaintLead.sentenceDueOnArrival([Int]()) == nil)
    }
}

@Suite("Pointer box leads speech")
struct PointerBoxLeadTests {
    @Test func aCaptureRingForThisCaptureIsTheBox() {
        let capture = UUID()
        let other = UUID()
        let marks = [
            PointerBoxLead.Mark(id: "label", isRing: false, inCaptureSpace: true, captureID: capture),
            PointerBoxLead.Mark(id: "arrow", isRing: false, inCaptureSpace: true, captureID: capture),
            PointerBoxLead.Mark(id: "canvas", isRing: true, inCaptureSpace: false, captureID: capture),
            PointerBoxLead.Mark(id: "other", isRing: true, inCaptureSpace: true, captureID: other),
            PointerBoxLead.Mark(id: "box", isRing: true, inCaptureSpace: true, captureID: capture),
        ]
        #expect(PointerBoxLead.boxIDs(marks, captureID: capture) == ["box"])
    }

    @Test func aSceneWithoutARingHasNoBox() {
        #expect(PointerBoxLead.boxIDs([], captureID: UUID()).isEmpty)
    }
}
