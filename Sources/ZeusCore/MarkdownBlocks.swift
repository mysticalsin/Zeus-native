import Foundation

/// Block-level Markdown for chat replies and agent plans: headings, paragraphs, bullet and
/// numbered lists (with nesting), fenced code, quotes and rules. Inline styling (bold, code,
/// links) is left to the renderer.
public enum MarkdownBlock: Equatable, Sendable {
    public struct Item: Equatable, Sendable {
        public var text: String
        public var depth: Int
        /// The item's own number in a numbered list.
        public var number: Int?
        /// `- [ ]` / `- [x]` task items.
        public var checked: Bool?
    }

    case heading(level: Int, text: String)
    case paragraph(String)
    case list(ordered: Bool, items: [Item])
    case code(language: String?, text: String)
    case quote(String)
    case rule

    public static func parse(_ markdown: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        var paragraph: [String] = []
        var quote: [String] = []
        var listItems: [Item] = []
        var listOrdered = false
        var code: (language: String?, lines: [String])?

        func flushParagraph() {
            if !paragraph.isEmpty { blocks.append(.paragraph(paragraph.joined(separator: "\n"))) }
            paragraph = []
        }
        func flushQuote() {
            if !quote.isEmpty { blocks.append(.quote(quote.joined(separator: "\n"))) }
            quote = []
        }
        func flushList() {
            if !listItems.isEmpty { blocks.append(.list(ordered: listOrdered, items: listItems)) }
            listItems = []
        }
        func flushAll() { flushParagraph(); flushQuote(); flushList() }

        for rawLine in markdown.components(separatedBy: "\n") {
            let line = rawLine.replacingOccurrences(of: "\t", with: "    ")
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if var open = code {
                if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                    blocks.append(.code(language: open.language, text: open.lines.joined(separator: "\n")))
                    code = nil
                } else {
                    open.lines.append(rawLine)
                    code = open
                }
                continue
            }
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                flushAll()
                let language = trimmed.dropFirst(3).trimmingCharacters(in: .whitespaces)
                code = (language.isEmpty ? nil : language, [])
                continue
            }
            if trimmed.isEmpty {
                flushParagraph(); flushQuote()
                continue
            }
            if let heading = headingLevel(trimmed) {
                flushAll()
                blocks.append(.heading(level: heading.level, text: heading.text))
                continue
            }
            if isRule(trimmed) {
                flushAll()
                blocks.append(.rule)
                continue
            }
            if trimmed.hasPrefix(">") {
                flushParagraph(); flushList()
                quote.append(String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces))
                continue
            }
            let indent = line.prefix { $0 == " " }.count
            if let item = listItem(trimmed, depth: indent / 2) {
                flushParagraph(); flushQuote()
                if listItems.isEmpty { listOrdered = item.ordered }
                else if item.item.depth == 0, item.ordered != listOrdered {
                    flushList()
                    listOrdered = item.ordered
                }
                listItems.append(item.item)
                continue
            }
            if !listItems.isEmpty, indent >= 2 {
                // A wrapped line belongs to the item above.
                listItems[listItems.count - 1].text += " " + trimmed
                continue
            }
            flushQuote(); flushList()
            paragraph.append(trimmed)
        }
        if let open = code { blocks.append(.code(language: open.language, text: open.lines.joined(separator: "\n"))) }
        flushAll()
        return blocks
    }

    static func headingLevel(_ line: String) -> (level: Int, text: String)? {
        let hashes = line.prefix { $0 == "#" }.count
        guard (1...6).contains(hashes), line.dropFirst(hashes).first == " " else { return nil }
        return (hashes, line.dropFirst(hashes).trimmingCharacters(in: .whitespaces))
    }

    static func isRule(_ line: String) -> Bool {
        let compact = line.replacingOccurrences(of: " ", with: "")
        guard compact.count >= 3, let first = compact.first, "-*_".contains(first) else { return false }
        return compact.allSatisfy { $0 == first }
    }

    static func listItem(_ line: String, depth: Int) -> (ordered: Bool, item: Item)? {
        var text: Substring
        var number: Int?
        if let marker = line.first, "-*+".contains(marker), line.dropFirst().first == " " {
            text = line.dropFirst(2)
        } else {
            let digits = line.prefix { $0.isNumber }
            guard !digits.isEmpty, digits.count <= 9 else { return nil }
            let rest = line.dropFirst(digits.count)
            guard let dot = rest.first, dot == "." || dot == ")", rest.dropFirst().first == " " else { return nil }
            number = Int(digits)
            text = rest.dropFirst(2)
        }
        var checked: Bool?
        if text.hasPrefix("[ ] ") { checked = false; text = text.dropFirst(4) }
        else if text.lowercased().hasPrefix("[x] ") { checked = true; text = text.dropFirst(4) }
        return (number != nil, Item(text: text.trimmingCharacters(in: .whitespaces), depth: depth, number: number, checked: checked))
    }
}
