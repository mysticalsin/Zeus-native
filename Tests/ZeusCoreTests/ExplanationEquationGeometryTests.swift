import Foundation
import Testing
@testable import ZeusCore

/// Phase 4 equation geometry (docs/POINTING-ASSISTANT-PLAN.md).
/// An equation is plain text in a monospaced cell. There is no TeX engine:
/// a caret, underscore, or slash stays on the baseline, and an ASCII
/// backslash or dollar sign is refused.
@Suite("Explanation equation geometry")
struct ExplanationEquationGeometryTests {
    private typealias Equation = ExplanationEquationGeometry

    private func layout(
        _ text: String,
        cellWidth: Double = Equation.cellWidth,
        cellHeight: Double = Equation.cellHeight
    ) -> Equation.Outcome {
        Equation.layout(text, cellWidth: cellWidth, cellHeight: cellHeight)
    }

    private func block(
        _ text: String,
        cellWidth: Double = Equation.cellWidth,
        cellHeight: Double = Equation.cellHeight
    ) -> Equation.Block? {
        if case .block(let value) = layout(text, cellWidth: cellWidth, cellHeight: cellHeight) { return value }
        return nil
    }

    @Test func theCellContractMatchesTheCanvasPointSize() {
        #expect(Equation.pointSize == 14)
        #expect(Equation.cellWidth == 14)
        #expect(Equation.cellHeight == 14)
        #expect(Equation.tabStop == 4)
        #expect(Equation.textByteLimit == 1024)
        #expect(Equation.face == "monospaced")
    }

    @Test func aPlainEquationStaysOnOneBaseline() {
        let samples = ["E = mc^2", "x_1", "a/b", "{1, 2}", "50%", "a & b", "πr²"]
        for text in samples {
            let value = block(text)
            #expect(value?.lines == [text])
            #expect(value?.rows == 1)
            #expect(value?.columns == text.count)
            #expect(value?.glyphs.map(\.text) == text.map(String.init))
            #expect(value?.glyphs.map(\.row) == Array(repeating: 0, count: text.count))
            #expect(value?.glyphs.map(\.column) == Array(0..<text.count))
            #expect(value?.width == Double(text.count) * Equation.cellWidth)
            #expect(value?.height == Equation.cellHeight)
            #expect(value?.face == "monospaced")
            #expect(value?.cellWidth == Equation.cellWidth)
            #expect(value?.cellHeight == Equation.cellHeight)
            #expect(layout(text) == layout(text))
        }
        let caret = block("E = mc^2")
        let mark = caret?.glyphs.first { $0.text == "^" }
        #expect(mark?.row == 0)
        #expect(mark?.column == 6)
        #expect(caret?.glyphs.allSatisfy { $0.row == mark?.row } == true)
    }

    @Test func aStackedFractionIsRowsAndALongLineDoesNotWrap() {
        let stacked = block("a\n-\nb")
        #expect(stacked?.lines == ["a", "-", "b"])
        #expect(stacked?.rows == 3)
        #expect(stacked?.columns == 1)
        #expect(stacked?.width == Equation.cellWidth)
        #expect(stacked?.height == Equation.cellHeight * 3)
        #expect(stacked?.glyphs.map(\.text) == ["a", "-", "b"])
        #expect(stacked?.glyphs.map(\.row) == [0, 1, 2])
        #expect(stacked?.glyphs.map(\.column) == [0, 0, 0])

        let aligned = block("  1\n+ 2")
        #expect(aligned?.lines == ["  1", "+ 2"])
        #expect(aligned?.columns == 3)
        #expect(aligned?.rows == 2)
        #expect(aligned?.glyphs.first?.text == " ")

        let long = String(repeating: "a", count: 300)
        let unwrapped = block(long)
        #expect(unwrapped?.rows == 1)
        #expect(unwrapped?.columns == 300)
        #expect(unwrapped?.lines == [long])
        #expect(unwrapped?.width == 300 * Equation.cellWidth)
    }

    @Test func tabsExpandToFourColumnStops() {
        let middle = block("a\tb")
        #expect(middle?.lines == ["a   b"])
        #expect(middle?.columns == 5)
        #expect(middle?.glyphs.map(\.text) == ["a", " ", " ", " ", "b"])
        #expect(middle?.glyphs.contains { $0.text == "\t" } == false)

        #expect(block("abcd\tX")?.lines == ["abcd    X"])
        #expect(block("ab\tc")?.lines == ["ab  c"])
        #expect(block("\ta")?.lines == ["    a"])
        #expect(block("a\tb\tc")?.columns == 9)
    }

    @Test func aTrailingNewlineDoesNotAddARow() {
        #expect(block("a\n")?.lines == ["a"])
        #expect(block("a\n")?.rows == 1)
        #expect(block("a\n\n")?.lines == ["a", ""])
        #expect(block("a\n\n")?.rows == 2)
        #expect(block("a\n\n")?.columns == 1)
        #expect(block("a\n\n")?.glyphs.map(\.text) == ["a"])
        #expect(block("a\nb")?.lines == ["a", "b"])
        #expect(block("a\nb")?.height == Equation.cellHeight * 2)
    }

    @Test func oneGraphemeClusterIsOneColumn() {
        let composed = "é"
        let combining = "e\u{0301}"
        let flag = "🇺🇸"
        #expect(combining.count == 1)
        #expect(combining.utf8.count == 3)
        #expect(block(combining)?.columns == 1)
        #expect(block(combining)?.glyphs.map(\.text) == [combining])
        #expect(block(composed)?.columns == 1)
        #expect(block(composed)?.glyphs.map(\.text) == [composed])
        #expect(composed.utf8.count == 2)
        #expect(flag.count == 1)
        #expect(flag.utf8.count == 8)
        #expect(block(flag)?.columns == 1)
        #expect(block(flag)?.width == Equation.cellWidth)

        let pair = "e\u{0301}"
        let exact = String(repeating: pair, count: 341)
        #expect(exact.utf8.count == 1023)
        #expect(block(exact)?.columns == 341)
        #expect(block(exact)?.rows == 1)
        let over = exact + pair
        #expect(over.utf8.count == 1026)
        #expect(layout(over) == .refused(.textBounds))
    }

    @Test func texMarkupIsRefusedAndNotLaidOut() {
        let markup = [
            "\\frac{1}{2}",
            "$x$",
            "$$x$$",
            "\\(x\\)",
            "\\[x\\]",
            "\\",
            "E = $",
            "a\\b",
            " $ ",
            String(repeating: "\\", count: Equation.textByteLimit),
        ]
        for text in markup {
            #expect(layout(text) == .refused(.tex))
        }
        let admitted = ["E = mc^2", "x_1", "a/b", "{1, 2}", "50%", "a & b", "＄", "＼"]
        for text in admitted {
            #expect(block(text)?.lines == [text])
        }
    }

    @Test func textBoundsMatchTheObjectTextRule() {
        let refused = [
            "",
            " ",
            "   ",
            "\n",
            "\t",
            "\n\t ",
            "a\r\nb",
            "a\rb",
            "a\u{0000}b",
            "a\u{007F}b",
            "a\u{000B}b",
            "a\u{0001}b",
            String(repeating: "a", count: Equation.textByteLimit + 1),
            String(repeating: "\\", count: Equation.textByteLimit + 1),
            String(repeating: "é", count: 513),
        ]
        for text in refused {
            #expect(layout(text) == .refused(.textBounds))
        }
        let exact = String(repeating: "a", count: Equation.textByteLimit)
        #expect(exact.utf8.count == 1024)
        #expect(block(exact)?.columns == 1024)
        #expect(block(exact)?.rows == 1)
        let accented = String(repeating: "é", count: 512)
        #expect(accented.utf8.count == 1024)
        #expect(block(accented)?.columns == 512)
        let line = String(repeating: "a", count: 1023) + "\n"
        #expect(line.utf8.count == 1024)
        #expect(block(line)?.lines == [String(repeating: "a", count: 1023)])
        #expect(block(line)?.rows == 1)
    }

    @Test func aLineSeparatorIsAGlyphNotABreak() {
        let text = "a\u{2028}b"
        let value = block(text)
        #expect(text.count == 3)
        #expect(value?.rows == 1)
        #expect(value?.columns == 3)
        #expect(value?.lines == [text])
        #expect(value?.glyphs.map(\.text) == ["a", "\u{2028}", "b"])
        #expect(block("a\nb")?.rows == 2)
    }

    @Test func aBadCellIsRefusedAndAFiniteCellScalesTheGrid() {
        let sample = "E = mc^2"
        for width in [Double.nan, Double.infinity, -Double.infinity, 0, -1, -0.0] {
            #expect(layout(sample, cellWidth: width) == .refused(.cell))
            #expect(layout(sample, cellHeight: width) == .refused(.cell))
        }
        let scaled = block("ab", cellWidth: 2, cellHeight: 3)
        #expect(scaled?.columns == 2)
        #expect(scaled?.rows == 1)
        #expect(scaled?.cellWidth == 2)
        #expect(scaled?.cellHeight == 3)
        #expect(scaled?.width == 4)
        #expect(scaled?.height == 3)
        #expect(scaled?.face == "monospaced")

        let huge = Double.greatestFiniteMagnitude
        #expect(block("a", cellWidth: huge)?.width == huge)
        #expect(layout("ab", cellWidth: huge) == .refused(.cell))
        #expect(layout("a\nb", cellHeight: huge) == .refused(.cell))
    }

    @Test func refusalChecksBoundsThenTexThenTheCell() {
        let hugeTex = String(repeating: "a", count: Equation.textByteLimit + 1) + "$"
        #expect(layout(hugeTex) == .refused(.textBounds))
        #expect(layout("$", cellWidth: .nan) == .refused(.tex))
        #expect(layout("\\frac{1}{2}", cellWidth: 0, cellHeight: .nan) == .refused(.tex))
        #expect(layout("E = mc^2", cellWidth: .nan) == .refused(.cell))
        #expect(layout("E = mc^2", cellHeight: 0) == .refused(.cell))
    }
}
