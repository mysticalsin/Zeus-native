import Foundation
import Testing
@testable import ZeusCore

@Suite("To-do")
struct TodoTests {
    @Test func parsesTaskLines() {
        let line = TodoMarkdown.parse(line: "- [ ] Call Anna 📅 2026-11-02")
        #expect(line?.title == "Call Anna")
        #expect(line?.due == "2026-11-02")
        #expect(line?.done == false)
        #expect(TodoMarkdown.parse(line: "* [x] Ship it")?.done == true)
        #expect(TodoMarkdown.parse(line: "- [ ]") == nil)
        #expect(TodoMarkdown.parse(line: "- plain bullet") == nil)
        #expect(TodoMarkdown.render(TodoItem(title: "Pay rent", done: true, due: "2026-11-01")) == "- [x] Pay rent 📅 2026-11-01")
    }

    @Test func applyKeepsOtherLines() {
        let note = """
        # Monday
        Some thoughts.
        - [ ] One
          - [ ] nested stays
        - [x] Two
        Footer line
        """
        var list = TodoList(items: TodoMarkdown.items(in: note))
        #expect(list.items.map(\.title) == ["One", "Two"])
        list.move(list.items[1].id, by: -1)
        list.toggle(list.items[1].id)
        list.add("Three", due: "2026-11-03")
        let out = TodoMarkdown.apply(list.items, to: note)
        #expect(out == """
        # Monday
        Some thoughts.
        - [x] Two
          - [ ] nested stays
        - [x] One
        - [ ] Three 📅 2026-11-03
        Footer line

        """)
    }

    @Test func applyToEmptyAndRemovals() {
        #expect(TodoMarkdown.apply([TodoItem(title: "A")], to: "") == "## To-do\n- [ ] A\n")
        #expect(TodoMarkdown.apply([TodoItem(title: "A")], to: "Intro\n") == "Intro\n\n## To-do\n- [ ] A\n")
        #expect(TodoMarkdown.apply([], to: "x\n- [ ] A\n- [ ] B\ny") == "x\ny\n")
    }

    @Test func adoptKeepsIDs() {
        var list = TodoList()
        let first = list.add("Milk")!
        list.adopt([TodoItem(title: "Bread"), TodoItem(title: "Milk", done: true)])
        #expect(list.items.count == 2)
        #expect(list.items[1].id == first.id)
        #expect(list.items[1].done)
    }

    @Test func quickAddDates() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Sao_Paulo")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 31, hour: 13))!  // a Saturday
        #expect(TodoQuickAdd.parse("call Anna tomorrow", now: now, calendar: calendar) == ("call Anna", "2026-11-01"))
        #expect(TodoQuickAdd.parse("pay rent by friday", now: now, calendar: calendar) == ("pay rent", "2026-11-06"))
        #expect(TodoQuickAdd.parse("ship it due 2026-11-03", now: now, calendar: calendar) == ("ship it", "2026-11-03"))
        #expect(TodoQuickAdd.parse("buy milk", now: now, calendar: calendar) == ("buy milk", nil))
        #expect(TodoQuickAdd.parse("review next week", now: now, calendar: calendar) == ("review", "2026-11-07"))
    }
}

@Suite("Second brain")
struct SecondBrainTests {
    func temp() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("zeus-brain-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func touch(_ url: URL, _ text: String = "x") throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    @Test func detectsKinds() throws {
        let home = try temp()
        defer { try? FileManager.default.removeItem(at: home) }
        try FileManager.default.createDirectory(at: home.appendingPathComponent("Documents/Vault/.obsidian"), withIntermediateDirectories: true)
        try touch(home.appendingPathComponent("Documents/Vault/inner/.obsidian/app.json"))
        try touch(home.appendingPathComponent("Documents/Graph/logseq/config.edn"))
        for index in 0..<5 { try touch(home.appendingPathComponent("Notes/Plain/n\(index).md")) }
        for index in 0..<3 { try touch(home.appendingPathComponent("Desktop/Export/Page \(index) 0123456789abcdef0123456789abcde\(index).md")) }
        for index in 0..<6 { try touch(home.appendingPathComponent("Documents/repo/d\(index).md")) }
        try FileManager.default.createDirectory(at: home.appendingPathComponent("Documents/repo/.git"), withIntermediateDirectories: true)
        let other = home.appendingPathComponent("Elsewhere/Work")
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        try touch(home.appendingPathComponent("Library/Application Support/obsidian/obsidian.json"),
                  #"{"vaults":{"a1":{"path":"\#(other.path)","ts":1}}}"#)

        let found = BrainDetector.detect(home: home)
        let kinds = Dictionary(found.map { ($0.name, $0.kind) }, uniquingKeysWith: { a, _ in a })
        #expect(kinds["Work"] == .obsidian)
        #expect(kinds["Vault"] == .obsidian)
        #expect(kinds["inner"] == nil)
        #expect(kinds["Graph"] == .logseq)
        #expect(kinds["Plain"] == .markdown)
        #expect(kinds["Export"] == .notion)
        #expect(kinds["repo"] == nil)
    }

    @Test func writeGuard() throws {
        let vault = try temp()
        defer { try? FileManager.default.removeItem(at: vault) }
        let source = BrainSource(kind: .obsidian, name: "V", path: vault.path)
        var connection = BrainConnection(source: source, access: .readWrite, todo: .note(BrainConnection.defaultTodoNote))
        #expect(connection.mayWrite(vault.appendingPathComponent("ZEUS/To-do.md")))
        #expect(connection.mayWrite(vault.appendingPathComponent("ZEUS/Inbox/2026-10-31 capture.md")))
        #expect(!connection.mayWrite(vault.appendingPathComponent("Projects/Plan.md")))
        #expect(!connection.mayWrite(vault.appendingPathComponent("ZEUS/Inbox/../../Projects/Plan.md")))
        connection.access = .readOnly
        #expect(!connection.mayWrite(vault.appendingPathComponent("ZEUS/To-do.md")))
        #expect(BrainConnection(source: source, todo: .note("../escape.md")).todoURL() == nil)
    }

    @Test func dailyNotePath() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Sao_Paulo")!
        let date = calendar.date(from: DateComponents(year: 2026, month: 3, day: 7, hour: 12))!
        #expect(DailyNoteConfig().relativePath(for: date, calendar: calendar) == "2026-03-07.md")
        #expect(DailyNoteConfig(folder: "/Daily/", format: "YYYY/MM/[Day] D").relativePath(for: date, calendar: calendar) == "Daily/2026/03/Day 7.md")
        let vault = try temp()
        defer { try? FileManager.default.removeItem(at: vault) }
        try touch(vault.appendingPathComponent(".obsidian/daily-notes.json"), #"{"folder":"Journal","format":"YYYY-MM-DD"}"#)
        #expect(DailyNoteConfig.read(vault: vault) == DailyNoteConfig(folder: "Journal", format: "YYYY-MM-DD"))
    }

    @Test func ranking() {
        let terms = NoteRanker.terms("What did I decide about the pricing for Acme?")
        #expect(terms == ["decide", "pricing", "acme"])
        let hit = NoteRanker.rank(title: "Acme", path: "/v/Acme.md", text: "# Acme\nWe agreed pricing at 40 per seat.\nOther", terms: terms)
        #expect(hit?.snippet == "We agreed pricing at 40 per seat.")
        #expect((hit?.score ?? 0) >= 5)
        #expect(NoteRanker.rank(title: "x", path: "", text: "nothing", terms: terms) == nil)
    }
}
