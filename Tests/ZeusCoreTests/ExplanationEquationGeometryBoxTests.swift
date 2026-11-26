import Foundation
import Testing
@testable import ZeusCore

@Suite("Explanation equation geometry box")
struct ExplanationEquationGeometryBoxTests {
    private typealias Equation = ExplanationEquationGeometry
    private typealias Box = ExplanationEquationGeometryBox

    private func lines(_ text: String) -> [String]? {
        if case .block(let value) = Equation.layout(text) { return value.lines }
        return nil
    }

    @Test func blankScalarsAreNamedAndLeaveAZeroWidthSpace() {
        #expect(Box.blankScalars.contains("\u{0009}"))
        #expect(Box.blankScalars.contains("\u{000A}"))
        #expect(Box.blankScalars.contains("\u{000B}"))
        #expect(Box.blankScalars.contains("\u{000C}"))
        #expect(Box.blankScalars.contains("\u{000D}"))
        #expect(Box.blankScalars.contains("\u{0020}"))
        #expect(Box.blankScalars.contains("\u{0085}"))
        #expect(Box.blankScalars.contains("\u{00A0}"))
        #expect(Box.blankScalars.contains("\u{1680}"))
        #expect(Box.blankScalars.contains("\u{2000}"))
        #expect(Box.blankScalars.contains("\u{2001}"))
        #expect(Box.blankScalars.contains("\u{2002}"))
        #expect(Box.blankScalars.contains("\u{2003}"))
        #expect(Box.blankScalars.contains("\u{2004}"))
        #expect(Box.blankScalars.contains("\u{2005}"))
        #expect(Box.blankScalars.contains("\u{2006}"))
        #expect(Box.blankScalars.contains("\u{2007}"))
        #expect(Box.blankScalars.contains("\u{2008}"))
        #expect(Box.blankScalars.contains("\u{2009}"))
        #expect(Box.blankScalars.contains("\u{200A}"))
        #expect(Box.blankScalars.contains("\u{2028}"))
        #expect(Box.blankScalars.contains("\u{2029}"))
        #expect(Box.blankScalars.contains("\u{202F}"))
        #expect(Box.blankScalars.contains("\u{205F}"))
        #expect(Box.blankScalars.contains("\u{3000}"))
        #expect(!Box.blankScalars.contains("\u{200B}"))
        #expect(Box.trimmed("\u{200B}") == "\u{200B}")
        #expect(Box.trimmed(" \u{200B} ") == "\u{200B}")
        #expect(Box.trimmed(" \t\n\u{00A0}\u{3000}") == "")
    }

    @Test func aZeroWidthSpaceCountsAsEquationText() {
        #expect(Box.hasEquationText("\u{200B}"))
        #expect(Box.trimmed("\u{200B}") == "\u{200B}")
        let mark = "\u{200B}"
        #expect(lines(mark) == [mark])
        let padded = " \u{200B} "
        #expect(lines(padded) == [padded])
        #expect(Box.trimmed(padded) == mark)
    }

    @Test func aBodyOfOnlyNamedBlanksIsRefused() {
        #expect(!Box.hasEquationText(""))
        #expect(!Box.hasEquationText(" "))
        #expect(!Box.hasEquationText("\u{00A0}"))
        #expect(!Box.hasEquationText("\u{0085}"))
        #expect(!Box.hasEquationText("\u{3000}"))
        #expect(!Box.hasEquationText(" \t\n\u{00A0}\u{3000}"))
        #expect(Box.hasEquationText("\u{00A0}\u{200B}"))
        #expect(Box.trimmed("\u{00A0}\u{200B}\u{3000}") == "\u{200B}")
        for text in ["", "   ", "\n", "\t", "\u{00A0}", "\u{0085}", "\u{1680}", "\u{2028}", "\u{3000}", " \t\n\u{00A0}\u{3000}"] {
            #expect(!Box.hasEquationText(text))
            #expect(Equation.layout(text) == .refused(.textBounds))
        }
        let kept = "\u{00A0}\u{200B}\u{3000}"
        #expect(lines(kept) == [kept])
    }

    @Test func namedBlanksAroundAnEquationStayInTheLine() {
        let equation = " \u{00A0}E = mc^2\u{3000} "
        #expect(Box.hasEquationText(equation))
        #expect(Box.trimmed(equation) == "E = mc^2")
        #expect(Box.trimmed(" \u{200B} ") == "\u{200B}")
        #expect(lines(equation) == [equation])
        let marked = "\u{200B}"
        #expect(lines(marked) == [marked])
        #expect(lines("a\u{2028}b") == ["a\u{2028}b"])
    }

    @Test func aZeroWidthSpaceInsideTheEquationStays() {
        let interior = "E =\u{200B}mc^2"
        #expect(Box.trimmed(interior) == interior)
        #expect(Box.trimmed("\u{200B}E = mc^2") == "\u{200B}E = mc^2")
        #expect(Box.trimmed("E = mc^2\u{200B}") == "E = mc^2\u{200B}")
        #expect(lines(interior) == [interior])
        let leading = "\u{200B}E = mc^2"
        #expect(lines(leading) == [leading])
        #expect(Equation.layout("\n") == .refused(.textBounds))
        #expect(Equation.layout("a\u{007F}b") == .refused(.textBounds))
        #expect(lines("a\nb") == ["a", "b"])
    }
}
