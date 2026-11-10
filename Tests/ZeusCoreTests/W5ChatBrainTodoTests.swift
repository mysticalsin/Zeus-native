import Foundation
import Testing
@testable import ZeusCore

private struct RaceBoom: Error, Equatable {}

private func scratchDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("zeus-w5-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}

@Suite("To-do store safety")
struct TodoStoreSafetyTests {
    @Test func missingFileIsAFreshStartWithoutNotice() throws {
        let directory = try scratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let sync = TodoSync(storeFile: directory.appendingPathComponent("todos.json"))
        #expect(sync.loadNotice == nil)
        #expect(sync.list.items.isEmpty)
    }

    @Test func corruptFileIsMovedAsideAndNeverOverwritten() throws {
        let directory = try scratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("todos.json")
        let garbage = "{ this is not a to-do list"
        try garbage.write(to: file, atomically: true, encoding: .utf8)

        var sync = TodoSync(storeFile: file)
        #expect(sync.loadNotice != nil)
        #expect(sync.list.items.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: file.path))

        let kept = try FileManager.default.contentsOfDirectory(atPath: directory.path).filter { $0.contains("corrupt") }
        #expect(kept.count == 1)
        let keptText = try String(contentsOf: directory.appendingPathComponent(kept[0]), encoding: .utf8)
        #expect(keptText == garbage)

        // A later save writes a fresh file and leaves the kept copy alone.
        _ = sync.list.add("buy milk", due: nil)
        try sync.commit()
        let after = try String(contentsOf: directory.appendingPathComponent(kept[0]), encoding: .utf8)
        #expect(after == garbage)
        #expect(FileManager.default.fileExists(atPath: file.path))
        let reloaded = TodoSync(storeFile: file)
        #expect(reloaded.list.items.count == 1)
        #expect(reloaded.loadNotice == nil)
    }

    @Test func failedSaveThrowsAndIsRecorded() throws {
        var sync = TodoSync(storeFile: URL(fileURLWithPath: "/dev/null/none/todos.json"))
        _ = sync.list.add("write report", due: nil)
        var threw = false
        do { try sync.commit() } catch { threw = true }
        #expect(threw)
        #expect(sync.saveError != nil)
    }

    @Test func unconnectedListNeverAsksForAPull() throws {
        let directory = try scratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let sync = TodoSync(storeFile: directory.appendingPathComponent("todos.json"))
        #expect(!sync.noteMayHaveChanged())
    }
}

@Suite("Brain race failures")
struct BrainRaceFailureTests {
    @Test func raceWithNoWinnerReportsTheRealError() async {
        let failing = { AsyncThrowingStream<BrainEvent, Error> { $0.finish(throwing: RaceBoom()) } }
        let race = BrainRace.compete([("a", failing()), ("b", failing())]) { _ in }
        var caught: Error?
        do {
            for try await _ in race.events {}
        } catch {
            caught = error
        }
        #expect(caught is RaceBoom)
    }

    @Test func raceWithNoOutputAtAllStillSaysNoToken() async {
        let empty = AsyncThrowingStream<BrainEvent, Error> { $0.finish() }
        let race = BrainRace.compete([("a", empty)]) { _ in }
        var caught: Error?
        do {
            for try await _ in race.events {}
        } catch {
            caught = error
        }
        #expect(caught is BrainRace.RaceError)
    }
}
