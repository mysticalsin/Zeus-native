import Foundation
import Testing
@testable import ZeusCore

@Suite("Dictation QA fixes: corrupt history metadata")
struct DictationCorruptHistoryTests {
    /// A fresh temp folder, resolved with realpath(3) so paths compare equal.
    private func makeRoot() throws -> URL {
        let base = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("zeus-dictation-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        guard let resolved = realpath(base.path, nil) else { return base }
        defer { free(resolved) }
        return URL(fileURLWithPath: String(cString: resolved), isDirectory: true)
    }

    private func record(_ id: String, daysAgo: Int = 0) -> DictationRecord {
        DictationRecord(id: id, datetime: Date().addingTimeInterval(-Double(daysAgo) * 86_400),
                        duration: 1000, processingTime: 100, modeKey: "voice", modeName: "Voice",
                        rawResult: "hello", result: "hello")
    }

    private func writeCorrupt(_ root: URL, id: String) throws -> URL {
        let folder = root.appendingPathComponent("history/\(id)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let meta = folder.appendingPathComponent("meta.json")
        try Data("{ not json".utf8).write(to: meta)
        return meta
    }

    @Test func corruptMetadataIsMovedAsideAndReported() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = DictationStore(root: root)
        try store.save(record("good"))
        let meta = try writeCorrupt(root, id: "bad")

        let load = store.loadHistory()
        #expect(load.records.map(\.id) == ["good"])
        #expect(load.problems.count == 1)
        #expect(!FileManager.default.fileExists(atPath: meta.path))
        let backup = try #require(load.problems.first)
        #expect(backup.lastPathComponent.hasPrefix("meta.json."))
        #expect(backup.pathExtension == "corrupt")
        #expect(try Data(contentsOf: backup) == Data("{ not json".utf8))
        let permissions = try FileManager.default.attributesOfItem(atPath: backup.path)[.posixPermissions] as? NSNumber
        #expect(permissions?.intValue == 0o600)
    }

    @Test func cleanHistoryReportsNoProblem() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = DictationStore(root: root)
        try store.save(record("one"))
        try FileManager.default.createDirectory(at: root.appendingPathComponent("history/empty"), withIntermediateDirectories: true)
        let load = store.loadHistory()
        #expect(load.isClean)
        #expect(load.records.count == 1)
    }

    @Test func pruneNeverRunsFromAFailedLoad() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = DictationStore(root: root)
        try store.save(record("old", daysAgo: 100))
        _ = try writeCorrupt(root, id: "bad")

        let removed = store.prune(olderThanDays: 30)
        let remaining = store.history().map(\.id)
        #expect(removed == 0)
        #expect(remaining == ["old"])
    }

    @Test func pruneWorksOnceTheHistoryIsClean() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = DictationStore(root: root)
        try store.save(record("old", daysAgo: 100))
        try store.save(record("new"))
        let removed = store.prune(olderThanDays: 30)
        let remaining = store.history().map(\.id)
        #expect(removed == 1)
        #expect(remaining == ["new"])
    }

    @Test func secondBackupNeverOverwritesTheFirst() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = DictationStore(root: root)
        let stamp = Date(timeIntervalSince1970: 1_800_000_000)
        let meta = try writeCorrupt(root, id: "bad")
        let first = store.loadHistory(now: stamp).problems
        try Data("{ second".utf8).write(to: meta)
        let second = store.loadHistory(now: stamp).problems
        #expect(first.count == 1 && second.count == 1)
        #expect(first[0] != second[0])
        #expect(try Data(contentsOf: first[0]) == Data("{ not json".utf8))
    }
}

@Suite("Dictation QA fixes: text transforms")
struct DictationQAFixTests {
    // MARK: Self-correction only on clear correction patterns

    @Test func ordinaryIMeanKeepsEveryWord() {
        #expect(TranscriptPolish.selfCorrect("It works, I mean, it's fine.") == "It works, I mean, it's fine.")
    }

    @Test func ordinarySorryKeepsEveryWord() {
        #expect(TranscriptPolish.selfCorrect("I'm sorry, I'm late.") == "I'm sorry, I'm late.")
        #expect(TranscriptPolish.prepareForInsert("I'm sorry, I'm late.") == "I'm sorry, I'm late.")
    }

    @Test func ordinaryActuallyKeepsEveryWord() {
        #expect(TranscriptPolish.selfCorrect("It was good, actually, and cheap") == "It was good, actually, and cheap")
    }

    @Test func restartedPhraseStillCorrects() {
        #expect(TranscriptPolish.selfCorrect("send it to Paul, sorry, to Marc") == "send it to Marc")
    }

    @Test func makeThatStillCorrects() {
        #expect(TranscriptPolish.selfCorrect("meet at 3pm, make that 4pm") == "meet at 4pm")
    }

    // MARK: Spoken punctuation only in command positions

    @Test func nounUsesOfPointAndPeriodSurvive() {
        #expect(SpokenDictationMarkup.apply("The main point is speed") == "The main point is speed")
        #expect(SpokenDictationMarkup.apply("a period of time") == "a period of time")
        #expect(SpokenDictationMarkup.apply("what is the point") == "what is the point")
        #expect(SpokenDictationMarkup.apply("at this point") == "at this point")
    }

    @Test func periodAtTheEndBecomesAStop() {
        #expect(SpokenDictationMarkup.apply("That is all period") == "That is all.")
        #expect(SpokenDictationMarkup.apply("Send it, period.") == "Send it.")
        #expect(SpokenDictationMarkup.apply("period") == ".")
    }

    @Test func literalKeepsTheWord() {
        #expect(SpokenDictationMarkup.apply("I said literal period") == "I said period")
    }

    @Test func unambiguousCommandsStillWork() {
        #expect(SpokenDictationMarkup.apply("Done full stop") == "Done.")
        #expect(SpokenDictationMarkup.apply("Really question mark") == "Really?")
    }
}
