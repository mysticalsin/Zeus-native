import Foundation
import Testing
@testable import ZeusCore

@Suite("Annotation crop box")
struct AnnotationCropBoxTests {
    private func clip(
        _ x: Double, _ y: Double, _ width: Double, _ height: Double,
        imageWidth: Int = 100, imageHeight: Int = 100
    ) -> AnnotationCropBox.Rect? {
        AnnotationCropBox.clip(
            x: x, y: y, width: width, height: height,
            imageWidth: imageWidth, imageHeight: imageHeight
        )
    }

    @Test func insideMarkIsUnchanged() {
        #expect(clip(10, 20, 30, 40, imageWidth: 200, imageHeight: 100) == AnnotationCropBox.Rect(x: 10, y: 20, width: 30, height: 40))
    }

    @Test func negativeOriginClipsToTheImage() {
        #expect(clip(-2, -3, 5, 4, imageWidth: 10, imageHeight: 10) == AnnotationCropBox.Rect(x: 0, y: 0, width: 3, height: 1))
    }

    @Test func farEdgesClipToTheImage() {
        #expect(clip(1.5, 2.25, 10.5, 4, imageWidth: 8, imageHeight: 100) == AnnotationCropBox.Rect(x: 1.5, y: 2.25, width: 6.5, height: 4))
        #expect(clip(-10, -10, 1000, 1000, imageWidth: 8, imageHeight: 6) == AnnotationCropBox.Rect(x: 0, y: 0, width: 8, height: 6))
    }

    @Test func widthUnderOneIsRefused() {
        #expect(clip(0, 0, 0.999, 20) == nil)
        #expect(!AnnotationCropBox.acceptsMark(width: 0.999, height: 20))
    }

    @Test func heightUnderOneIsRefused() {
        #expect(clip(0, 0, 20, 0) == nil)
        #expect(!AnnotationCropBox.acceptsMark(width: 20, height: 0))
    }

    @Test func negativeStoredSizeStillClips() {
        #expect(AnnotationCropBox.acceptsMark(width: -8, height: -3))
        #expect(clip(10, 4, -8, -3) == AnnotationCropBox.Rect(x: 2, y: 1, width: 8, height: 3))
    }

    @Test func aGapIsRefused() {
        #expect(clip(100, 0, 10, 10, imageWidth: 50, imageHeight: 50) == nil)
        #expect(clip(0, 40, 10, 10, imageWidth: 50, imageHeight: 20) == nil)
    }

    @Test func aSharedEdgeIsRefused() {
        #expect(clip(10, 0, 5, 5, imageWidth: 10, imageHeight: 10) == nil)
        #expect(clip(0, 10, 5, 5, imageWidth: 10, imageHeight: 10) == nil)
    }

    @Test func onePixelIsKept() {
        #expect(clip(0, 0, 1, 1, imageWidth: 10, imageHeight: 10) == AnnotationCropBox.Rect(x: 0, y: 0, width: 1, height: 1))
        #expect(clip(9, 8, 1, 1, imageWidth: 10, imageHeight: 9) == AnnotationCropBox.Rect(x: 9, y: 8, width: 1, height: 1))
    }

    @Test func aSliverUnderOnePixelIsRefused() {
        #expect(clip(9.2, 0, 5, 2, imageWidth: 10, imageHeight: 10) == nil)
        #expect(clip(0, 9.2, 4, 5, imageWidth: 10, imageHeight: 10) == nil)
    }

    @Test func anEmptyImageIsRefused() {
        #expect(clip(0, 0, 10, 10, imageWidth: 0, imageHeight: 10) == nil)
        #expect(clip(0, 0, 10, 10, imageWidth: 10, imageHeight: 0) == nil)
    }

    @Test func markedLabelAddsTheCropSuffix() {
        #expect(AnnotationCropBox.markedLabel("screen 1") == "screen 1 (marked crop)")
        #expect(AnnotationCropBox.markedLabel("") == " (marked crop)")
    }

    @Test func jpegQualityStaysAtTheCurrentCompression() {
        #expect(AnnotationCropBox.jpegQuality == 0.85)
    }

    @Test func acceptsMarkUsesTheAbsoluteSize() {
        #expect(AnnotationCropBox.acceptsMark(width: 1, height: 1))
        #expect(AnnotationCropBox.acceptsMark(width: -1, height: 4))
        #expect(!AnnotationCropBox.acceptsMark(width: 0.5, height: 4))
        #expect(!AnnotationCropBox.acceptsMark(width: 4, height: -0.5))
    }

    @Test func bothAxesMustClearOnePixel() {
        #expect(clip(0, 0, 4, 0.2) == nil)
        #expect(clip(0, 0, 0.2, 4) == nil)
        #expect(clip(0, 0, -0.2, -4) == nil)
    }
}
