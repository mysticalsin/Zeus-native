import CoreGraphics
import Testing
@testable import ZeusCore

@Suite("Dictation preview")
struct DictationPreviewTests {
    let visible = CGRect(x: 0, y: 0, width: 1728, height: 1080)
    let size = CGSize(width: 420, height: 150)

    @Test func sitsUnderTheCaret() {
        let caret = CGRect(x: 500, y: 600, width: 2, height: 18)
        let frame = DictationPreviewLayout.frame(size: size, caret: caret, pointer: .zero, visible: visible)
        #expect(frame.maxY == 600 - DictationPreviewLayout.gap)
        #expect(frame.minX == 484)
    }

    @Test func flipsAboveNearTheBottomAndStaysOnScreen() {
        let caret = CGRect(x: 1700, y: 40, width: 2, height: 18)
        let frame = DictationPreviewLayout.frame(size: size, caret: caret, pointer: .zero, visible: visible)
        #expect(frame.minY == 58 + DictationPreviewLayout.gap)
        #expect(Double(frame.maxX) == 1720)
    }

    @Test func fallsBackToThePointer() {
        let frame = DictationPreviewLayout.frame(size: size, caret: nil, pointer: CGPoint(x: 300, y: 900), visible: visible)
        #expect(frame.maxY == 900 - DictationPreviewLayout.gap)
    }

    @Test func keys() {
        #expect(DictationPreviewKey.action(keyCode: 36, shift: false, command: false) == .insert)
        #expect(DictationPreviewKey.action(keyCode: 76, shift: false, command: false) == .insert)
        #expect(DictationPreviewKey.action(keyCode: 36, shift: true, command: false) == .edit)
        #expect(DictationPreviewKey.action(keyCode: 36, shift: true, command: true) == .insert)
        #expect(DictationPreviewKey.action(keyCode: 53, shift: false, command: false) == .cancel)
        #expect(DictationPreviewKey.action(keyCode: 0, shift: false, command: false) == .edit)
    }

    @Test func emptiedTextInsertsNothing() {
        #expect(DictationPreviewResult.finalText("  hello world \n") == "hello world")
        #expect(DictationPreviewResult.finalText(" \n ") == nil)
    }
}
