import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
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

    @Test func aCapRemovesFilesInstalledDuringTheRunAndKeepsOlderOnes() async throws {
        let clock = ManualClock(0)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("zeus-foot-\(UUID().uuidString)", isDirectory: true)
        let tree = root.appendingPathComponent("venv", isDirectory: true)
        let kept = tree.appendingPathComponent("lib/kokoro.txt")
        try FileManager.default.createDirectory(at: kept.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("old".utf8).write(to: kept)
        let before = InstallFootprint.snapshot(tree)
        let task = Task {
            await DownloadRunner.run(kind: .model, clock: { clock.time }, partials: {
                InstallFootprint.removals(root: root, rootExisted: true, tree: tree, treeExisted: true, before: before)
            }) {
                let installed = tree.appendingPathComponent("lib/python3.12/site-packages/faster_whisper/model.bin")
                try FileManager.default.createDirectory(at: installed.deletingLastPathComponent(), withIntermediateDirectories: true)
                try Data("new".utf8).write(to: installed)
                let sibling = tree.appendingPathComponent("lib/new.txt")
                try Data("sibling".utf8).write(to: sibling)
                while !Task.isCancelled { try await Task.sleep(nanoseconds: 5_000_000) }
            }
        }
        try await Task.sleep(nanoseconds: 40_000_000)
        clock.time = 600
        let result = await task.value
        #expect(result == .tookTooLong)
        #expect(try Data(contentsOf: kept) == Data("old".utf8))
        #expect(!FileManager.default.fileExists(atPath: tree.appendingPathComponent("lib/python3.12/site-packages/faster_whisper").path))
        #expect(!FileManager.default.fileExists(atPath: tree.appendingPathComponent("lib/new.txt").path))
        try? FileManager.default.removeItem(at: root)
    }

    @Test func cancelRemovesFilesInstalledDuringTheRun() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("zeus-foot-\(UUID().uuidString)", isDirectory: true)
        let tree = root.appendingPathComponent("venv", isDirectory: true)
        try FileManager.default.createDirectory(at: tree, withIntermediateDirectories: true)
        let before = InstallFootprint.snapshot(tree)
        let installed = tree.appendingPathComponent("lib/site-packages/faster_whisper/__init__.py")
        let result = await DownloadRunner.run(kind: .model, clock: { 0 }, partials: {
            InstallFootprint.removals(root: root, rootExisted: true, tree: tree, treeExisted: true, before: before)
        }) {
            try FileManager.default.createDirectory(at: installed.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("pkg".utf8).write(to: installed)
            throw CancellationError()
        }
        #expect(result == .cancelled)
        #expect(!FileManager.default.fileExists(atPath: installed.path))
        #expect(FileManager.default.fileExists(atPath: tree.path))
        try? FileManager.default.removeItem(at: root)
    }

    @Test func aNewPythonRootIsTheOnlyRemovalWhenItDidNotExist() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("zeus-foot-\(UUID().uuidString)", isDirectory: true)
        let tree = root.appendingPathComponent("venv", isDirectory: true)
        let installed = tree.appendingPathComponent("lib/faster_whisper/model.bin")
        try FileManager.default.createDirectory(at: installed.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("pkg".utf8).write(to: installed)
        let urls = InstallFootprint.removals(root: root, rootExisted: false, tree: tree, treeExisted: false, before: [])
        #expect(urls == [root])
        #expect(PartialFiles.remove(urls).isEmpty)
        #expect(!FileManager.default.fileExists(atPath: root.path))
    }

    @Test func anExistingRootLosesOnlyANewVirtualEnvironment() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("zeus-foot-\(UUID().uuidString)", isDirectory: true)
        let note = root.appendingPathComponent("notes.txt")
        let tree = root.appendingPathComponent("venv", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("keep".utf8).write(to: note)
        try FileManager.default.createDirectory(at: tree.appendingPathComponent("lib"), withIntermediateDirectories: true)
        let urls = InstallFootprint.removals(root: root, rootExisted: true, tree: tree, treeExisted: false, before: [])
        #expect(urls == [tree])
        #expect(PartialFiles.remove(urls).isEmpty)
        #expect(try Data(contentsOf: note) == Data("keep".utf8))
        #expect(!FileManager.default.fileExists(atPath: tree.path))
        try? FileManager.default.removeItem(at: root)
    }

    @Test func theByteCapErrorTellsThePersonTheDownloadWasTooLarge() {
        let error = DownloadCapExceeded()
        #expect(error.errorDescription == "Download stopped: larger than expected")
        #expect((error as Error).localizedDescription == "Download stopped: larger than expected")
    }

    @Test func byteCapsAreThePinnedSizesPlusTwentyFivePercent() {
        #expect(PinnedModelBytes.whisperBaseEn == 147_964_211)
        #expect(PinnedModelBytes.whisperSmall == 487_601_967)
        #expect(PinnedModelBytes.whisperLargeTurboQ5 == 574_041_195)
        #expect(PinnedModelBytes.kokoroOnnx == 325_532_387)
        #expect(PinnedModelBytes.kokoroVoices == 28_214_398)
        #expect(PinnedModelBytes.cap(147_964_211) == 184_955_263)
        #expect(PinnedModelBytes.cap(487_601_967) == 609_502_458)
        #expect(PinnedModelBytes.cap(574_041_195) == 717_551_493)
        #expect(PinnedModelBytes.cap(325_532_387) == 406_915_483)
        #expect(PinnedModelBytes.cap(28_214_398) == 35_267_997)
    }

    @Test func aFakeSessionCancelsWhenExpectedLengthOrBytesWrittenPassTheCap() {
        let task = FakeDownloadTask()
        let guardRail = DownloadTransferGuard(maximumBytes: 184_955_263, allowedHosts: PinnedDownloadHosts.whisper)
        guardRail.evaluateWrite(written: 1, expected: 184_955_264, task: task)
        #expect(task.cancelCount == 1)
        #expect(guardRail.stopped)

        let within = FakeDownloadTask()
        let ok = DownloadTransferGuard(maximumBytes: 184_955_263, allowedHosts: PinnedDownloadHosts.whisper)
        ok.evaluateWrite(written: 184_955_263, expected: -1, task: within)
        #expect(within.cancelCount == 0)
        ok.evaluateWrite(written: 184_955_264, expected: -1, task: within)
        #expect(within.cancelCount == 1)
    }

    @Test func capMinusOneAndTheCapItselfDoNotCancel() {
        let cap: Int64 = 100
        let task = FakeDownloadTask()
        let guardRail = DownloadTransferGuard(maximumBytes: cap, allowedHosts: PinnedDownloadHosts.whisper)
        guardRail.evaluateWrite(written: cap - 1, expected: cap, task: task)
        #expect(task.cancelCount == 0)
        guardRail.evaluateWrite(written: cap, expected: cap, task: task)
        #expect(task.cancelCount == 0)
        let over = FakeDownloadTask()
        let overGuard = DownloadTransferGuard(maximumBytes: cap, allowedHosts: PinnedDownloadHosts.whisper)
        overGuard.evaluateWrite(written: cap + 1, expected: 10, task: over)
        #expect(over.cancelCount == 1)
    }

    @Test func redirectsRequireAnExactHostWithNoUserAndTheDefaultPort() {
        func followed(_ raw: String) -> Bool {
            let guardRail = DownloadTransferGuard(maximumBytes: 100, allowedHosts: PinnedDownloadHosts.whisper)
            let task = FakeDownloadTask()
            var request: URLRequest?
            guardRail.evaluateRedirect(URL(string: raw)!, task: task) { request = $0 }
            return request != nil
        }
        #expect(followed("https://huggingface.co/model.bin"))
        #expect(followed("https://huggingface.co:443/model.bin"))
        #expect(followed("https://evilhuggingface.co/model.bin") == false)
        #expect(followed("https://us.aws.cdn.hf.co.evil.com/model.bin") == false)
        #expect(followed("https://huggingface.co@evil.example/model.bin") == false)
        #expect(followed("https://evil.example@huggingface.co/model.bin") == false)
        #expect(followed("https://huggingface.co:444/model.bin") == false)
    }

    @Test func aFailedDownloadRemovesThePartial() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("zeus-fail-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let partial = directory.appendingPathComponent("model.partial")
        let result = await DownloadRunner.run(kind: .model, clock: { 0 }, partials: { [partial] }) {
            try Data("partial".utf8).write(to: partial)
            throw NSError(domain: "Zeus", code: 7)
        }
        guard case .failed = result else {
            Issue.record("expected failed, got \(result)")
            return
        }
        #expect(!FileManager.default.fileExists(atPath: partial.path))
    }

    @Test func theFinishedDownloadIsMovedInsideTheCallback() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("zeus-move-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("temp.bin")
        let destination = directory.appendingPathComponent("model.partial")
        try Data(count: 10).write(to: source)
        let guardRail = DownloadTransferGuard(maximumBytes: 10, allowedHosts: PinnedDownloadHosts.whisper)
        guardRail.destination = destination
        guardRail.acceptFinishedDownload(at: source)
        #expect(guardRail.keptURL == destination)
        #expect(!FileManager.default.fileExists(atPath: source.path))
        #expect(try Data(contentsOf: destination).count == 10)

        let big = directory.appendingPathComponent("big.bin")
        try Data(count: 11).write(to: big)
        let over = DownloadTransferGuard(maximumBytes: 10, allowedHosts: PinnedDownloadHosts.whisper)
        over.destination = directory.appendingPathComponent("nope.partial")
        over.acceptFinishedDownload(at: big)
        #expect(over.keptURL == nil)
        #expect(over.stopped)
        #expect(!FileManager.default.fileExists(atPath: big.path))
        #expect(!FileManager.default.fileExists(atPath: over.destination!.path))
    }

    @Test func redirectsStopAtFiveAndStayOnHttpsAllowlistedHosts() {
        let hosts = PinnedDownloadHosts.whisper
        let guardRail = DownloadTransferGuard(maximumBytes: 100, allowedHosts: hosts)
        let task = FakeDownloadTask()
        var followed = 0
        for _ in 1...5 {
            var request: URLRequest?
            guardRail.evaluateRedirect(URL(string: "https://us.aws.cdn.hf.co/model.bin")!, task: task) { request = $0 }
            if request != nil { followed += 1 }
        }
        #expect(followed == 5)
        #expect(task.cancelCount == 0)
        var sixth: URLRequest?
        guardRail.evaluateRedirect(URL(string: "https://us.aws.cdn.hf.co/model.bin")!, task: task) { sixth = $0 }
        #expect(sixth == nil)
        #expect(task.cancelCount == 1)

        let plain = DownloadTransferGuard(maximumBytes: 100, allowedHosts: hosts)
        let httpTask = FakeDownloadTask()
        var http: URLRequest?
        plain.evaluateRedirect(URL(string: "http://huggingface.co/model.bin")!, task: httpTask) { http = $0 }
        #expect(http == nil)
        #expect(httpTask.cancelCount == 1)

        let other = DownloadTransferGuard(maximumBytes: 100, allowedHosts: hosts)
        let otherTask = FakeDownloadTask()
        var foreign: URLRequest?
        other.evaluateRedirect(URL(string: "https://example.com/model.bin")!, task: otherTask) { foreign = $0 }
        #expect(foreign == nil)

        let kokoro = DownloadTransferGuard(maximumBytes: 100, allowedHosts: PinnedDownloadHosts.kokoro)
        let kokoroTask = FakeDownloadTask()
        var release: URLRequest?
        kokoro.evaluateRedirect(URL(string: "https://release-assets.githubusercontent.com/kokoro-v1.0.onnx")!, task: kokoroTask) { release = $0 }
        #expect(release != nil)
        #expect(kokoroTask.cancelCount == 0)
    }

    @Test func anUnpackLargerThanTheCapIsRefused() {
        let maximum = PinnedModelBytes.cap(PinnedModelBytes.whisperBaseEn)
        #expect(ArchiveUnpackCap.exceeds(producedBytes: maximum, maximumBytes: maximum) == false)
        #expect(ArchiveUnpackCap.exceeds(producedBytes: maximum + 1, maximumBytes: maximum))
        #expect(ArchiveUnpackCap.isArchive("ggml-base.en.bin") == false)
        #expect(ArchiveUnpackCap.isArchive("model.zip"))
    }

    @Test func aByteCapRemovesThePartialAndKeepsTheFinishedModel() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("zeus-cap-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let partial = directory.appendingPathComponent("model.partial")
        let finished = directory.appendingPathComponent("ggml-base.en.bin")
        try Data("finished".utf8).write(to: finished)
        let result = await DownloadRunner.run(kind: .model, clock: { 0 }, partials: { [partial] }) {
            try Data("partial".utf8).write(to: partial)
            throw DownloadCapExceeded()
        }
        #expect(result == .capped)
        #expect(!FileManager.default.fileExists(atPath: partial.path))
        #expect(try Data(contentsOf: finished) == Data("finished".utf8))
    }

    @Test func aFailedCleanupIsNotReportedAsCancelledOrTookTooLong() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("zeus-stuck-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let partial = directory.appendingPathComponent("model.partial")
        try Data("partial".utf8).write(to: partial)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: directory.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: directory.path)
            try? FileManager.default.removeItem(at: directory)
        }
        let cancelled = await DownloadRunner.run(kind: .model, clock: { 0 }, partials: { [partial] }) {
            throw CancellationError()
        }
        guard case .failed = cancelled else {
            Issue.record("cleanup failure was reported as \(cancelled)")
            return
        }
        #expect(FileManager.default.fileExists(atPath: partial.path))

        let clock = ManualClock(0)
        let task = Task {
            await DownloadRunner.run(kind: .model, clock: { clock.time }, partials: { [partial] }) {
                while !Task.isCancelled { try await Task.sleep(nanoseconds: 5_000_000) }
            }
        }
        try await Task.sleep(nanoseconds: 20_000_000)
        clock.time = 600
        let timed = await task.value
        guard case .failed = timed else {
            Issue.record("cleanup failure was reported as \(timed)")
            return
        }
    }

    @Test func fasterWhisperUnpackStopsPastThePinnedWheelBytes() throws {
        #expect(FasterWhisperUnpack.knownBytes == 294_567_673)
        #expect(FasterWhisperUnpack.maximumBytes == 368_209_591)
        #expect(ArchiveUnpackCap.exceeds(producedBytes: FasterWhisperUnpack.maximumBytes, maximumBytes: FasterWhisperUnpack.maximumBytes) == false)
        #expect(ArchiveUnpackCap.exceeds(producedBytes: FasterWhisperUnpack.maximumBytes + 1, maximumBytes: FasterWhisperUnpack.maximumBytes))

        let root = FileManager.default.temporaryDirectory.appendingPathComponent("zeus-unpack-\(UUID().uuidString)", isDirectory: true)
        let tree = root.appendingPathComponent("venv", isDirectory: true)
        let kept = tree.appendingPathComponent("lib/old.txt")
        try FileManager.default.createDirectory(at: kept.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(count: 10).write(to: kept)
        let before = try #require(InstallFootprint.sizeSnapshot(tree))
        try Data(count: 50).write(to: kept)
        let added = tree.appendingPathComponent("lib/site-packages/faster_whisper/pkg.py")
        try FileManager.default.createDirectory(at: added.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(Data(count: 40)).write(to: added)
        #expect(InstallFootprint.producedBytes(tree: tree, treeExisted: true, before: before) == 80)
        let missing = root.appendingPathComponent("missing")
        #expect(InstallFootprint.producedBytes(tree: missing, treeExisted: true, before: [:]) == nil)
        #expect(InstallFootprint.producedBytes(tree: missing, treeExisted: false, before: [:]) == 0)
        let blocked = root.appendingPathComponent("blocked", isDirectory: true)
        try FileManager.default.createDirectory(at: blocked, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: blocked.appendingPathComponent("hidden.txt"))
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: blocked.path)
        #expect(InstallFootprint.sizeSnapshot(blocked) == nil)
        #expect(InstallFootprint.producedBytes(tree: blocked, treeExisted: true, before: [:]) == nil)
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: blocked.path)
        try? FileManager.default.removeItem(at: root)
    }
}

private final class ManualClock: @unchecked Sendable {
    var time: TimeInterval
    init(_ time: TimeInterval) { self.time = time }
}
