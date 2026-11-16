import Foundation
import Testing

/// Structure checks for layout fixes that cannot be unit tested without opening a window.
@Suite("UI polish source")
struct UIPolishSourceTests {
    static func source(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    @Test func thePermissionCueWrapsInsteadOfTruncatingMidWord() throws {
        let text = try Self.source("Sources/Zeus/TopBar/TopBarViews.swift")
        let start = try #require(text.range(of: "case .permission(let text, let pane):"))
        let block = String(text[start.upperBound...].prefix(900))
        #expect(block.contains("lineLimit(2)"))
        #expect(!block.contains("lineLimit(1)"))
    }
}
