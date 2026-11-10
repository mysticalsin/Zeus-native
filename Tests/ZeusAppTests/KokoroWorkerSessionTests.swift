import Foundation
import Testing
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif
#if ZEUS_PORTABLE_KOKORO
@testable import KokoroValidation
#else
@testable import Zeus
#endif

@Suite("Bounded local voice worker")
struct KokoroWorkerSessionTests {
    private struct Fixture {
        let directory: URL
        let launch: KokoroWorkerSession.Launch
        init() throws {
            directory = FileManager.default.temporaryDirectory.appendingPathComponent("zeus-voice-fixture-\(UUID().uuidString)-\"quoted", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
            try """
            import os,time,pathlib
            class Kokoro:
                def __init__(self,model,voices): self.root=pathlib.Path(model).parent; print("library diagnostic")
                def create(self,text,**kwargs):
                    (self.root/('started-'+text)).write_text(str(os.getpid()))
                    if text=='hang': time.sleep(30)
                    return text,16000
            """.write(to: directory.appendingPathComponent("kokoro_onnx.py"), atomically: true, encoding: .utf8)
            try """
            import struct,time
            def write(path,audio,sr,format):
                data=b'RIFF'+struct.pack('<I',40)+b'WAVEfmt '+struct.pack('<IHHIIHH',16,1,1,16000,32000,2,16)+b'data'+struct.pack('<I',4)+b'\\x00'*4
                with open(path,'wb') as f:
                    f.write(data[:16]); f.flush()
                    if audio=='partial': time.sleep(0.3)
                    f.write(data[16:])
            """.write(to: directory.appendingPathComponent("soundfile.py"), atomically: true, encoding: .utf8)
            // Run the unmodified production worker script with disposable model modules.
            // -I prevents loading installed/user Python packages; only this fixture directory is added.
            let wrapper = "import sys; sys.path.insert(0,sys.argv.pop(1)); exec(sys.argv.pop(1))"
            let files = KokoroWorker.modelFiles(in: directory)
            launch = .init(executable: "/usr/bin/python3", arguments: ["-I", "-c", wrapper, directory.path,
                KokoroWorker.workerScript(modelDir: directory), files.onnx.path, files.voices.path])
        }
        func session(timeout: TimeInterval = 3, idle: TimeInterval = 120) -> KokoroWorkerSession {
            let launch = launch
            return KokoroWorkerSession(configuration: { launch }, requestTimeout: timeout, idleTimeout: idle, temporaryDirectory: directory)
        }
        func remove() { try? FileManager.default.removeItem(at: directory) }
    }

    private func wait(_ condition: () async -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while !(await condition()), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(5)) }
        try #require(await condition())
    }

    @Test func productionWorkerPublishesOnlyACompleteAcknowledgedWAV() async throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        let session = fixture.session()
        let task = Task { await session.render("partial", voice: "synthetic", speed: 1) }
        try await wait {
            let items = (try? FileManager.default.contentsOfDirectory(at: fixture.directory, includingPropertiesForKeys: nil)) ?? []
            return items.contains { FileManager.default.fileExists(atPath: $0.appendingPathComponent("audio.wav.partial").path) }
        }
        #expect(await session.pendingRequestCount == 1)
        let items = try FileManager.default.contentsOfDirectory(at: fixture.directory, includingPropertiesForKeys: nil)
        #expect(!items.contains { $0.pathExtension == "wav" })
        let result = try #require(await task.value)
        #expect(try Data(contentsOf: result).count == 48)
        #expect(try FileManager.default.attributesOfItem(atPath: result.path)[.posixPermissions] as? Int == 0o600)
        #expect(!(try FileManager.default.contentsOfDirectory(atPath: fixture.directory.path)).contains { $0.hasPrefix("zeus-kokoro-work-") })
        await session.close()
    }

    @Test func cancellingSynthesisReturnsNoArtifactAndStopsItsWorker() async throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        let session = fixture.session()
        let task = Task { await session.render("hang", voice: "synthetic", speed: 1) }
        let marker = fixture.directory.appendingPathComponent("started-hang")
        try await wait { FileManager.default.fileExists(atPath: marker.path) }
        let pid = try #require(Int32(try String(contentsOf: marker, encoding: .utf8)))
        let began = ContinuousClock.now
        task.cancel()
        #expect(await task.value == nil)
        #expect(began.duration(to: .now) < .milliseconds(500))
        await session.close()
        #expect(kill(pid, 0) == -1 && errno == ESRCH)
        #expect(!(try FileManager.default.contentsOfDirectory(atPath: fixture.directory.path)).contains { $0.hasPrefix("zeus-kokoro-") })
    }

    @Test func pendingAdmissionIsBoundedAndNeverReplaysARejectedRequest() async throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        let session = fixture.session()
        let first = Task { await session.render("hang", voice: "synthetic", speed: 1) }
        try await wait { await session.pendingRequestCount == 1 }
        #expect(await session.render("second", voice: "synthetic", speed: 1) == nil)
        #expect(await session.pendingRequestCount == 1)
        first.cancel(); #expect(await first.value == nil)
        await session.close()
        #expect(!FileManager.default.fileExists(atPath: fixture.directory.appendingPathComponent("started-second").path))
    }

    @Test func deadlineIncludesStartupAndANonReadingWorker() async throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        let session = KokoroWorkerSession(configuration: { .init(executable: "/bin/sleep", arguments: ["30"]) },
                                          requestTimeout: 0.1, temporaryDirectory: fixture.directory)
        let began = ContinuousClock.now
        #expect(await session.render(String(repeating: "x", count: KokoroWorkerSession.maximumTextBytes), voice: "synthetic", speed: 1) == nil)
        #expect(began.duration(to: .now) < .milliseconds(500))
        await session.close()
        #expect(!(try FileManager.default.contentsOfDirectory(atPath: fixture.directory.path)).contains { $0.hasPrefix("zeus-kokoro-") })
    }

    @Test func malformedAndOversizedRepliesEndTheWorker() async throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        for script in ["printf 'not-json\\n'", "printf '{\"id\":'", "exec /bin/dd if=/dev/zero bs=32768 count=2"] {
            let session = KokoroWorkerSession(configuration: { .init(executable: "/bin/sh", arguments: ["-c", script]) }, temporaryDirectory: fixture.directory)
            #expect(await session.render("test", voice: "synthetic", speed: 1) == nil)
            await session.close()
            #expect(await session.pendingRequestCount == 0)
        }
    }

    @Test func wrongIdentityWrongPathAndSymlinkCannotPublish() async throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        for mode in ["id", "path", "symlink", "partial", "invalid-pcm"] {
            let script = """
            import sys,json,os,struct
            req=json.loads(sys.stdin.readline())
            data=b'RIFF'+struct.pack('<I',40)+b'WAVE'+b'0'*36
            if sys.argv[1]=='symlink':
                outside=req['out']+'.target';open(outside,'wb').write(data);os.symlink(outside,req['out'])
            else: open(req['out'],'wb').write(data[:44] if sys.argv[1]=='partial' else data)
            print(json.dumps({'id': 'wrong' if sys.argv[1]=='id' else req['id'], 'out': 'wrong' if sys.argv[1]=='path' else req['out'],'ok':True}),flush=True)
            """
            let session = KokoroWorkerSession(configuration: { .init(executable: "/usr/bin/python3", arguments: ["-I", "-c", script, mode]) }, temporaryDirectory: fixture.directory)
            #expect(await session.render("test", voice: "synthetic", speed: 1) == nil)
            await session.close()
        }
    }

    @Test func idleWorkerReleasesItsProcessAndClosedSessionCannotRestart() async throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        let session = fixture.session(idle: 0.05)
        let first = try #require(await session.render("first", voice: "synthetic", speed: 1))
        #expect(try Data(contentsOf: first).count == 48)
        try await wait { !(await session.isRunning) }
        // Explicitly close after observing idle shutdown; it also joins the bounded cleanup.
        await session.close()
        #expect(await session.render("closed", voice: "synthetic", speed: 1) == nil)
    }

    @Test func invalidTextAndSpeedNeverStartAWorker() async throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        let session = fixture.session()
        #expect(await session.render("", voice: "synthetic", speed: 1) == nil)
        #expect(await session.render(String(repeating: "x", count: KokoroWorkerSession.maximumTextBytes + 1), voice: "synthetic", speed: 1) == nil)
        #expect(await session.render("test", voice: "synthetic", speed: .nan) == nil)
        #expect(await session.isRunning == false)
        await session.close()
    }
    private final class StartupProbe: @unchecked Sendable {
        let lock = NSLock()
        let gate = DispatchSemaphore(value: 0)
        private var calls = 0
        var count: Int { lock.withLock { calls } }
        func run(_ launch: KokoroWorkerSession.Launch) -> KokoroWorkerSession.Launch? {
            lock.withLock { calls += 1 }
            guard gate.wait(timeout: .now() + 2) == .success else { return nil }
            return launch
        }
    }

    @Test func cancellationDuringSetupDoesNotCreateAnotherProbeOrReplayTheOldText() async throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        let probe = StartupProbe(), launch = fixture.launch
        let session = KokoroWorkerSession(configuration: { probe.run(launch) }, temporaryDirectory: fixture.directory)
        let first = Task { await session.render("first", voice: "synthetic", speed: 1) }
        try await wait { probe.count == 1 }
        first.cancel(); #expect(await first.value == nil)
        let second = Task { await session.render("second", voice: "synthetic", speed: 1) }
        try await wait { await session.pendingRequestCount == 1 }
        #expect(probe.count == 1)
        probe.gate.signal()
        let result = try #require(await second.value)
        #expect(try Data(contentsOf: result).count == 48)
        #expect(!FileManager.default.fileExists(atPath: fixture.directory.appendingPathComponent("started-first").path))
        #expect(FileManager.default.fileExists(atPath: fixture.directory.appendingPathComponent("started-second").path))
        await session.close()
    }

    @Test func cancelledPartialWriteCannotLeaveAnAudioArtifact() async throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        let session = fixture.session()
        let task = Task { await session.render("partial", voice: "synthetic", speed: 1) }
        try await wait {
            let items = (try? FileManager.default.contentsOfDirectory(at: fixture.directory, includingPropertiesForKeys: nil)) ?? []
            return items.contains { FileManager.default.fileExists(atPath: $0.appendingPathComponent("audio.wav.partial").path) }
        }
        task.cancel(); #expect(await task.value == nil)
        await session.close()
        #expect(!(try FileManager.default.contentsOfDirectory(atPath: fixture.directory.path)).contains { $0.hasPrefix("zeus-kokoro-") })
    }

    private func wav(_ samples: [UInt8] = [0, 0, 0, 0]) -> Data {
        var data = Data("RIFF".utf8)
        func u16(_ value: UInt16) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        func u32(_ value: UInt32) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        u32(UInt32(36 + samples.count)); data.append(contentsOf: "WAVEfmt ".utf8)
        u32(16); u16(1); u16(1); u32(16_000); u32(32_000); u16(2); u16(16)
        data.append(contentsOf: "data".utf8); u32(UInt32(samples.count)); data.append(contentsOf: samples)
        return data
    }

    @Test func descriptorPublicationCannotBeSubstitutedByAReplacedPath() throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        let source = fixture.directory.appendingPathComponent("source.wav")
        let target = fixture.directory.appendingPathComponent("published.wav")
        let original = wav([1, 0, 2, 0])
        try original.write(to: source)
        let descriptor = open(source.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        try #require(descriptor >= 0)
        defer {
            #if canImport(Darwin)
            Darwin.close(descriptor)
            #else
            Glibc.close(descriptor)
            #endif
        }
        try FileManager.default.removeItem(at: source)
        try wav([3, 0, 4, 0]).write(to: source)
        #expect(KokoroWAVArtifact.publish(descriptor: descriptor, to: target, maximumBytes: 1024))
        #expect(try Data(contentsOf: target) == original)
        // Exclusive publication cannot overwrite an existing result.
        #expect(!KokoroWAVArtifact.publish(source, to: target, maximumBytes: 1024))
        #expect(try Data(contentsOf: target) == original)
    }

    @Test func invalidPCMChunkBoundsAndAlignmentCannotBePublished() throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        var badRate = wav(); badRate[28] = 1
        var missingFormat = wav(); missingFormat.replaceSubrange(12..<16, with: Data("JUNK".utf8))
        var truncatedData = wav(); truncatedData[40] = 8
        var invalidFormat = wav(); invalidFormat[20] = 3
        var missingChunkBody = Data("RIFF".utf8); missingChunkBody.append(contentsOf: [36,0,0,0]); missingChunkBody.append(contentsOf: "WAVEJUNK".utf8)
        missingChunkBody.append(contentsOf: [16,0,0,0]); missingChunkBody.append(Data(repeating: 0, count: 16)); missingChunkBody.append(contentsOf: "fmt ".utf8); missingChunkBody.append(contentsOf: [16,0,0,0])
        for (index, data) in [badRate, missingFormat, truncatedData, invalidFormat, missingChunkBody].enumerated() {
            let source = fixture.directory.appendingPathComponent("bad-\(index).wav")
            let target = fixture.directory.appendingPathComponent("must-not-publish-\(index).wav")
            try data.write(to: source)
            #expect(!KokoroWAVArtifact.publish(source, to: target, maximumBytes: 1024))
            #expect(!FileManager.default.fileExists(atPath: target.path))
        }
    }

    private final class CopyStop: @unchecked Sendable {
        private let lock = NSLock()
        private var checks = 0
        func shouldStop() -> Bool { lock.withLock { checks += 1; return checks >= 3 } }
    }

    @Test func cancellationDuringArtifactCopyRemovesTheUnpublishedTarget() throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        let source = fixture.directory.appendingPathComponent("source.wav")
        let target = fixture.directory.appendingPathComponent("cancelled.wav")
        let audio = wav([UInt8](repeating: 0, count: 65_536))
        try audio.write(to: source)
        let cancellation = CopyStop()
        let published = KokoroWAVArtifact.publish(source, to: target, maximumBytes: 100_000,
                                                  shouldStop: { cancellation.shouldStop() })
        #expect(!published)
        #expect(!FileManager.default.fileExists(atPath: target.path))
        #expect(try Data(contentsOf: source) == audio)
    }

}
