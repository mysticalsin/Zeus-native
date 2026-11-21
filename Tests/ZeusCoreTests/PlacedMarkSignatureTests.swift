import Testing
@testable import ZeusCore

/// The compiled screen-mark method. A comment, a string, a raw string, or a `#if false` copy cannot satisfy this.
private protocol ScreenMarkPlaceSignature {
    func place(_ marks: [MarkPin]) -> [LaidOutMark]
}

extension MarkLayout: ScreenMarkPlaceSignature {}

/// The compiled drawing-mark method, and the one `PlacedMark` the module exports.
private protocol DrawingMarkPlaceSignature {
    static func place(_ marks: [DrawingMark]) -> [PlacedMark]
}

extension DrawingLayout: DrawingMarkPlaceSignature {}

@Suite struct PlacedMarkSignatureTests {
    @Test func theCompiledPlaceSignaturesAreTheScreenAndDrawingForms() {
        let laidOut: [LaidOutMark] = MarkLayout(screens: { [] }).place([])
        let drawn: [PlacedMark] = DrawingLayout.place([])
        #expect(laidOut.isEmpty)
        #expect(drawn.isEmpty)
    }
}
