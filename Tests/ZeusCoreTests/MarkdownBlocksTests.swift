import Testing
@testable import ZeusCore

@Suite("Markdown blocks")
struct MarkdownBlocksTests {
    @Test func mixedDocument() {
        let text = """
        # Plan
        Do the **thing** first,
        then the rest.

        1. Read files
        2. Write tests
           with care
        - [ ] open item
        - [x] done item
          - nested

        ```swift
        let x = 1

        print(x)
        ```
        > quoted
        > twice
        ---
        Tail
        """
        let blocks = MarkdownBlock.parse(text)
        #expect(blocks.count == 8)
        #expect(blocks[0] == .heading(level: 1, text: "Plan"))
        #expect(blocks[1] == .paragraph("Do the **thing** first,\nthen the rest."))
        guard case .list(let ordered, let items) = blocks[2] else { Issue.record("no ordered list"); return }
        #expect(ordered)
        #expect(items.map(\.text) == ["Read files", "Write tests with care"])
        #expect(items.map(\.number) == [1, 2])
        guard case .list(let bullets, let tasks) = blocks[3] else { Issue.record("no bullet list"); return }
        #expect(!bullets)
        #expect(tasks.map(\.checked) == [false, true, nil])
        #expect(tasks.map(\.depth) == [0, 0, 1])
        #expect(blocks[4] == .code(language: "swift", text: "let x = 1\n\nprint(x)"))
        #expect(blocks[5] == .quote("quoted\ntwice"))
        #expect(blocks[6] == .rule)
        #expect(blocks[7] == .paragraph("Tail"))
    }

    @Test func edgeCases() {
        #expect(MarkdownBlock.parse("") == [])
        #expect(MarkdownBlock.parse("#hashtag not heading") == [.paragraph("#hashtag not heading")])
        #expect(MarkdownBlock.parse("1.5 million users") == [.paragraph("1.5 million users")])
        #expect(MarkdownBlock.parse("```\nunclosed") == [.code(language: nil, text: "unclosed")])
        #expect(MarkdownBlock.parse("* a\n* b") == [.list(ordered: false, items: [
            .init(text: "a", depth: 0, number: nil, checked: nil), .init(text: "b", depth: 0, number: nil, checked: nil),
        ])])
    }
}
