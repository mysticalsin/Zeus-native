import Foundation
import Testing
@testable import ZeusCore

@Suite("Pointing action tools box")
struct PointingActionToolsBoxTests {
    @Test func blankScalarsAreNamedAndLeaveAZeroWidthSpace() {
        #expect(PointingActionToolsBox.blankScalars.contains("\u{0009}"))
        #expect(PointingActionToolsBox.blankScalars.contains("\u{000A}"))
        #expect(PointingActionToolsBox.blankScalars.contains("\u{000B}"))
        #expect(PointingActionToolsBox.blankScalars.contains("\u{000C}"))
        #expect(PointingActionToolsBox.blankScalars.contains("\u{000D}"))
        #expect(PointingActionToolsBox.blankScalars.contains("\u{0020}"))
        #expect(PointingActionToolsBox.blankScalars.contains("\u{0085}"))
        #expect(PointingActionToolsBox.blankScalars.contains("\u{00A0}"))
        #expect(PointingActionToolsBox.blankScalars.contains("\u{1680}"))
        #expect(PointingActionToolsBox.blankScalars.contains("\u{2000}"))
        #expect(PointingActionToolsBox.blankScalars.contains("\u{2001}"))
        #expect(PointingActionToolsBox.blankScalars.contains("\u{2002}"))
        #expect(PointingActionToolsBox.blankScalars.contains("\u{2003}"))
        #expect(PointingActionToolsBox.blankScalars.contains("\u{2004}"))
        #expect(PointingActionToolsBox.blankScalars.contains("\u{2005}"))
        #expect(PointingActionToolsBox.blankScalars.contains("\u{2006}"))
        #expect(PointingActionToolsBox.blankScalars.contains("\u{2007}"))
        #expect(PointingActionToolsBox.blankScalars.contains("\u{2008}"))
        #expect(PointingActionToolsBox.blankScalars.contains("\u{2009}"))
        #expect(PointingActionToolsBox.blankScalars.contains("\u{200A}"))
        #expect(PointingActionToolsBox.blankScalars.contains("\u{2028}"))
        #expect(PointingActionToolsBox.blankScalars.contains("\u{2029}"))
        #expect(PointingActionToolsBox.blankScalars.contains("\u{202F}"))
        #expect(PointingActionToolsBox.blankScalars.contains("\u{205F}"))
        #expect(PointingActionToolsBox.blankScalars.contains("\u{3000}"))
        #expect(!PointingActionToolsBox.blankScalars.contains("\u{200B}"))
        #expect(PointingActionToolsBox.trimmed("\u{200B}") == "\u{200B}")
        #expect(PointingActionToolsBox.trimmed(" \u{200B} ") == "\u{200B}")
        #expect(PointingActionToolsBox.trimmed(" \t\n\u{00A0}\u{3000}") == "")
    }

    @Test func aZeroWidthSpaceCountsAsText() {
        #expect(PointingActionToolsBox.hasBody("\u{200B}"))
        #expect(PointingActionToolsBox.hasBody(" \u{200B} "))
        #expect(PointingActionToolsBox.hasBody("\u{200B}hello"))
        #expect(PointingActionToolsBox.hasBody("  hello  "))
        #expect(PointingActionToolsBox.trimmed("  hello  ") == "hello")
        #expect(!PointingActionToolsBox.hasBody(" \t\n"))
        #expect(!PointingActionToolsBox.hasBody("\u{00A0}\u{3000}"))
        #expect(!PointingActionToolsBox.hasBody(""))
    }

    @Test func aZeroWidthTextIsWritten() {
        let sink = BoxRecordingSink()
        var tools = PointingActionTools()
        let phase = tools.submit(request(text: "\u{200B}", risk: .undoable), sink: sink)
        #expect(indicator(from: phase)?.state == .done)
        #expect(sink.inserts == ["\u{200B}"])
        #expect(refusal(from: phase) == nil)

        let spaced = BoxRecordingSink()
        var spacedTools = PointingActionTools()
        let kept = spacedTools.submit(request(text: "  hello  ", risk: .undoable), sink: spaced)
        #expect(indicator(from: kept)?.state == .done)
        #expect(spaced.inserts == ["  hello  "])

        let clip = BoxRecordingSink()
        var clipTools = PointingActionTools()
        let asked = clipTools.submit(
            request(kind: .writeClipboard, text: "\u{200B}", risk: .safe),
            sink: clip
        )
        #expect(card(from: asked)?.kind == .writeClipboard)
        #expect(refusal(from: asked) == nil)
        #expect(clip.clips.isEmpty)
    }

    @Test func namedBlanksAreEmptyAndAZeroWidthSpaceIsNot() {
        #expect(!PointingActionToolsBox.hasBody(" \t\n\u{00A0}\u{3000}"))
        #expect(PointingActionToolsBox.hasBody("\u{200B}"))

        let blanks = BoxRecordingSink()
        var blankTools = PointingActionTools()
        let refused = blankTools.submit(
            request(text: " \t\n\u{00A0}\u{3000}", risk: .undoable),
            sink: blanks
        )
        #expect(refusal(from: refused)?.reason == .emptyText)
        #expect(blanks.inserts.isEmpty)

        let mark = BoxRecordingSink()
        var markTools = PointingActionTools()
        let written = markTools.submit(request(text: "\u{200B}", risk: .safe), sink: mark)
        #expect(refusal(from: written)?.reason != .emptyText)
        #expect(mark.inserts == ["\u{200B}"])
    }

    @Test func aZeroWidthSummaryIsShown() {
        let sink = BoxRecordingSink()
        var tools = PointingActionTools()
        let phase = tools.submit(request(summary: "\u{200B}", text: "hello", risk: .safe), sink: sink)
        #expect(refusal(from: phase)?.reason != .summary)
        #expect(indicator(from: phase)?.summary == "\u{200B}")
        #expect(sink.inserts == ["hello"])

        let blanks = BoxRecordingSink()
        var blankTools = PointingActionTools()
        let refused = blankTools.submit(
            request(summary: " \t\n\u{00A0}", text: "hello", risk: .undoable),
            sink: blanks
        )
        #expect(refusal(from: refused)?.reason == .summary)
        #expect(blanks.inserts.isEmpty)

        let padded = BoxRecordingSink()
        var paddedTools = PointingActionTools()
        let asked = paddedTools.submit(
            request(summary: " \u{00A0}Note\u{3000}", text: "hello", risk: .risky),
            sink: padded
        )
        #expect(card(from: asked)?.summary == " \u{00A0}Note\u{3000}")
        #expect(padded.inserts.isEmpty)
    }

    private func request(
        id: String = "a1",
        kind: PointingActionRequest.Kind = .insertText,
        summary: String = "Insert the note",
        text: String,
        risk: PointingActionRequest.Risk
    ) -> PointingActionRequest {
        PointingActionRequest(id: id, kind: kind, summary: summary, text: text, risk: risk)
    }

    private func card(from phase: PointingActionPhase) -> PointingActionCard? {
        if case .confirming(let card) = phase { return card }
        return nil
    }

    private func indicator(from phase: PointingActionPhase) -> PointingActionIndicator? {
        if case .indicated(let indicator) = phase { return indicator }
        return nil
    }

    private func refusal(from phase: PointingActionPhase) -> PointingActionRefusal? {
        if case .refused(let refusal) = phase { return refusal }
        return nil
    }
}

private final class BoxRecordingSink: PointingActionSink {
    private(set) var inserts: [String] = []
    private(set) var clips: [String] = []

    func insertText(_ text: String) { inserts.append(text) }
    func writeClipboard(_ text: String) { clips.append(text) }
}
