import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import ZeusCore

@Suite struct LocalVoiceBackendContractTests {
    private func tone(_ value: Float) -> [Float] {
        Array(repeating: value, count: VoiceFrame.sampleCount)
    }

    @Test func everyStateAndEventHasOneOutcome() throws {
        let failure = VoiceSessionError.badFrameSize(expected: 3_200, got: 1)
        let states = VoiceSessionState.everyCase(failure: failure)
        let events = VoiceSessionEvent.everyCase(failure: failure)
        #expect(states.map(\.shape) == VoiceSessionStateShape.allCases)
        #expect(events.map(\.shape) == VoiceSessionEventShape.allCases)
        let legal: [VoiceSessionState: [VoiceSessionEvent: VoiceSessionState]] = [
            .idle: [.start: .starting, .close: .closed, .fail(failure): .failed(failure)],
            .starting: [.started: .streaming, .close: .closing, .fail(failure): .failed(failure)],
            .streaming: [.push: .streaming, .close: .closing, .fail(failure): .failed(failure)],
            .closing: [.closed: .closed, .fail(failure): .failed(failure)],
        ]
        for state in states {
            for event in events {
                if let next = legal[state]?[event] {
                    #expect(try state.next(on: event) == next)
                } else {
                    #expect(throws: VoiceSessionError.illegalTransition(from: state, event: event)) {
                        try state.next(on: event)
                    }
                }
            }
        }
    }

    @Test func startReturnsFrameZeroOf3200Samples() async throws {
        let first = tone(0.25)
        let backend = try FakeDuplexVoiceBackend(frames: [first, tone(0.5)])
        let frame = try await backend.start()
        #expect(frame.samples.count == VoiceFrame.sampleCount)
        #expect(frame.samples == first)
        #expect(await backend.state == .streaming)
    }

    @Test func aWrongSizeFrameThrows() async throws {
        let backend = try FakeDuplexVoiceBackend(frames: [tone(0.25), tone(0.5)])
        _ = try await backend.start()
        await #expect(throws: VoiceSessionError.badFrameSize(expected: 3_200, got: 3)) {
            try await backend.push(userFrame: [0, 0, 0])
        }
    }

    @Test func closeDuringStartEndsClosedAndNeverStreams() async throws {
        let gate = StartGate()
        let backend = try FakeDuplexVoiceBackend(frames: [tone(0.3)], beforeStarted: {
            await gate.markEntered()
            await gate.waitUntilReleased()
        })
        let task = Task { try await backend.start() }
        await gate.waitUntilEntered()
        #expect(await backend.state == .starting)
        await backend.close()
        #expect(await backend.state == .closing)
        await gate.release()
        await #expect(throws: VoiceSessionError.illegalTransition(from: .closed, event: .started)) {
            try await task.value
        }
        #expect(await backend.state == .closed)
        #expect(await backend.state != .streaming)
    }

    @Test func closeFromIdleRefusesALaterStart() async throws {
        let backend = try FakeDuplexVoiceBackend(frames: [tone(0.1)])
        await backend.close()
        #expect(await backend.state == .closed)
        await #expect(throws: VoiceSessionError.illegalTransition(from: .closed, event: .start)) {
            try await backend.start()
        }
    }

    @Test func aSecondCloseStaysClosed() async throws {
        let backend = try FakeDuplexVoiceBackend(frames: [tone(0.1), tone(0.2)])
        _ = try await backend.start()
        await backend.close()
        #expect(await backend.state == .closed)
        await backend.close()
        #expect(await backend.state == .closed)
    }

    @Test func aPushBeforeStartThrows() async throws {
        let backend = try FakeDuplexVoiceBackend(frames: [tone(0.25)])
        await #expect(throws: VoiceSessionError.illegalTransition(from: .idle, event: .push)) {
            try await backend.push(userFrame: tone(0.1))
        }
    }

    @Test func aPushAfterCloseThrows() async throws {
        let backend = try FakeDuplexVoiceBackend(frames: [tone(0.25), tone(0.5)])
        _ = try await backend.start()
        await backend.close()
        #expect(await backend.state == .closed)
        await #expect(throws: VoiceSessionError.illegalTransition(from: .closed, event: .push)) {
            try await backend.push(userFrame: tone(0.1))
        }
    }

    @Test func flagsDefaultToOff() throws {
        let flags = LocalVoiceFlags()
        #expect(flags.conversationMode == false)
        #expect(flags.pocketTTS == false)

        let fresh = try JSONDecoder().decode(PersistedVoiceSettings.self, from: Data("{}".utf8))
        #expect(fresh.resolvedEngine(kokoroReady: true, elevenLabsKeyValid: true) == .elevenLabs)
        #expect(fresh.resolvedProvider(kokoroReady: true, elevenLabsKeyValid: true) == .elevenLabs)
        #expect(fresh.resolvedEngineAuto())

        let saved = Data("""
        {"voice.engine":"kokoro","voice.engine.userSelected":true,"voice.ttsProvider":"kokoro","voice.engine.auto":false}
        """.utf8)
        let kept = try JSONDecoder().decode(PersistedVoiceSettings.self, from: saved)
        #expect(kept.resolvedEngine(kokoroReady: false, elevenLabsKeyValid: false) == .kokoro)
        #expect(kept.resolvedProvider(kokoroReady: false, elevenLabsKeyValid: true) == .kokoro)
        #expect(kept.resolvedEngineAuto() == false)

        let withFlagsOff = Data("""
        {"voice.engine":"system","voice.engine.userSelected":true,"conversationMode":false,"pocketTTS":false}
        """.utf8)
        let stillSystem = try JSONDecoder().decode(PersistedVoiceSettings.self, from: withFlagsOff)
        #expect(stillSystem.resolvedEngine(kokoroReady: true, elevenLabsKeyValid: true) == .system)
    }

    @Test func frameSizeBoundariesFollowThe3200SampleRule() async throws {
        let legal = try await verifyWithin("legal frame") { try VoiceFrame(samples: Array(repeating: 0, count: 3_200)) }
        #expect(legal.samples.count == VoiceFrame.sampleCount)
        let backend = try FakeDuplexVoiceBackend(frames: [tone(0.2), tone(0.2)])
        _ = try await backend.start()
        for count in [0, 3_199, 3_201] {
            await #expect(throws: VoiceSessionError.badFrameSize(expected: 3_200, got: count)) {
                try await backend.push(userFrame: Array(repeating: 0, count: count))
            }
            #expect(await backend.state == .streaming)
        }
        let accepted = try await verifyWithin("sized push") {
            try await backend.push(userFrame: Array(repeating: 0, count: 3_200))
        }
        #expect(accepted.samples.count == 3_200)
    }

    @Test func aSavedEngineStaysThatEngineForEveryStoredChoice() throws {
        for engine in [UltronVoicePlan.Engine.system, .elevenLabs, .kokoro] {
            for ready in [false, true] {
                for key in [false, true] {
                    let json = Data("""
                    {"voice.engine":"\(engine.rawValue)","voice.engine.userSelected":true}
                    """.utf8)
                    let saved = try JSONDecoder().decode(PersistedVoiceSettings.self, from: json)
                    #expect(saved.resolvedEngine(kokoroReady: ready, elevenLabsKeyValid: key) == engine)
                }
            }
        }
        let flags = LocalVoiceFlags()
        #expect(flags.conversationMode == false)
        #expect(flags.pocketTTS == false)
    }

    @Test func aTimeoutIsAnInfrastructureErrorAfterOneRetry() async {
        let tries = Counter()
        await #expect(throws: VerifyInfrastructure.timedOut("probe")) {
            try await verifyWithin("probe") {
                tries.add()
                throw VerifyInfrastructure.timedOut("probe")
            }
        }
        #expect(tries.value == 2)
    }

    @Test func flagsOffDoNotUseTheNetworkOrAProcess() async throws {
        let flags = LocalVoiceFlags()
        #expect(flags.conversationMode == false)
        #expect(flags.pocketTTS == false)
        let banned = ["URL" + "Session", "posix_" + "spawn", "NW" + "Connection", "Process"]
        let files = [
            "Sources/ZeusCore/Voice/DuplexVoiceBackend.swift",
            "Sources/ZeusCore/Voice/VoiceSessionState.swift",
            "Sources/ZeusCore/Voice/LocalVoiceFlags.swift",
            "Sources/ZeusCore/Voice/PersistedVoiceSettings.swift",
        ]
        for file in files {
            let source = try voiceSource(file)
            for token in banned where source.contains(token) {
                #expect(Bool(false), "\(file) contains \(token)")
            }
        }
        let trap = LaunchSeen.shared
        trap.reset()
        #if canImport(FoundationNetworking)
        URLProtocol.registerClass(LaunchTrap.self)
        defer { URLProtocol.unregisterClass(LaunchTrap.self) }
        #endif
        let backend = try FakeDuplexVoiceBackend(frames: [tone(0.2), tone(0.4)])
        _ = try await backend.start()
        _ = try await backend.push(userFrame: tone(0.2))
        await backend.close()
        #expect(trap.value == false)
        #expect(await backend.state == .closed)
    }

    @Test func theEngineRouterIsUnchangedWhenLocalFlagsAreOff() throws {
        let flags = LocalVoiceFlags()
        #expect(flags.conversationMode == false)
        #expect(flags.pocketTTS == false)
        let router = try voiceSource("Sources/ZeusCore/Voice/UltronEngineRouter.swift")
        for token in ["Local" + "VoiceFlags", "conversation" + "Mode", "pocket" + "TTS"] where router.contains(token) {
            #expect(Bool(false), "router mentions \(token)")
        }
        let chain = UltronEngineRouter.chain(
            choice: .auto,
            availability: UltronEngineAvailability(elevenLabsConfigured: true, kokoroReady: true))
        // Auto, with ElevenLabs configured and Kokoro ready, is still ElevenLabs, Kokoro, then the Mac voice.
        #expect(chain.map(\.engine) == [.elevenLabs, .kokoro, .system])
    }

    @Test func theTransitionSwitchHasNoDefault() throws {
        let source = try voiceSource("Sources/ZeusCore/Voice/VoiceSessionState.swift")
        #expect(source.contains("default:") == false)
    }

    @Test func thisSuiteAddsNoSkipOrXfail() throws {
        let source = try String(contentsOf: URL(fileURLWithPath: #filePath), encoding: .utf8)
        for token in ["XCT" + "Skip", "expected" + "Failure", "with" + "KnownIssue", ".dis" + "abled"] {
            #expect(source.contains(token) == false)
        }
    }
}

private final class LaunchSeen: @unchecked Sendable {
    static let shared = LaunchSeen()
    private let lock = NSLock()
    private var stored = false
    var value: Bool { lock.withLock { stored } }
    func mark() { lock.withLock { stored = true } }
    func reset() { lock.withLock { stored = false } }
}

#if canImport(FoundationNetworking)
private final class LaunchTrap: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool {
        LaunchSeen.shared.mark()
        return false
    }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {}
    override func stopLoading() {}
}
#endif

private actor StartGate {
    private var entered = false
    private var released = false
    private var enteredWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []

    func markEntered() {
        entered = true
        let waiters = enteredWaiters
        enteredWaiters.removeAll()
        waiters.forEach { $0.resume() }
    }

    func waitUntilEntered() async {
        if entered { return }
        await withCheckedContinuation { enteredWaiters.append($0) }
    }

    func release() {
        released = true
        let waiters = releaseWaiters
        releaseWaiters.removeAll()
        waiters.forEach { $0.resume() }
    }

    func waitUntilReleased() async {
        if released { return }
        await withCheckedContinuation { releaseWaiters.append($0) }
    }
}

private func voiceSource(_ relative: String) throws -> String {
    var url = URL(fileURLWithPath: #filePath)
    url.deleteLastPathComponent()
    url.deleteLastPathComponent()
    url.deleteLastPathComponent()
    return try String(contentsOf: url.appendingPathComponent(relative), encoding: .utf8)
}

private enum VerifyInfrastructure: Error, Equatable {
    case timedOut(String)
}

private func verifyWithin<T>(_ label: String, _ body: () async throws -> T) async throws -> T {
    for attempt in 1...2 {
        do { return try await body() }
        catch let error as VerifyInfrastructure {
            if attempt == 2 { throw error }
        }
    }
    throw VerifyInfrastructure.timedOut(label)
}

private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var stored = 0
    var value: Int { lock.withLock { stored } }
    func add() { lock.withLock { stored += 1 } }
}
