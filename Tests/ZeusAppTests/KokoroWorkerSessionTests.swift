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
    // Fixture diagnostics contain fixed phase names, labeled clocks and PIDs only.
    // They never read production stderr or record the submitted text.
    private final class Trace: @unchecked Sendable {
        private let lock = NSLock()
        private var entries: [String] = []
        func record(_ phase: String) {
            lock.withLock {
                guard entries.count < 32 else { return }
                entries.append("uptime=\(ProcessInfo.processInfo.systemUptime) epoch=\(Date().timeIntervalSince1970) \(ProcessInfo.processInfo.processIdentifier) \(phase)")
            }
        }
        var snapshot: [String] { lock.withLock { entries } }
    }

    private final class Fixture: @unchecked Sendable {
        let identifier = UUID()
        let directory: URL
        let launch: KokoroWorkerSession.Launch
        private let trace = Trace()
        private let lock = NSLock()
        private var sessions: [KokoroWorkerSession] = []
        private var tasks: [Task<URL?, Never>] = []
        private var auxiliaryTasks: [Task<Void, Never>] = []

        private static let wrapper = """
        import sys
        sys.path.insert(0,sys.argv.pop(1))
        from fixture_trace import phase
        phase('python-entered')
        try: exec(sys.argv.pop(1))
        except BaseException:
            phase('worker-error')
            raise
        """

        init() throws {
            directory = FileManager.default.temporaryDirectory.appendingPathComponent("zeus-voice-fixture-\(identifier.uuidString)-\"quoted", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
            try """
            import os,time
            _path=os.path.join(os.path.dirname(__file__),'phases.log')
            _count=0
            def phase(name):
                global _count
                if _count>=32: return
                _count+=1
                line=f'monotonic={time.monotonic():.6f} epoch={time.time():.6f} {os.getpid()} {name}\\n'
                if os.path.exists(_path) and os.path.getsize(_path)+len(line)>4096: return
                with open(_path,'a') as output: output.write(line)
            """.write(to: directory.appendingPathComponent("fixture_trace.py"), atomically: true, encoding: .utf8)
            try """
            import os,time,pathlib
            from fixture_trace import phase
            phase('kokoro-imported')
            class Kokoro:
                def __init__(self,model,voices):
                    self.root=pathlib.Path(model).parent
                    phase('engine-ready')
                    print("library diagnostic")
                def create(self,text,**kwargs):
                    phase('create-entered')
                    (self.root/('started-'+text)).write_text(str(os.getpid()))
                    if text=='hang': time.sleep(30)
                    return text,16000
            """.write(to: directory.appendingPathComponent("kokoro_onnx.py"), atomically: true, encoding: .utf8)
            try """
            import struct,time
            from fixture_trace import phase
            phase('soundfile-imported')
            def write(path,audio,sr,format):
                data=b'RIFF'+struct.pack('<I',40)+b'WAVEfmt '+struct.pack('<IHHIIHH',16,1,1,16000,32000,2,16)+b'data'+struct.pack('<I',4)+b'\\x00'*4
                with open(path,'wb') as f:
                    f.write(data[:16]); f.flush()
                    phase('partial-written')
                    if audio=='partial': time.sleep(0.3)
                    f.write(data[16:])
                phase('audio-written')
            """.write(to: directory.appendingPathComponent("soundfile.py"), atomically: true, encoding: .utf8)
            // Run the unmodified production worker script with disposable model modules.
            // -I prevents loading installed/user Python packages; only this fixture directory is added.
            let files = KokoroWorker.modelFiles(in: directory)
            launch = .init(executable: "/usr/bin/python3", arguments: ["-I", "-c", Self.wrapper, directory.path,
                KokoroWorker.workerScript(modelDir: directory), files.onnx.path, files.voices.path])
            trace.record("fixture-ready")
        }

        func pythonLaunch(script: String, arguments: [String]) -> KokoroWorkerSession.Launch {
            .init(executable: "/usr/bin/python3", arguments: ["-I", "-c", Self.wrapper, directory.path, script] + arguments)
        }

        func session(timeout: TimeInterval = 3, idle: TimeInterval = 120,
                     configuration: (@Sendable () -> KokoroWorkerSession.Launch?)? = nil,
                     launchQueue: DispatchQueue? = nil,
                     launchProcess: @escaping @Sendable (Process) throws -> Void = { try $0.run() },
                     launchObserver: @escaping @Sendable (KokoroWorkerSession.LaunchPhase) -> Void = { _ in }) -> KokoroWorkerSession {
            let launch = launch, trace = trace
            let session = KokoroWorkerSession(configuration: {
                trace.record("configuration-entered")
                let result: KokoroWorkerSession.Launch?
                if let configuration { result = configuration() } else { result = launch }
                trace.record(result == nil ? "configuration-unavailable" : "configuration-returned")
                return result
            }, requestTimeout: timeout, idleTimeout: idle, temporaryDirectory: directory,
               launchQueue: launchQueue, launchProcess: launchProcess, launchObserver: { phase in
                   trace.record("launch-" + phase.rawValue)
                   launchObserver(phase)
               })
            lock.withLock { sessions.append(session) }
            return session
        }

        func render(_ session: KokoroWorkerSession, _ text: String,
                    didReturn: @escaping @Sendable () -> Void = {}) -> Task<URL?, Never> {
            let trace = trace
            trace.record("render-submitted")
            let task = Task {
                let result = await session.render(text, voice: "synthetic", speed: 1)
                didReturn()
                trace.record(result == nil ? "render-rejected" : "render-published")
                return result
            }
            lock.withLock { tasks.append(task) }
            return task
        }

        func ownTask(_ operation: @escaping @Sendable () async -> Void) -> Task<Void, Never> {
            let task = Task(operation: operation)
            lock.withLock { auxiliaryTasks.append(task) }
            return task
        }

        func report(test: String) {
            var entries = trace.snapshot
            // Read a bounded prefix and admit only the known fixture event grammar.
            let allowed = Set(["python-entered", "worker-error", "kokoro-imported", "engine-ready",
                               "create-entered", "soundfile-imported", "partial-written", "audio-written",
                               "request-read", "reply-ready"])
            if let handle = try? FileHandle(forReadingFrom: directory.appendingPathComponent("phases.log")) {
                defer { try? handle.close() }
                if let data = try? handle.read(upToCount: 4096) {
                    for line in String(decoding: data, as: UTF8.self).split(separator: "\n").prefix(32) {
                        let fields = line.split(separator: " ")
                        guard fields.count == 4, fields[0].hasPrefix("monotonic="), fields[1].hasPrefix("epoch="),
                              let time = Double(fields[0].dropFirst(10)), time.isFinite,
                              let epoch = Double(fields[1].dropFirst(6)), epoch.isFinite,
                              let pid = Int32(fields[2]), pid > 0, allowed.contains(String(fields[3])) else { continue }
                        entries.append(String(line))
                    }
                }
            }
            print("Kokoro fixture \(test) \(identifier.uuidString): \(entries.joined(separator: "; "))")
        }

        func close() async {
            let (tasks, sessions, auxiliaryTasks) = lock.withLock { (self.tasks, self.sessions, self.auxiliaryTasks) }
            tasks.forEach { $0.cancel() }
            for session in sessions { await session.close() }
            for task in tasks { _ = await task.value }
            for task in auxiliaryTasks { await task.value }
        }

        func remove() { try? FileManager.default.removeItem(at: directory) }
    }

    private func withFixture(_ test: String = #function, _ body: (Fixture) async throws -> Void) async throws {
        let fixture = try Fixture()
        do {
            try await body(fixture)
        } catch {
            fixture.report(test: test)
            await fixture.close()
            fixture.remove()
            throw error
        }
        fixture.report(test: test)
        await fixture.close()
        fixture.remove()
    }

    private func wait(_ condition: () async -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while !(await condition()), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(5)) }
        try #require(await condition())
    }

    @Test func productionWorkerPublishesOnlyACompleteAcknowledgedWAV() async throws {
        try await withFixture { fixture in
            let session = fixture.session()
            let task = fixture.render(session, "partial")
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
    }

    @Test func cancellingSynthesisReturnsNoArtifactAndStopsItsWorker() async throws {
        try await withFixture { fixture in
            let session = fixture.session()
            let task = fixture.render(session, "hang")
            let marker = fixture.directory.appendingPathComponent("started-hang")
            try await wait { FileManager.default.fileExists(atPath: marker.path) }
            let pid = try #require(Int32(try String(contentsOf: marker, encoding: .utf8)))
            let began = ContinuousClock.now
            task.cancel()
            #expect(await task.value == nil)
            #expect(began.duration(to: .now) < .milliseconds(500))
            await session.close()
            #expect(kill(pid, 0) == -1 && errno == ESRCH)
            let remaining = try FileManager.default.contentsOfDirectory(atPath: fixture.directory.path)
            #expect(!remaining.contains { $0.hasPrefix("zeus-kokoro-") })
        }
    }

    @Test func pendingAdmissionIsBoundedAndNeverReplaysARejectedRequest() async throws {
        try await withFixture { fixture in
            let session = fixture.session()
            let first = fixture.render(session, "hang")
            try await wait { await session.pendingRequestCount == 1 }
            #expect(await session.render("second", voice: "synthetic", speed: 1) == nil)
            #expect(await session.pendingRequestCount == 1)
            first.cancel(); #expect(await first.value == nil)
            await session.close()
            #expect(!FileManager.default.fileExists(atPath: fixture.directory.appendingPathComponent("started-second").path))
        }
    }

    @Test func deadlineIncludesStartupAndANonReadingWorker() async throws {
        try await withFixture { fixture in
            let session = fixture.session(timeout: 0.1, configuration: { .init(executable: "/bin/sleep", arguments: ["30"]) })
            let began = ContinuousClock.now
            #expect(await session.render(String(repeating: "x", count: KokoroWorkerSession.maximumTextBytes), voice: "synthetic", speed: 1) == nil)
            #expect(began.duration(to: .now) < .milliseconds(500))
            await session.close()
            let remaining = try FileManager.default.contentsOfDirectory(atPath: fixture.directory.path)
            #expect(!remaining.contains { $0.hasPrefix("zeus-kokoro-") })
        }
    }

    @Test func malformedAndOversizedRepliesEndTheWorker() async throws {
        try await withFixture { fixture in
            for script in ["printf 'not-json\\n'", "printf '{\"id\":'", "exec /bin/dd if=/dev/zero bs=32768 count=2"] {
                let session = fixture.session(timeout: 120, configuration: { .init(executable: "/bin/sh", arguments: ["-c", script]) })
                #expect(await session.render("test", voice: "synthetic", speed: 1) == nil)
                await session.close()
                #expect(await session.pendingRequestCount == 0)
            }
        }
    }

    @Test func wrongIdentityWrongPathAndSymlinkCannotPublish() async throws {
        try await withFixture { fixture in
            // The control proves this same interpreter/transport can publish the otherwise valid WAV.
            for mode in ["valid", "id", "path", "symlink", "partial", "invalid-pcm"] {
                let script = """
                import sys,json,os,struct
                from fixture_trace import phase
                req=json.loads(sys.stdin.readline())
                phase('request-read')
                mode=sys.argv[1]
                data=b'RIFF'+struct.pack('<I',40)+b'WAVEfmt '+struct.pack('<IHHIIHH',16,1,1,16000,32000,2,16)+b'data'+struct.pack('<I',4)+b'\\x00'*4
                if mode=='invalid-pcm': data=data[:20]+b'\\x03\\x00'+data[22:]
                if mode=='symlink':
                    outside=req['out']+'.target';open(outside,'wb').write(data);os.symlink(outside,req['out'])
                else: open(req['out'],'wb').write(data[:44] if mode=='partial' else data)
                reply={'id': 'wrong' if mode=='id' else req['id'], 'out': 'wrong' if mode=='path' else req['out'],'ok':True}
                with open(sys.argv[2],'w') as marker: marker.write(mode)
                phase('reply-ready')
                print(json.dumps(reply),flush=True)
                """
                let marker = fixture.directory.appendingPathComponent("reply-ready-\(mode)")
                let launch = fixture.pythonLaunch(script: script, arguments: [mode, marker.path])
                let session = fixture.session(timeout: 120, configuration: { launch })
                let result = await session.render("test", voice: "synthetic", speed: 1)
                // A startup failure, EOF or deadline cannot stand in for exercising the requested mode.
                try #require((try? String(contentsOf: marker, encoding: .utf8)) == mode)
                if mode == "valid" {
                    let published = try #require(result)
                    #expect(try Data(contentsOf: published).count == 48)
                } else {
                    #expect(result == nil)
                }
                await session.close()
            }
        }
    }

    @Test func idleWorkerReleasesItsProcessAndClosedSessionCannotRestart() async throws {
        try await withFixture { fixture in
            let session = fixture.session(idle: 0.05)
            let first = try #require(await session.render("first", voice: "synthetic", speed: 1))
            #expect(try Data(contentsOf: first).count == 48)
            try await wait { !(await session.isRunning) }
            // Explicitly close after observing idle shutdown; it also joins the bounded cleanup.
            await session.close()
            #expect(await session.render("closed", voice: "synthetic", speed: 1) == nil)
        }
    }

    @Test func invalidTextAndSpeedNeverStartAWorker() async throws {
        try await withFixture { fixture in
            let session = fixture.session()
            #expect(await session.render("", voice: "synthetic", speed: 1) == nil)
            #expect(await session.render(String(repeating: "x", count: KokoroWorkerSession.maximumTextBytes + 1), voice: "synthetic", speed: 1) == nil)
            #expect(await session.render("test", voice: "synthetic", speed: .nan) == nil)
            #expect(await session.isRunning == false)
            await session.close()
        }
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
        try await withFixture { fixture in
            let probe = StartupProbe(), launch = fixture.launch
            let session = fixture.session(timeout: 120, configuration: { probe.run(launch) })
            let first = fixture.render(session, "first")
            try await wait { probe.count == 1 }
            first.cancel(); #expect(await first.value == nil)
            let second = fixture.render(session, "second")
            try await wait { await session.pendingRequestCount == 1 }
            #expect(probe.count == 1)
            probe.gate.signal()
            let result = try #require(await second.value)
            #expect(try Data(contentsOf: result).count == 48)
            #expect(!FileManager.default.fileExists(atPath: fixture.directory.appendingPathComponent("started-first").path))
            #expect(FileManager.default.fileExists(atPath: fixture.directory.appendingPathComponent("started-second").path))
            await session.close()
        }
    }

    @Test func cancelledPartialWriteCannotLeaveAnAudioArtifact() async throws {
        try await withFixture { fixture in
            let session = fixture.session()
            let task = fixture.render(session, "partial")
            try await wait {
                let items = (try? FileManager.default.contentsOfDirectory(at: fixture.directory, includingPropertiesForKeys: nil)) ?? []
                return items.contains { FileManager.default.fileExists(atPath: $0.appendingPathComponent("audio.wav.partial").path) }
            }
            task.cancel(); #expect(await task.value == nil)
            await session.close()
            let remaining = try FileManager.default.contentsOfDirectory(atPath: fixture.directory.path)
            #expect(!remaining.contains { $0.hasPrefix("zeus-kokoro-") })
        }
    }

    private final class LaunchProbe: @unchecked Sendable {
        enum Failure: Error { case afterSpawn }
        private let lock = NSLock()
        private let gate = DispatchSemaphore(value: 0)
        private var didEnter = false
        private var didLeave = false
        private var runCalls = 0
        private var launchedPID: Int32?
        private weak var observedProcess: Process?
        private var closeResult: Bool?
        private var events: [KokoroWorkerSession.LaunchPhase] = []

        var entered: Bool { lock.withLock { didEnter } }
        var leftGate: Bool { lock.withLock { didLeave } }
        var calls: Int { lock.withLock { runCalls } }
        var pid: Int32? { lock.withLock { launchedPID } }
        var processReleased: Bool { lock.withLock { observedProcess == nil } }
        var closedAfterRun: Bool? { lock.withLock { closeResult } }
        var skipped: Bool { lock.withLock { events.contains(.skipped) } }

        func hold() {
            lock.withLock { didEnter = true }
            _ = gate.wait(timeout: .now() + 1)
            lock.withLock { didLeave = true }
        }
        func release() { gate.signal() }
        func observe(_ event: KokoroWorkerSession.LaunchPhase) {
            lock.withLock { if events.count < 16 { events.append(event) } }
        }
        func didClose() { lock.withLock { closeResult = didLeave && launchedPID != nil } }
        func run(_ process: Process, held: Bool = false, failAfterSpawn: Bool = false) throws {
            lock.withLock { runCalls += 1; observedProcess = process }
            if held { hold() }
            try process.run()
            lock.withLock { launchedPID = process.processIdentifier }
            if failAfterSpawn { throw Failure.afterSpawn }
        }
    }

    private func launchReader(_ fixture: Fixture) -> KokoroWorkerSession.Launch {
        let marker = fixture.directory.appendingPathComponent("launch-request-received")
        return .init(executable: "/bin/sh", arguments: ["-c",
            "while IFS= read -r line; do printf received > \"$1\"; done", "fixture", marker.path])
    }

    private func requireLateChildReaped(_ probe: LaunchProbe, fixture: Fixture) throws {
        let pid = try #require(probe.pid)
        #expect(kill(pid, 0) == -1 && errno == ESRCH)
        #expect(!FileManager.default.fileExists(atPath: fixture.directory.appendingPathComponent("launch-request-received").path))
    }

    @Test func deadlineDuringLaunchReturnsBeforeRunnerAndReapsLateChild() async throws {
        try await withFixture { fixture in
            let probe = LaunchProbe()
            defer { probe.release() }
            let queue = DispatchQueue(label: "zeus.test.launch-deadline")
            let launch = launchReader(fixture)
            let session = fixture.session(timeout: 0.1, configuration: { launch }, launchQueue: queue,
                                          launchProcess: { try probe.run($0, held: true) })
            let began = ContinuousClock.now
            let request = fixture.render(session, "deadline")
            try await wait { probe.entered }
            #expect(await request.value == nil)
            #expect(began.duration(to: .now) < .milliseconds(500))
            #expect(!probe.leftGate)
            let replacementBegan = ContinuousClock.now
            #expect(await session.render("replacement", voice: "synthetic", speed: 1) == nil)
            #expect(replacementBegan.duration(to: .now) < .milliseconds(500))
            #expect(await session.pendingRequestCount == 0)
            #expect(probe.calls == 1)
            probe.release()
            await session.close()
            try requireLateChildReaped(probe, fixture: fixture)
            try await wait { probe.processReleased }
            #expect(await session.render("closed", voice: "synthetic", speed: 1) == nil)
        }
    }

    @Test func cancellationDuringLaunchReturnsBeforeRunnerAndReapsLateChild() async throws {
        try await withFixture { fixture in
            let probe = LaunchProbe()
            defer { probe.release() }
            let queue = DispatchQueue(label: "zeus.test.launch-cancellation")
            let launch = launchReader(fixture)
            let session = fixture.session(configuration: { launch }, launchQueue: queue,
                                          launchProcess: { try probe.run($0, held: true) })
            let request = fixture.render(session, "cancel")
            try await wait { probe.entered }
            let began = ContinuousClock.now
            request.cancel()
            #expect(await request.value == nil)
            #expect(began.duration(to: .now) < .milliseconds(500))
            #expect(!probe.leftGate)
            let replacementBegan = ContinuousClock.now
            #expect(await session.render("replacement", voice: "synthetic", speed: 1) == nil)
            #expect(replacementBegan.duration(to: .now) < .milliseconds(500))
            #expect(await session.pendingRequestCount == 0)
            #expect(probe.calls == 1)
            probe.release()
            await session.close()
            try requireLateChildReaped(probe, fixture: fixture)
            try await wait { probe.processReleased }
        }
    }

    @Test func closeDuringLaunchResolvesRequestThenJoinsLateChild() async throws {
        try await withFixture { fixture in
            let probe = LaunchProbe()
            defer { probe.release() }
            let queue = DispatchQueue(label: "zeus.test.launch-close")
            let launch = launchReader(fixture)
            let session = fixture.session(configuration: { launch }, launchQueue: queue,
                                          launchProcess: { try probe.run($0, held: true) })
            let request = fixture.render(session, "close")
            try await wait { probe.entered }
            let began = ContinuousClock.now
            let closing = fixture.ownTask {
                await session.close()
                probe.didClose()
            }
            #expect(await request.value == nil)
            #expect(began.duration(to: .now) < .milliseconds(500))
            #expect(!probe.leftGate)
            #expect(probe.closedAfterRun == nil)
            probe.release()
            await closing.value
            #expect(probe.closedAfterRun == true)
            try requireLateChildReaped(probe, fixture: fixture)
            try await wait { probe.processReleased }
            #expect(await session.render("closed", voice: "synthetic", speed: 1) == nil)
        }
    }

    @Test func expiredQueuedLaunchNeverInvokesTheProcessRunner() async throws {
        try await withFixture { fixture in
            let blocker = LaunchProbe(), probe = LaunchProbe()
            defer { blocker.release() }
            let queue = DispatchQueue(label: "zeus.test.launch-queued")
            let blockedWork = fixture.ownTask {
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    queue.async {
                        blocker.hold()
                        continuation.resume()
                    }
                }
            }
            try await wait { blocker.entered }
            let launch = launchReader(fixture)
            let session = fixture.session(timeout: 0.1, configuration: { launch }, launchQueue: queue,
                                          launchProcess: { try probe.run($0) }, launchObserver: { probe.observe($0) })
            let began = ContinuousClock.now
            let request = fixture.render(session, "queued")
            #expect(await request.value == nil)
            #expect(began.duration(to: .now) < .milliseconds(500))
            #expect(!blocker.leftGate)
            #expect(probe.calls == 0)
            let replacementBegan = ContinuousClock.now
            #expect(await session.render("replacement", voice: "synthetic", speed: 1) == nil)
            #expect(replacementBegan.duration(to: .now) < .milliseconds(500))
            #expect(await session.pendingRequestCount == 0)
            blocker.release()
            await session.close()
            await blockedWork.value
            #expect(probe.skipped)
            #expect(probe.calls == 0)
            #expect(probe.pid == nil)
            #expect(!FileManager.default.fileExists(atPath: fixture.directory.appendingPathComponent("launch-request-received").path))
        }
    }

    @Test func runnerFailureBeforeAndAfterSpawnReleasesItsOwnedProcess() async throws {
        for afterSpawn in [false, true] {
            try await withFixture { fixture in
                let probe = LaunchProbe()
                let queue = DispatchQueue(label: "zeus.test.launch-failure")
                let launch = afterSpawn ? launchReader(fixture) : KokoroWorkerSession.Launch(
                    executable: fixture.directory.appendingPathComponent("missing-executable").path, arguments: [])
                let session = fixture.session(configuration: { launch }, launchQueue: queue,
                                              launchProcess: { try probe.run($0, failAfterSpawn: afterSpawn) })
                #expect(await session.render("failure", voice: "synthetic", speed: 1) == nil)
                await session.close()
                #expect(probe.calls == 1)
                if afterSpawn {
                    try requireLateChildReaped(probe, fixture: fixture)
                } else {
                    #expect(probe.pid == nil)
                }
                // A never-started Process has no termination callback; a started
                // one must release its deliberate retention after observed exit.
                try await wait { probe.processReleased }
            }
        }
    }

    @Test func terminatedWorkerReleasesItsProcessAfterClose() async throws {
        try await withFixture { fixture in
            let probe = LaunchProbe()
            let session = fixture.session(configuration: {
                .init(executable: "/bin/sh", arguments: ["-c", "exit 0"])
            }, launchProcess: { try probe.run($0) })
            #expect(await session.render("terminated", voice: "synthetic", speed: 1) == nil)
            await session.close()
            try requireLateChildReaped(probe, fixture: fixture)
            try await wait { probe.processReleased }
        }
    }

    @Test func completedRequestCanImmediatelyReuseTheSameWorker() async throws {
        try await withFixture { fixture in
            let session = fixture.session()
            var firstPID: Int32?
            for index in 0..<4 {
                let text = "sequence-\(index)"
                let result = try #require(await session.render(text, voice: "synthetic", speed: 1))
                #expect(try Data(contentsOf: result).count == 48)
                let marker = fixture.directory.appendingPathComponent("started-" + text)
                let pid = try #require(Int32(try String(contentsOf: marker, encoding: .utf8)))
                if let firstPID { #expect(pid == firstPID) } else { firstPID = pid }
            }
            await session.close()
        }
    }

    private enum FixtureFailure: Error { case expected }

    @Test func thrownFixtureFailureJoinsRenderAndClosesWorkerBeforeRemoval() async throws {
        let proof = FileManager.default.temporaryDirectory.appendingPathComponent("zeus-cleanup-proof-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: proof) }
        let completed = Trace()
        var captured: (Fixture, KokoroWorkerSession, Task<URL?, Never>, Int32)?
        var caught = false
        do {
            try await withFixture { fixture in
                // Shell builtins only: this guard owns one process, with no descendant-cleanup claim.
                let script = """
                trap 'if [ -d "$1" ]; then printf present > "$2"; else printf removed > "$2"; fi' EXIT
                trap 'exit 0' TERM
                printf '%s' "$$" > "$1/cleanup-started"
                printf ready > "$1/cleanup-ready"
                while IFS= read -r line; do :; done
                """
                let directory = fixture.directory
                let session = fixture.session(configuration: {
                    .init(executable: "/bin/sh", arguments: ["-c", script, "fixture", directory.path, proof.path])
                })
                let task = fixture.render(session, "test", didReturn: {
                    completed.record(FileManager.default.fileExists(atPath: directory.path) ? "directory-present" : "directory-missing")
                })
                let marker = directory.appendingPathComponent("cleanup-started")
                let ready = directory.appendingPathComponent("cleanup-ready")
                // The acknowledgement follows the completed PID write; mere file existence
                // can race with the shell opening an empty output file.
                try await wait { (try? String(contentsOf: ready, encoding: .utf8)) == "ready" }
                let pid = try #require(Int32(try String(contentsOf: marker, encoding: .utf8)))
                captured = (fixture, session, task, pid)
                throw FixtureFailure.expected
            }
        } catch FixtureFailure.expected { caught = true }
        try #require(caught)
        let (fixture, session, task, pid) = try #require(captured)
        // The task callback and child EXIT trap both observed the directory before deletion.
        #expect(completed.snapshot.contains { $0.hasSuffix(" directory-present") })
        #expect(try String(contentsOf: proof, encoding: .utf8) == "present")
        #expect(await task.value == nil)
        #expect(await session.isRunning == false)
        #expect(await session.pendingRequestCount == 0)
        #expect(await session.render("closed", voice: "synthetic", speed: 1) == nil)
        #expect(kill(pid, 0) == -1 && errno == ESRCH)
        #expect(!FileManager.default.fileExists(atPath: fixture.directory.path))
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
