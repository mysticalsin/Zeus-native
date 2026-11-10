import Foundation
import Testing
@testable import ZeusCore

/// A fresh private temp folder, resolved with realpath(3) so paths compare equal under /var -> /private/var.
private func makeTempDirectory() throws -> URL {
    var template = Array((NSTemporaryDirectory() + "zeus-memqa-XXXXXX").utf8CString)
    guard mkdtemp(&template) != nil else { throw CocoaError(.fileWriteUnknown) }
    let made = String(cString: template)
    guard let resolved = realpath(made, nil) else { throw CocoaError(.fileNoSuchFile) }
    defer { free(resolved) }
    return URL(fileURLWithPath: String(cString: resolved), isDirectory: true)
}

private func mode(_ url: URL) -> Int {
    ((try? FileManager.default.attributesOfItem(atPath: url.path))?[.posixPermissions] as? NSNumber)?.intValue.masked ?? -1
}

private extension Int {
    var masked: Int { self & 0o777 }
}

@Suite("UserMemory QA fixes")
struct UserMemoryQAFixTests {
    // MARK: Commands

    @Test func rememberKeepsCasingAndPossessives() {
        let parsed = UserMemoryCommands.parse("please remember my sister's name is Ana")
        #expect(parsed?.kind == .remember("my sister's name is Ana"))
    }

    @Test func rememberThatDropsOnlyTheLeadIn() {
        #expect(UserMemoryCommands.parse("remember that I like Tea")?.kind == .remember("I like Tea"))
        #expect(UserMemoryCommands.parse("remember")?.kind == nil)
    }

    @Test func forgetThatWithATopicNamesTheTopic() {
        #expect(UserMemoryCommands.parse("forget that I'm vegan")?.kind == .forget("I'm vegan"))
        #expect(UserMemoryCommands.parse("forget that dentist is Tuesday")?.kind == .forget("dentist is Tuesday"))
        #expect(UserMemoryCommands.parse("forget about my dentist")?.kind == .forget("my dentist"))
        #expect(UserMemoryCommands.parse("forget I'm vegan")?.kind == .forget("I'm vegan"))
    }

    @Test func bareForgetStaysTheNewestCommand() {
        #expect(UserMemoryCommands.parse("forget that")?.kind == .forget("that"))
        #expect(UserMemoryCommands.parse("forget")?.kind == .forget("that"))
    }

    // MARK: Forgetting

    @Test func forgetMatchesWholeWordsAndCounts() {
        var store = UserMemoryStore()
        _ = store.rememberRule("I like tea")
        _ = store.rememberRule("My teacher is Ms Lee")
        _ = store.rememberFact("Steak night is Friday")
        #expect(store.forget(matching: "tea") == 1)
        #expect(store.rules.map(\.text) == ["My teacher is Ms Lee"])
        #expect(store.facts.count == 1)
    }

    @Test func forgetIgnoresLeadingFillerAndMatchesTheTopic() {
        var store = UserMemoryStore()
        _ = store.rememberFact("Dentist is Tuesday")
        #expect(store.forget(matching: "my dentist") == 1)
        #expect(store.facts.isEmpty)
    }

    @Test func forgetPhraseMatchesTheStoredText() {
        var store = UserMemoryStore()
        _ = store.rememberRule("I'm vegan")
        _ = store.rememberRule("Call me Sam")
        #expect(store.forget(matching: "I'm vegan") == 1)
        #expect(store.rules.map(\.text) == ["Call me Sam"])
    }

    @Test func fillerOnlyPhraseRemovesNothing() {
        var store = UserMemoryStore()
        _ = store.rememberRule("I like tea")
        #expect(store.forget(matching: "the") == 0)
        #expect(store.forget(matching: "   ") == 0)
        #expect(store.rules.count == 1)
    }

    @Test func forgetNewestDropsOnlyTheLatestEntry() {
        var store = UserMemoryStore()
        let early = Date(timeIntervalSince1970: 1_000)
        _ = store.rememberRule("old rule", at: early)
        _ = store.rememberFact("new fact", at: early.addingTimeInterval(60))
        #expect(store.forgetNewest() == 1)
        #expect(store.facts.isEmpty)
        #expect(store.rules.count == 1)
        #expect(store.forgetNewest() == 1)
        #expect(store.forgetNewest() == 0)
    }

    // MARK: Persistence

    @Test func missingFileLoadsEmptyAndSaveRoundTrips() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let persistence = UserMemoryPersistence(url: dir.appendingPathComponent("Zeus/user-memory.json"))
        #expect(try persistence.loadChecked() == UserMemoryStore())
        var store = UserMemoryStore()
        _ = store.rememberRule("I'm vegan")
        try persistence.save(store)
        #expect(try persistence.loadChecked().rules.map(\.text) == ["I'm vegan"])
    }

    @Test func savedFileIsPrivate() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("Zeus/user-memory.json")
        var store = UserMemoryStore()
        _ = store.rememberRule("I'm vegan")
        try UserMemoryPersistence(url: url).save(store)
        #expect(mode(url) == 0o600)
        #expect(mode(url.deletingLastPathComponent()) == 0o700)
    }

    @Test func permissiveExistingFilesAreRepaired() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let folder = dir.appendingPathComponent("Zeus", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path)
        let url = folder.appendingPathComponent("user-memory.json")
        let json = #"{"rules":[],"facts":[]}"#
        #expect(FileManager.default.createFile(atPath: url.path, contents: Data(json.utf8), attributes: [.posixPermissions: 0o644]))
        _ = UserMemoryPersistence(url: url).load()
        #expect(mode(url) == 0o600)
        #expect(mode(folder) == 0o700)
    }

    @Test func corruptFileIsPreservedAndNeverOverwritten() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("user-memory.json")
        let garbage = Data("{not json".utf8)
        try garbage.write(to: url)
        let persistence = UserMemoryPersistence(url: url)

        #expect(throws: UserMemoryError.self) { try persistence.loadChecked() }
        #expect(persistence.load() == UserMemoryStore()) // the lenient reader is empty, but writes nothing

        var store = UserMemoryStore()
        _ = store.rememberRule("I'm vegan")
        #expect(throws: UserMemoryError.self) { try persistence.save(store) }

        #expect(try Data(contentsOf: url) == garbage)
        #expect(try Data(contentsOf: persistence.corruptCopyURL) == garbage)
    }

    @Test func newerFormatIsNotMistakenForEmpty() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("user-memory.json")
        let newer = Data(#"{"rules":[],"facts":[{"id":"7B8C2D14-0F57-4B49-9E5B-6C3B7C0C2A11","text":"x","source":"telepathy","created":"2026-11-01T10:00:00Z"}]}"#.utf8)
        try newer.write(to: url)
        let persistence = UserMemoryPersistence(url: url)
        #expect(throws: UserMemoryError.self) { try persistence.loadChecked() }
        #expect(throws: UserMemoryError.self) { try persistence.save(UserMemoryStore()) }
        #expect(try Data(contentsOf: url) == newer)
    }

    @Test func quarantineMovesTheFileAsideSoSavingWorks() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("user-memory.json")
        try Data("oops".utf8).write(to: url)
        let persistence = UserMemoryPersistence(url: url)
        try persistence.quarantine()
        #expect(!FileManager.default.fileExists(atPath: url.path))
        var store = UserMemoryStore()
        _ = store.rememberRule("I'm vegan")
        try persistence.save(store)
        #expect(try persistence.loadChecked().rules.count == 1)
    }

    @Test func zeroByteFileIsCorruptPreservedAndNeverOverwritten() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("user-memory.json")
        try Data().write(to: url)
        let persistence = UserMemoryPersistence(url: url)
        #expect(throws: UserMemoryError.self) { try persistence.loadChecked() }
        var store = UserMemoryStore()
        _ = store.rememberRule("I'm vegan")
        #expect(throws: UserMemoryError.self) { try persistence.save(store) }
        #expect(try Data(contentsOf: url).isEmpty)
        #expect(FileManager.default.fileExists(atPath: persistence.corruptCopyURL.path))
        try persistence.quarantine()
        try persistence.save(store)
        #expect(try persistence.loadChecked().rules.count == 1)
    }

    @Test func severalMatchesNeedAChoiceAndRemoveNothing() {
        var store = UserMemoryStore()
        _ = store.rememberRule("I like tea")
        _ = store.rememberFact("Tea time is four")
        #expect(store.forgetOne(matching: "tea") == .needsChoice(["I like tea", "Tea time is four"]))
        #expect(store.rules.count == 1)
        #expect(store.facts.count == 1)
    }

    @Test func exactMatchAmongSeveralIsRemovedAlone() {
        var store = UserMemoryStore()
        _ = store.rememberRule("I like tea")
        _ = store.rememberFact("I like tea a lot")
        #expect(store.forgetOne(matching: "I like tea") == .removed(1))
        #expect(store.rules.isEmpty)
        #expect(store.facts.count == 1)
    }

    @Test func singleMatchIsRemovedAndNoMatchIsZero() {
        var store = UserMemoryStore()
        _ = store.rememberRule("I like tea")
        #expect(store.forgetOne(matching: "coffee") == .removed(0))
        #expect(store.forgetOne(matching: "tea") == .removed(1))
    }
}

@Suite("Daily brief QA fixes")
struct DailyBriefQAFixTests {
    private let summary = TodaySummary(day: "2026-11-08")

    @Test func undatedTodoIsNotDue() {
        let text = DailyBrief.text(summary: summary, events: [], zeusTodos: [TodoItem(title: "Buy milk")])
        #expect(text.contains("No to-dos are due."))
        #expect(!text.contains("Buy milk"))
    }

    @Test func todayAndOverdueAreDueAndCounted() {
        let todos = [
            TodoItem(title: "Buy milk"),
            TodoItem(title: "Call Anna", due: "2026-11-08"),
            TodoItem(title: "Pay rent", due: "2026-11-01"),
            TodoItem(title: "Next week", due: "2026-11-15"),
            TodoItem(title: "Done thing", done: true, due: "2026-11-08"),
        ]
        let text = DailyBrief.text(summary: summary, events: [], zeusTodos: todos)
        #expect(text.contains("2 to-dos, 1 overdue"))
        #expect(text.contains("Call Anna"))
        #expect(text.contains("Pay rent"))
        #expect(!text.contains("Buy milk"))
        #expect(!text.contains("Next week"))
        #expect(!text.contains("Done thing"))
    }

    @Test func emptyDueStringCountsAsUndated() {
        let text = DailyBrief.text(summary: summary, events: [], zeusTodos: [TodoItem(title: "Blank", due: "")])
        #expect(text.contains("No to-dos are due."))
    }
}
