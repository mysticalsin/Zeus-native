import Foundation
import Testing
@testable import ZeusCore

/// S06-17. Model and voice downloads share a 10-minute cap. The 45 s, 20 s and 8 s request
/// timeouts stay as they are. The clock is injected.
@Suite("Download cap")
struct DownloadCapTests {
    @Test func fortyFiveTwentyAndEightSecondsDoNotEndTheDownload() {
        #expect(DownloadCap.requestTimeouts == [45, 20, 8])
        #expect(DownloadCap.overall == 10 * 60)
        var session = DownloadSession()
        #expect(session.start(.model, now: 0).isEmpty)
        for mark in [8.0, 20.0, 45.0, 599.0] {
            #expect(session.advance(to: mark).isEmpty)
            #expect(session.phase == .running(kind: .model, startedAt: 0))
            #expect(session.bar.message == nil)
        }
        let effects = session.advance(to: 600)
        #expect(effects == [.cancelAndRemovePartials, .showTookTooLong])
        #expect(session.phase == .tookTooLong(kind: .model))
        #expect(session.bar.message == DownloadBarState.tookTooLong)
        #expect(session.bar.retryTitle == DownloadBarState.retry)
        #expect(DownloadBarState.tookTooLong == "This download took too long.")
        #expect(DownloadBarState.retry == "Retry")
    }

    @Test func retryRestartsTheSameKind() {
        var session = DownloadSession()
        _ = session.start(.voice, now: 10)
        _ = session.advance(to: 610)
        #expect(session.phase == .tookTooLong(kind: .voice))
        let effects = session.retry(now: 700)
        #expect(effects == [.restart(.voice)])
        #expect(session.phase == .running(kind: .voice, startedAt: 700))
        #expect(session.bar.message == nil)
        #expect(session.advance(to: 1_299).isEmpty)
        #expect(session.advance(to: 1_300) == [.cancelAndRemovePartials, .showTookTooLong])
    }

    @Test func retryDoesNothingUnlessTheDownloadTookTooLong() {
        var session = DownloadSession()
        #expect(session.retry(now: 0).isEmpty)
        _ = session.start(.model, now: 0)
        #expect(session.retry(now: 1).isEmpty)
        #expect(session.phase == .running(kind: .model, startedAt: 0))
        _ = session.finish(now: 30)
        #expect(session.retry(now: 31).isEmpty)
        #expect(session.phase == .finished(kind: .model))
    }

    @Test func finishingInsideTheCapShowsNoRetry() {
        var session = DownloadSession()
        _ = session.start(.model, now: 0)
        #expect(session.finish(now: 45).isEmpty)
        #expect(session.phase == .finished(kind: .model))
        #expect(session.bar.message == nil)
        #expect(session.advance(to: 10_000).isEmpty)
    }

    @Test func cancelRemovesPartialsWithoutSayingTookTooLong() {
        var session = DownloadSession()
        _ = session.start(.voice, now: 0)
        #expect(session.cancel(now: 20) == [.cancelAndRemovePartials])
        #expect(session.phase == .cancelled(kind: .voice))
        #expect(session.bar.message == nil)
        #expect(session.advance(to: 10_000).isEmpty)
    }

    @Test func modelAndVoiceShareTheTenMinuteCap() {
        for kind in [DownloadKind.model, .voice] {
            var session = DownloadSession()
            _ = session.start(kind, now: 5)
            #expect(session.advance(to: 604).isEmpty)
            #expect(session.advance(to: 605) == [.cancelAndRemovePartials, .showTookTooLong])
            #expect(session.phase == .tookTooLong(kind: kind))
        }
    }

    @Test func removingPartialFilesDeletesTheFileAndTheFolder() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("zeus-partial-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("voice.partial")
        try Data("partial".utf8).write(to: file)
        let missing = directory.appendingPathComponent("gone.partial")
        let left = PartialFiles.remove([file, missing, directory])
        #expect(left.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: file.path))
        #expect(!FileManager.default.fileExists(atPath: directory.path))
    }

    @Test func theRunnerDeletesAPartialWhenTheClockPassesTenMinutes() async throws {
        let clock = ManualClock(0)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("zeus-cap-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let partial = directory.appendingPathComponent("model.partial")
        let task = Task {
            await DownloadRunner.run(kind: .model, clock: { clock.time }, partials: { [partial] }) {
                try Data("partial".utf8).write(to: partial)
                while !Task.isCancelled { try await Task.sleep(nanoseconds: 5_000_000) }
            }
        }
        try await Task.sleep(nanoseconds: 40_000_000)
        clock.time = 600
        let result = await task.value
        #expect(result == .tookTooLong)
        #expect(!FileManager.default.fileExists(atPath: partial.path))
    }

    @Test func theRunnerKeepsTheFileWhenTheDownloadFinishesInTime() async throws {
        let clock = ManualClock(0)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("zeus-cap-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let partial = directory.appendingPathComponent("model.partial")
        let result = await DownloadRunner.run(kind: .voice, clock: { clock.time }, partials: { [partial] }) {
            try Data("whole".utf8).write(to: partial)
        }
        #expect(result == .finished)
        #expect(clock.time == 0)
        #expect(try Data(contentsOf: partial) == Data("whole".utf8))
    }
}

private final class ManualClock: @unchecked Sendable {
    var time: TimeInterval
    init(_ time: TimeInterval) { self.time = time }
}
