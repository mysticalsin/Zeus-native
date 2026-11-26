import Foundation

/// Plain-text equation geometry.
///
/// Phase 4 asks for an equation as plain text in a monospaced cell, with no TeX
/// engine. Each extended grapheme cluster is one column on the baseline. A caret,
/// underscore, or slash is a character, not a superscript or a stacked fraction.
/// An ASCII backslash or an ASCII dollar sign is TeX markup and is refused.
/// This type does not measure a font, does not draw, and does not run a TeX lexer.
/// The blank check is read from `ExplanationEquationGeometryBox`. The laid-out
/// line stays as written, including a zero-width space.
public enum ExplanationEquationGeometry {
    /// Object text cap in `ExplanationLimits.text`, counted in UTF-8 bytes.
    public static let textByteLimit = 1024
    /// Canvas labels are set at 14 points. The default cell is a square of that
    /// size. It is not a measured glyph advance.
    public static let pointSize = 14.0
    public static let cellWidth = pointSize
    public static let cellHeight = pointSize
    /// Columns a tab advances, from the column it starts on, to the next stop.
    public static let tabStop = 4
    public static let face = "monospaced"

    public struct Glyph: Equatable, Sendable {
        public var row: Int
        public var column: Int
        public var text: String

        public init(row: Int, column: Int, text: String) {
            self.row = row
            self.column = column
            self.text = text
        }
    }

    public struct Block: Equatable, Sendable {
        public var lines: [String]
        public var glyphs: [Glyph]
        public var columns: Int
        public var rows: Int
        public var cellWidth: Double
        public var cellHeight: Double
        public var width: Double
        public var height: Double
        public var face: String

        public init(lines: [String], glyphs: [Glyph], columns: Int, rows: Int,
                    cellWidth: Double, cellHeight: Double, width: Double, height: Double, face: String) {
            self.lines = lines
            self.glyphs = glyphs
            self.columns = columns
            self.rows = rows
            self.cellWidth = cellWidth
            self.cellHeight = cellHeight
            self.width = width
            self.height = height
            self.face = face
        }
    }

    public enum Refusal: Equatable, Sendable {
        case textBounds
        case tex
        case cell
    }

    public enum Outcome: Equatable, Sendable {
        case block(Block)
        case refused(Refusal)
    }

    /// Lays `text` out on the baseline. Checks run in order: object-text bounds,
    /// then TeX introducers, then the cell. A non-finite product of the grid and
    /// the cell is a cell refusal, so the block never carries a non-finite size.
    public static func layout(
        _ text: String,
        cellWidth: Double = Self.cellWidth,
        cellHeight: Double = Self.cellHeight
    ) -> Outcome {
        if let refusal = textRefusal(text) { return .refused(refusal) }
        guard cellWidth.isFinite, cellHeight.isFinite, cellWidth > 0, cellHeight > 0 else {
            return .refused(.cell)
        }
        let lines = expandedLines(text)
        let columns = lines.map(\.count).max() ?? 0
        let rows = lines.count
        guard rows > 0, let width = span(columns, cellWidth), let height = span(rows, cellHeight) else {
            return .refused(.cell)
        }
        return .block(Block(
            lines: lines, glyphs: glyphs(on: lines), columns: columns, rows: rows,
            cellWidth: cellWidth, cellHeight: cellHeight, width: width, height: height, face: face))
    }

    /// The same bounds as `ExplanationReducer` object text: a non-blank string,
    /// at most `textByteLimit` UTF-8 bytes, and no controls other than newline and tab.
    /// Blank scalars are named in `ExplanationEquationGeometryBox`. A zero-width space counts as text.
    private static func textRefusal(_ text: String) -> Refusal? {
        if text.utf8.count > textByteLimit { return .textBounds }
        if !ExplanationEquationGeometryBox.hasEquationText(text) { return .textBounds }
        let controls = text.unicodeScalars.contains { scalar in
            scalar.value == 127 || (scalar.value < 32 && scalar != "\n" && scalar != "\t")
        }
        if controls { return .textBounds }
        if text.unicodeScalars.contains(where: { $0 == "\\" || $0 == "$" }) { return .tex }
        return nil
    }

    /// Splits on newline only. One trailing newline does not add a blank row.
    /// A tab becomes spaces out to the next `tabStop`, so the stored line is plain text.
    private static func expandedLines(_ text: String) -> [String] {
        var raw = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        if text.hasSuffix("\n"), raw.last?.isEmpty == true {
            raw.removeLast()
        }
        return raw.map(expandTabs)
    }

    private static func expandTabs(_ line: String) -> String {
        var out = ""
        var column = 0
        for character in line {
            if character == "\t" {
                let spaces = tabStop - (column % tabStop)
                out.append(String(repeating: " ", count: spaces))
                column += spaces
            } else {
                out.append(character)
                column += 1
            }
        }
        return out
    }

    private static func glyphs(on lines: [String]) -> [Glyph] {
        var result: [Glyph] = []
        for (row, line) in lines.enumerated() {
            for (column, character) in line.enumerated() {
                result.append(Glyph(row: row, column: column, text: String(character)))
            }
        }
        return result
    }

    private static func span(_ count: Int, _ cell: Double) -> Double? {
        guard count >= 0 else { return nil }
        let value = Double(count) * cell
        return value.isFinite ? value : nil
    }
}
