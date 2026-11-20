import Foundation
import Testing
@testable import ZeusCore

@Suite struct LocalVoiceBackendContractTests {
    private func tone(_ value: Float) -> [Float] {
        Array(repeating: value, count: VoiceFrame.sampleCount)
    }

    @Test func everyStateAndEventHasOneOutcome() throws {
        let failure = VoiceSessionError.badFrameSize(expected: 3_200, got: 1)
        let states: [VoiceSessionState] = [.idle, .starting, .streaming, .closing, .closed, .failed(failure)]
        let events: [VoiceSessionEvent] = [.start, .started, .push, .close, .closed, .fail(failure)]
        let legal: [VoiceSessionState: [VoiceSessionEvent: VoiceSessionState]] = [
            .idle: [.start: .starting, .fail(failure): .failed(failure)],
            .starting: [.started: .streaming, .fail(failure): .failed(failure)],
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

    @Test func closeBeforeStartLeavesTheSessionIdle() async throws {
        let backend = try FakeDuplexVoiceBackend(frames: [tone(0.1)])
        await backend.close()
        #expect(await backend.state == .idle)
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

    @Test func thisSuiteAddsNoSkipOrXfail() throws {
        let source = try String(contentsOf: URL(fileURLWithPath: #filePath), encoding: .utf8)
        for token in ["XCT" + "Skip", "expected" + "Failure", "with" + "KnownIssue", ".dis" + "abled"] {
            #expect(source.contains(token) == false)
        }
    }
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
