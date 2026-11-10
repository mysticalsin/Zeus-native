import Foundation
import Testing
@testable import ZeusCore

@Suite("Theme tokens")
struct ThemeTokensTests {
    @Test func purpleLightingMatchesBrief() {
        #expect(ZeusThemeTokens.zeusPurple == 0x8B5CF6)
        #expect(ZeusThemeTokens.zeusPurpleGlow == 0xA78BFA)
        #expect(ZeusThemeTokens.zeusPurpleDeep == 0x5B21B6)
    }

    @Test func mascotGoldIsSeparateFromAccent() {
        #expect(ZeusThemeTokens.lightningGold == 0xF5BA32)
        #expect(!ZeusThemeTokens.accentTokens.contains(ZeusThemeTokens.lightningGold))
        #expect(!ZeusThemeTokens.accentTokens.contains(ZeusThemeTokens.scarfCobalt))
        #expect(!ZeusThemeTokens.accentTokens.contains(ZeusThemeTokens.cloudIvory))
    }
}

@Suite("To-do learning")
struct TodoLearningTests {
    @Test func learnsDueOffsetAndSuggests() {
        var learning = TodoLearning()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Sao_Paulo")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 10))!
        learning.observeAdd("Call Anna", due: "2026-11-02", now: now, calendar: calendar)
        learning.observeAdd("Call Anna", due: "2026-11-03", now: now, calendar: calendar)
        let suggestion = learning.suggestDue(for: "Call Anna", now: now, calendar: calendar)
        #expect(suggestion?.due == "2026-11-02" || suggestion?.due == "2026-11-03")
        #expect(suggestion?.reason.contains("usually") == true)
    }

    @Test func recurringAfterDone() {
        var learning = TodoLearning()
        learning.observeAdd("Standup notes", due: nil)
        learning.observeAdd("Standup notes", due: nil)
        learning.observeAdd("Standup notes", due: nil)
        learning.observeDone("Standup notes")
        learning.observeDone("Standup notes")
        let recurring = learning.recurringSuggestions(openTitles: [])
        #expect(recurring.contains { $0.title == "Standup notes" })
        #expect(learning.recurringSuggestions(openTitles: ["Standup notes"]).isEmpty)
    }

    @Test func splitLongTitle() {
        let learning = TodoLearning()
        let suggestion = learning.suggestSplit("call Ana tomorrow and send the invoice Friday and book the dentist")
        #expect(suggestion?.split.count ?? 0 >= 2)
    }

    @Test func clearAndDisable() {
        var learning = TodoLearning()
        learning.observeAdd("Milk", due: "2026-11-02")
        learning.observeAdd("Milk", due: "2026-11-03")
        learning.enabled = false
        #expect(learning.suggestDue(for: "Milk") == nil)
        learning.enabled = true
        learning.clear()
        #expect(learning.patterns.isEmpty)
    }

    @Test func markdownRoundTripOnTempVault() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("zeus-learn-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("ZEUS"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let note = root.appendingPathComponent("ZEUS/To-do.md")
        let source = BrainSource(kind: .markdown, name: "tmp", path: root.path)
        let connection = BrainConnection(source: source, access: .readWrite, todo: .note(BrainConnection.defaultTodoNote))
        let store = root.appendingPathComponent("todos.json")
        var sync = TodoSync(storeFile: store, connection: connection)
        #expect(sync.list.add("Ship COLOR", due: "2026-11-01") != nil)
        try sync.commit()
        let text = try String(contentsOf: note, encoding: .utf8)
        #expect(text.contains("- [ ] Ship COLOR"))
        #expect(text.contains("2026-11-01"))
        // Never rewrite unrelated notes.
        let other = root.appendingPathComponent("Keep.md")
        try "# Keep\nHello\n".write(to: other, atomically: true, encoding: .utf8)
        try sync.commit()
        #expect(try String(contentsOf: other, encoding: .utf8) == "# Keep\nHello\n")
    }
}
