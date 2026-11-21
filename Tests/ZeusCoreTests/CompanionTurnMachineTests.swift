import Foundation
import Testing
@testable import ZeusCore

/// Slice S1. The production machine is exercised as a pure value: one phase, injected time,
/// and commands instead of side effects. Illegal pairs come back as `CompanionTurnRejection`.
@Suite("CompanionTurnMachine")
struct CompanionTurnMachineTests {
    private static let screenDenial = "I can't see the screen."
    private static let phases: [CompanionTurnPhase] = [
        .idle, .listening, .transcribing, .thinking, .speaking, .interrupted,
        .error("That failed. Nothing was changed."),
    ]

    private enum Expectation: Equatable {
        case reject
        case accept(CompanionTurnPhase, [CompanionTurnCommand])
    }

    // MARK: Exhaustive table

    @Test func everyPhaseAndEventIsEitherAcceptedOrRejected() {
        let events = Self.events()
        let kinds = Set(events.map(Self.kind))
        #expect(kinds.count == 12)
        #expect(events.count == 14)
        for phase in Self.phases {
            for event in events {
                var machine = arrive(phase)
                #expect(machine.phase == phase, "setup did not reach \(phase)")
                let partialBefore = machine.partial
                let marksBefore = machine.marks
                let enteredBefore = machine.phaseEnteredAt
                let response = machine.send(event)
                switch (Self.expect(from: phase, event: event), response) {
                case (.reject, .rejected(let rejection)):
                    #expect(machine.phase == phase)
                    #expect(rejection.phase == phase)
                    #expect(rejection.event == event)
                    #expect(machine.partial == partialBefore)
                    #expect(machine.marks == marksBefore)
                    #expect(machine.phaseEnteredAt == enteredBefore)
                case (.accept(let next, let commands), .accepted(let outcome)):
                    #expect(machine.phase == next, "\(phase) + \(event) landed on \(machine.phase)")
                    #expect(outcome.commands == commands, "\(phase) + \(event) commands \(outcome.commands)")
                    #expect(outcome.steps.count == 1)
                    #expect(outcome.steps.first?.from == phase)
                    #expect(outcome.steps.first?.to == next)
                    #expect(outcome.steps.first?.commands == commands)
                    #expect(machine.phase.activePhaseCount <= 1)
                    switch event {
                    case .partialTranscript(let text):
                        #expect(machine.partial == text)
                    case .finalTranscript(let text, _):
                        #expect(machine.partial == text.trimmingCharacters(in: .whitespacesAndNewlines))
                    case .keyDown, .reset:
                        #expect(machine.partial.isEmpty)
                    default:
                        if machine.phase == .idle || machine.phase == .interrupted {
                            #expect(machine.partial.isEmpty)
                        }
                    }
                default:
                    Issue.record("\(phase) + \(event) produced \(response), expected \(Self.expect(from: phase, event: event))")
                }
            }
        }
    }

    // MARK: Spec boundaries

    @Test func keyDownPublishesListeningBeforeTheMicrophoneCommand() {
        let clock = CompanionManualClock(now: 10)
        var machine = CompanionTurnMachine(clock: clock)
        let response = machine.send(.keyDown)
        #expect(machine.phase == .listening)
        #expect(machine.hotkeyToListening == 0)
        #expect((machine.hotkeyToListening ?? 1) < 0.050)
        guard case .accepted(let outcome) = response else {
            Issue.record("key down was rejected")
            return
        }
        #expect(outcome.commands == [.showListeningLamp, .startMic, .startCapture])
        let lamp = outcome.commands.firstIndex(of: .showListeningLamp)
        let mic = outcome.commands.firstIndex(of: .startMic)
        #expect(lamp != nil && mic != nil && lamp! < mic!)
        clock.advance(to: 10.049)
        #expect(machine.elapsedInPhase() < 0.050)
        clock.advance(to: 10.051)
        #expect(machine.elapsedInPhase() > 0.050)
    }

    @Test func secondKeyDownWhileListeningStaysListening() {
        var machine = arrive(.listening)
        let response = machine.send(.keyDown)
        guard case .rejected = response else {
            Issue.record("a second key down was accepted")
            return
        }
        #expect(machine.phase == .listening)
    }

    @Test func emptyPartialEndsIdleWithoutABrainCommand() {
        var machine = arrive(.transcribing)
        let response = machine.send(.finalTranscript(" \n\t ", instant: true))
        #expect(machine.phase == .idle)
        guard case .accepted(let outcome) = response else {
            Issue.record("blank transcript was rejected")
            return
        }
        #expect(outcome.commands.isEmpty)
        #expect(!outcome.commands.contains(.cancelLLM))
        #expect(outcome.steps.allSatisfy { $0.to != .thinking && $0.from != .thinking })
    }

    @Test func instantRouteSkipsThinking() {
        var machine = arrive(.transcribing)
        let response = machine.send(.finalTranscript("What time is it", instant: true))
        #expect(machine.phase == .speaking)
        guard case .accepted(let outcome) = response else {
            Issue.record("instant transcript was rejected")
            return
        }
        #expect(outcome.commands.isEmpty)
        #expect(!outcome.commands.contains(.cancelLLM))
        #expect(outcome.steps.allSatisfy { $0.from != .thinking && $0.to != .thinking })
    }

    @Test func brainRouteEntersThinkingWithoutSpeaking() {
        var machine = arrive(.transcribing)
        let response = machine.send(.finalTranscript("Point at the clock", instant: false))
        #expect(machine.phase == .thinking)
        guard case .accepted(let outcome) = response else {
            Issue.record("brain transcript was rejected")
            return
        }
        #expect(outcome.commands.isEmpty)
        #expect(machine.phase != .speaking)
    }

    @Test func bargeInFromSpeakingStartsTheMicrophone() {
        var machine = arrive(.speaking)
        let response = machine.send(.bargeIn)
        #expect(machine.phase == .listening)
        guard case .accepted(let outcome) = response else {
            Issue.record("barge-in from speaking was rejected")
            return
        }
        #expect(outcome.commands.contains(.startMic))
        #expect(outcome.commands.contains(.startCapture))
        let speech = outcome.commands.firstIndex(of: .stopSpeech)
        let mic = outcome.commands.firstIndex(of: .startMic)
        #expect(speech != nil && mic != nil && speech! < mic!)
    }

    @Test func bargeInFromSpeakingStopsSpeechFlightAndCaptureInOneStep() {
        for phase in [CompanionTurnPhase.thinking, .speaking, .transcribing, .listening, .error("That failed. Nothing was changed.")] {
            var machine = arrive(phase)
            let response = machine.send(.bargeIn)
            #expect(machine.phase == .interrupted, "\(phase) did not interrupt")
            guard case .accepted(let outcome) = response else {
                Issue.record("barge-in from \(phase) was rejected")
                continue
            }
            #expect(outcome.steps.count == 1)
            let speech = outcome.commands.firstIndex(of: .stopSpeech)
            let flight = outcome.commands.firstIndex(of: .cancelFlight)
            let model = outcome.commands.firstIndex(of: .cancelLLM)
            #expect(speech != nil && flight != nil && model != nil)
            #expect(speech! < flight! && flight! < model!)
            #expect(outcome.commands.filter { $0 == .stopSpeech }.count == 1)
            #expect(outcome.commands.filter { $0 == .cancelFlight }.count == 1)
            #expect(outcome.commands.filter { $0 == .cancelLLM }.count == 1)
            #expect(outcome.commands.allSatisfy { command in
                if case .speakError = command { return false }
                return true
            })
        }
    }

    @Test func secondHoldListensAgainAfterTheInterrupt() {
        var machine = arrive(.speaking)
        let interrupted = machine.send(.bargeIn)
        guard case .accepted = interrupted else {
            Issue.record("barge-in from speaking was rejected")
            return
        }
        #expect(machine.phase == .interrupted)
        let again = machine.send(.keyDown)
        #expect(machine.phase == .listening)
        guard case .accepted(let outcome) = again else {
            Issue.record("key down after the interrupt was rejected")
            return
        }
        #expect(outcome.commands == [.showListeningLamp, .startMic, .startCapture])
        #expect(machine.phase != .speaking)
    }

    @Test func noSpeechAfterInterrupted() {
        var machine = arrive(.speaking)
        machine.send(.bargeIn)
        #expect(machine.phase == .interrupted)
        let blocked: [CompanionTurnEvent] = [
            .firstToken, .firstAudio, .audioFinished,
            .finalTranscript("hello", instant: true),
            .partialTranscript("hello"),
            .captureFailed(Self.screenDenial),
            .timeout,
        ]
        for event in blocked {
            let response = machine.send(event)
            guard case .rejected = response else {
                Issue.record("\(event) was accepted after the interrupt")
                return
            }
            #expect(machine.phase == .interrupted)
            #expect(machine.phase != .speaking)
        }
        machine.send(.keyDown)
        #expect(machine.phase == .listening)
        let earlyAudio = machine.send(.firstAudio)
        guard case .rejected = earlyAudio else {
            Issue.record("audio was accepted before a new transcript")
            return
        }
        #expect(machine.phase == .listening)
    }

    @Test func errorThenHoldListensAgain() {
        var machine = arrive(.listening)
        let failed = machine.send(.captureFailed(Self.screenDenial))
        #expect(machine.phase == .error(Self.screenDenial))
        guard case .accepted(let failure) = failed else {
            Issue.record("capture failure was rejected")
            return
        }
        #expect(failure.commands == [.stopMic, .speakError(Self.screenDenial)])
        let held = machine.send(.keyDown)
        #expect(machine.phase == .listening)
        guard case .accepted(let outcome) = held else {
            Issue.record("the hold after an error was rejected")
            return
        }
        #expect(outcome.commands == [.stopSpeech, .showListeningLamp, .startMic, .startCapture])
    }

    @Test func errorSpeaksOneLine() {
        var dumped = arrive(.listening)
        let dump = "Traceback (most recent call last): exception error: HTTP 500 brain: failed; exit code timed out"
        dumped.send(.captureFailed(dump))
        guard case .error(let line) = dumped.phase else {
            Issue.record("a provider dump did not enter error")
            return
        }
        #expect(Self.words(line) <= 10)
        #expect(Self.words(line) >= 1)
        let lowered = line.lowercased()
        #expect(!lowered.contains("traceback"))
        #expect(!lowered.contains("exception"))
        #expect(!lowered.contains("http"))
        #expect(!line.contains(dump))

        var quota = arrive(.thinking)
        quota.send(.captureFailed("You hit your usage limit for the week"))
        #expect(quota.phase == .error("Every AI is out of quota."))

        var clipped = arrive(.transcribing)
        let long = "one two three four five six seven eight nine ten eleven"
        clipped.send(.captureFailed(long))
        guard case .error(let clippedLine) = clipped.phase else {
            Issue.record("a long failure did not enter error")
            return
        }
        #expect(Self.words(clippedLine) <= 10)
        #expect(clippedLine == "one two three four five six seven eight nine ten.")

        var exact = arrive(.listening)
        let ten = "one two three four five six seven eight nine ten"
        exact.send(.captureFailed(ten))
        #expect(exact.phase == .error(ten))
    }

    @Test func eachPhaseHasOnePose() {
        let phases: [CompanionTurnPhase] = [
            .idle, .listening, .transcribing, .thinking, .speaking, .interrupted, .error("x"),
        ]
        let poses = phases.map { $0.pose(flightActive: false) }
        #expect(poses == [.idle, .listening, .thinking, .thinking, .speaking, .interrupted, .error])
        #expect(CompanionTurnPhase.speaking.pose(flightActive: true) == .pointing)
        #expect(CompanionTurnPhase.speaking.pose(flightActive: false) == .speaking)
        #expect(CompanionTurnPhase.thinking.pose(flightActive: true) == .thinking)
        #expect(CompanionTurnPhase.listening.pose(flightActive: true) == .listening)
        #expect(CompanionTurnPhase.error("x").pose(flightActive: false) != CompanionTurnPhase.idle.pose(flightActive: false))
        #expect(CompanionTurnPhase.interrupted.pose(flightActive: false) == .interrupted)
        #expect(CompanionTurnPhase.error("x").pose(flightActive: false) == .error)
        for phase in phases {
            #expect(phase.pose(flightActive: false) == phase.pose(flightActive: false))
            #expect(phase.activePhaseCount <= 1)
        }
    }

    @Test func notchAndBuddySharePhase() {
        let phases: [CompanionTurnPhase] = [
            .idle, .listening, .transcribing, .thinking, .speaking, .interrupted, .error("x"),
        ]
        for phase in phases {
            for flight in [false, true] {
                #expect(phase.notchPose(flightActive: flight) == phase.buddyPose(flightActive: flight))
                #expect(phase.notchLabel(flightActive: flight) == phase.buddyLabel(flightActive: flight))
                #expect(phase.notchPose(flightActive: flight) == phase.pose(flightActive: flight))
                #expect(phase.notchLabel(flightActive: flight) == phase.pose(flightActive: flight).title)
            }
        }
        #expect(CompanionTurnPhase.speaking.notchLabel(flightActive: true) == "Pointing")
        #expect(CompanionTurnPhase.transcribing.notchLabel(flightActive: false) == "Thinking")
        #expect(CompanionTurnPhase.thinking.buddyLabel(flightActive: false) == "Thinking")
    }

    @Test func injectedClockMeasuresKeyUpToFirstAudioAgainstTheExistingCeiling() {
        let clock = CompanionManualClock(now: 1_000)
        var machine = CompanionTurnMachine(clock: clock)
        machine.send(.keyDown)
        clock.advance(to: 1_000.25)
        machine.send(.keyUp)
        clock.advance(to: 1_000.5)
        machine.send(.finalTranscript("Point at the clock", instant: false))
        clock.advance(to: 1_000.75)
        machine.send(.firstToken)
        clock.advance(to: 1_001)
        machine.send(.firstAudio)
        #expect(machine.interval(.keyUp, .firstToken) == 0.5)
        #expect(machine.keyUpToFirstAudio == 0.75)
        #expect(machine.withinExistingFirstAudioCeiling(apiBrain: true, cloudVoice: true) == true)
        let ceiling = Double(VoiceLatencyTargets.apiCloudVoiceMs) / 1_000
        #expect(ceiling == 1.2)
        #expect((machine.keyUpToFirstAudio ?? 9) < ceiling)
        #expect((machine.keyUpToFirstAudio ?? 9) < 0.9)
    }

    @Test func wallClockJumpDoesNotTripTheDeepSpokenCeiling() throws {
        let source = try String(contentsOf: Self.repoRoot.appendingPathComponent("Sources/ZeusCore/Companion/CompanionTurnMachine.swift"), encoding: .utf8)
        #expect(!source.contains("timeIntervalSinceReferenceDate"))
        #expect(source.contains("systemUptime"))

        let system = CompanionSystemClock()
        let uptime = ProcessInfo.processInfo.systemUptime
        #expect(abs(system.now() - uptime) < 0.05)
        #expect(abs(system.now() - Date().timeIntervalSinceReferenceDate) > 86_400)

        let clock = CompanionManualClock(now: 40)
        var machine = CompanionTurnMachine(clock: clock)
        machine.send(.keyDown)
        machine.send(.keyUp)
        machine.send(.finalTranscript("Point at the clock", instant: false))
        #expect(machine.phase == .thinking)
        let entered = machine.phaseEnteredAt
        let jump = CompanionTurnMachine.deepSpokenCeiling + 3_600
        clock.jumpWall(by: jump)
        #expect(clock.wallNow() == 40 + jump)
        #expect(clock.now() == entered)
        #expect(machine.elapsedInPhase() == 0)
        #expect(!machine.exceededDeepSpokenCeiling())
        clock.advance(to: entered + 1)
        #expect(machine.elapsedInPhase() == 1)
        #expect(!machine.exceededDeepSpokenCeiling())
    }

    @Test func existingFortyFiveAndTwentySecondTimeoutsAreReferenced() throws {
        let root = Self.repoRoot
        let controller = try String(contentsOf: root.appendingPathComponent("Sources/Zeus/App/VoiceTurnController.swift"), encoding: .utf8)
        let latency = try String(contentsOf: root.appendingPathComponent("Sources/Zeus/Voice/VoiceLatency.swift"), encoding: .utf8)
        let router = try String(contentsOf: root.appendingPathComponent("Sources/Zeus/Brain/Router.swift"), encoding: .utf8)
        let machineSource = try String(contentsOf: root.appendingPathComponent("Sources/ZeusCore/Companion/CompanionTurnMachine.swift"), encoding: .utf8)
        let phaseSource = try String(contentsOf: root.appendingPathComponent("Sources/ZeusCore/Companion/CompanionTurnPhase.swift"), encoding: .utf8)
        let deep = try Self.firstInteger(#"deep \? ([0-9]+)"#, in: controller)
        let quiet = try Self.firstInteger(#"\.seconds\(([0-9]+)\)"#, in: latency)
        let firstByte = try Self.firstInteger(#"\? ([0-9]+) : Self\.silentLimit"#, in: router)
        #expect(deep == 45)
        #expect(quiet == 45)
        #expect(firstByte == 20)
        #expect(CompanionTurnMachine.deepSpokenCeiling == FastTier.conversationWindowSeconds)
        #expect(CompanionTurnMachine.deepSpokenCeiling == TimeInterval(deep))
        #expect(CompanionTurnMachine.deepSpokenCeiling == TimeInterval(quiet))
        #expect(!machineSource.contains("= 45") && !machineSource.contains("=45"))
        #expect(!machineSource.contains("= 20") && !machineSource.contains("=20"))
        #expect(!phaseSource.contains("= 45") && !phaseSource.contains("= 20"))

        let clock = CompanionManualClock(now: 0)
        var thinking = CompanionTurnMachine(clock: clock)
        thinking.send(.keyDown)
        thinking.send(.keyUp)
        thinking.send(.finalTranscript("Point at the clock", instant: false))
        let started = thinking.phaseEnteredAt
        clock.advance(to: started + TimeInterval(firstByte))
        #expect(thinking.phase == .thinking)
        #expect(!thinking.exceededDeepSpokenCeiling())
        let early = thinking.send(.timeout)
        #expect(thinking.phase == .error(CompanionTurnMachine.timeoutSpokenLine))
        guard case .accepted(let earlyOutcome) = early else {
            Issue.record("the host timeout was rejected")
            return
        }
        #expect(earlyOutcome.commands == [.cancelLLM, .speakError(CompanionTurnMachine.timeoutSpokenLine)])

        let later = CompanionManualClock(now: 0)
        var speaking = CompanionTurnMachine(clock: later)
        speaking.send(.keyDown)
        speaking.send(.keyUp)
        speaking.send(.finalTranscript("What time is it", instant: true))
        later.advance(to: speaking.phaseEnteredAt + CompanionTurnMachine.deepSpokenCeiling - 0.001)
        #expect(!speaking.exceededDeepSpokenCeiling())
        later.advance(to: speaking.phaseEnteredAt + CompanionTurnMachine.deepSpokenCeiling)
        #expect(speaking.exceededDeepSpokenCeiling())
        let quietEnd = speaking.send(.timeout)
        #expect(speaking.phase == .idle)
        guard case .accepted(let quietOutcome) = quietEnd else {
            Issue.record("the speaking ceiling timeout was rejected")
            return
        }
        #expect(quietOutcome.commands == [.stopSpeech])
    }

    // MARK: Seeded sequences

    @Test func randomSequencesKeepTheTurnInvariants() {
        let seed: UInt64 = 0x0070_C0A1
        let sequences = 200
        let length = 24
        for index in 0..<sequences {
            var generator = SeededGenerator(seed &+ UInt64(index))
            let clock = CompanionManualClock(now: 0)
            var machine = CompanionTurnMachine(clock: clock)
            var speechBlocked = false
            for step in 0..<length {
                let event = Self.randomEvent(&generator)
                let before = machine.phase
                let partialBefore = machine.partial
                let marksBefore = machine.marks
                let response = machine.send(event)
                let context = "sequence \(index) step \(step) from \(before) event \(event)"
                #expect(Self.activeNames(machine.phase).count <= 1, "\(context)")
                #expect(machine.phase.activePhaseCount == Self.activeNames(machine.phase).count, "\(context)")
                switch response {
                case .rejected(let rejection):
                    #expect(machine.phase == before, "\(context)")
                    #expect(rejection.phase == before, "\(context)")
                    #expect(rejection.event == event, "\(context)")
                    #expect(machine.partial == partialBefore, "\(context)")
                    #expect(machine.marks == marksBefore, "\(context)")
                case .accepted(let outcome):
                    var cursor = before
                    var sawInterrupted = false
                    var flat: [CompanionTurnCommand] = []
                    for transition in outcome.steps {
                        #expect(transition.from == cursor, "\(context)")
                        if sawInterrupted {
                            #expect(transition.to != .speaking, "\(context)")
                            #expect(Self.noSpokenLine(transition.commands), "\(context)")
                        }
                        if transition.to == .interrupted { sawInterrupted = true }
                        cursor = transition.to
                        flat.append(contentsOf: transition.commands)
                    }
                    #expect(cursor == machine.phase, "\(context)")
                    #expect(flat == outcome.commands, "\(context)")
                    #expect(!(outcome.commands.contains(.startMic) && outcome.commands.contains(.stopMic)), "\(context)")
                    if case .bargeIn = event {
                        #expect(Self.hasBargeCancels(outcome.commands), "\(context)")
                    }
                }
                if speechBlocked {
                    if case .accepted(let outcome) = response {
                        #expect(machine.phase != .speaking, "\(context)")
                        #expect(Self.noSpokenLine(outcome.commands), "\(context)")
                    } else {
                        #expect(machine.phase != .speaking, "\(context)")
                    }
                }
                if case .accepted(let outcome) = response {
                    if outcome.steps.contains(where: { $0.to == .interrupted }) {
                        speechBlocked = true
                    }
                    if machine.phase == .listening {
                        switch before {
                        case .interrupted, .idle, .error: speechBlocked = false
                        default: break
                        }
                    }
                    if case .reset = event { speechBlocked = false }
                }
                if case .bargeIn = event, case .rejected = response {
                    #expect(before == .idle, "\(context)")
                }
                if case .reset = event {
                    #expect(machine.phase == .idle, "\(context)")
                }
            }
            let finished = machine.send(.reset)
            #expect(machine.phase == .idle, "sequence \(index) did not idle")
            guard case .accepted = finished else {
                Issue.record("reset was rejected at the end of sequence \(index)")
                continue
            }
        }
    }

    // MARK: Expectations

    private static func events() -> [CompanionTurnEvent] {
        [
            .keyDown,
            .keyUp,
            .partialTranscript("partial"),
            .finalTranscript("what time is it", instant: false),
            .finalTranscript("what time is it", instant: true),
            .finalTranscript(" \n ", instant: true),
            .firstToken,
            .firstAudio,
            .audioFinished,
            .bargeIn,
            .captureFailed(screenDenial),
            .timeout,
            .cancel,
            .reset,
        ]
    }

    /// Every event the machine claims to understand. Adding a case without a table row fails the build.
    private static func kind(_ event: CompanionTurnEvent) -> String {
        switch event {
        case .keyDown: "keyDown"
        case .keyUp: "keyUp"
        case .partialTranscript: "partialTranscript"
        case .finalTranscript: "finalTranscript"
        case .firstToken: "firstToken"
        case .firstAudio: "firstAudio"
        case .audioFinished: "audioFinished"
        case .bargeIn: "bargeIn"
        case .captureFailed: "captureFailed"
        case .timeout: "timeout"
        case .cancel: "cancel"
        case .reset: "reset"
        }
    }

    private static func expect(from phase: CompanionTurnPhase, event: CompanionTurnEvent) -> Expectation {
        let cancels: [CompanionTurnCommand] = [.stopSpeech, .cancelFlight, .cancelLLM]
        let listen: [CompanionTurnCommand] = [.showListeningLamp, .startMic, .startCapture]
        let timeoutLine = CompanionTurnMachine.timeoutSpokenLine
        func spoken(_ raw: String) -> String { SpokenFailure.line(raw) }

        switch phase {
        case .idle:
            switch event {
            case .keyDown: return .accept(.listening, listen)
            case .reset: return .accept(.idle, [])
            default: return .reject
            }
        case .listening:
            switch event {
            case .keyUp: return .accept(.transcribing, [.stopMic])
            case .partialTranscript: return .accept(.listening, [])
            case .captureFailed(let reason):
                let line = spoken(reason)
                return .accept(.error(line), [.stopMic, .speakError(line)])
            case .cancel, .reset: return .accept(.idle, [.stopMic])
            case .bargeIn: return .accept(.interrupted, cancels + [.stopMic])
            default: return .reject
            }
        case .transcribing:
            switch event {
            case .partialTranscript: return .accept(.transcribing, [])
            case .finalTranscript(let text, let instant):
                if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return .accept(.idle, []) }
                return instant ? .accept(.speaking, []) : .accept(.thinking, [])
            case .captureFailed(let reason):
                let line = spoken(reason)
                return .accept(.error(line), [.speakError(line)])
            case .cancel, .reset: return .accept(.idle, [])
            case .bargeIn: return .accept(.interrupted, cancels)
            default: return .reject
            }
        case .thinking:
            switch event {
            case .firstToken: return .accept(.thinking, [])
            case .firstAudio: return .accept(.speaking, [])
            case .captureFailed(let reason):
                let line = spoken(reason)
                return .accept(.error(line), [.cancelLLM, .speakError(line)])
            case .timeout:
                return .accept(.error(timeoutLine), [.cancelLLM, .speakError(timeoutLine)])
            case .bargeIn, .cancel: return .accept(.interrupted, cancels)
            case .reset: return .accept(.idle, cancels)
            default: return .reject
            }
        case .speaking:
            switch event {
            case .firstAudio: return .accept(.speaking, [])
            case .audioFinished: return .accept(.idle, [])
            case .timeout: return .accept(.idle, [.stopSpeech])
            case .bargeIn, .cancel: return .accept(.interrupted, cancels)
            case .reset: return .accept(.idle, cancels)
            default: return .reject
            }
        case .interrupted:
            switch event {
            case .keyDown: return .accept(.listening, listen)
            case .bargeIn: return .accept(.interrupted, cancels)
            case .cancel, .reset: return .accept(.idle, [])
            default: return .reject
            }
        case .error:
            switch event {
            case .keyDown: return .accept(.listening, [.stopSpeech] + listen)
            case .audioFinished: return .accept(.idle, [])
            case .bargeIn: return .accept(.interrupted, cancels)
            case .cancel, .reset: return .accept(.idle, [.stopSpeech])
            default: return .reject
            }
        }
    }

    private func arrive(_ phase: CompanionTurnPhase) -> CompanionTurnMachine {
        let clock = CompanionManualClock(now: 0)
        var machine = CompanionTurnMachine(clock: clock)
        switch phase {
        case .idle:
            break
        case .listening:
            machine.send(.keyDown)
            machine.send(.partialTranscript("partial"))
        case .transcribing:
            machine.send(.keyDown)
            machine.send(.partialTranscript("partial"))
            machine.send(.keyUp)
        case .thinking:
            machine.send(.keyDown)
            machine.send(.partialTranscript("partial"))
            machine.send(.keyUp)
            machine.send(.finalTranscript("what time is it", instant: false))
        case .speaking:
            machine.send(.keyDown)
            machine.send(.partialTranscript("partial"))
            machine.send(.keyUp)
            machine.send(.finalTranscript("what time is it", instant: true))
        case .interrupted:
            machine.send(.keyDown)
            machine.send(.partialTranscript("partial"))
            machine.send(.keyUp)
            machine.send(.finalTranscript("what time is it", instant: true))
            machine.send(.bargeIn)
        case .error(let reason):
            machine.send(.keyDown)
            machine.send(.partialTranscript("partial"))
            machine.send(.captureFailed(reason))
        }
        return machine
    }

    private static func randomEvent(_ generator: inout SeededGenerator) -> CompanionTurnEvent {
        switch Int.random(in: 0..<12, using: &generator) {
        case 0: .keyDown
        case 1: .keyUp
        case 2: .partialTranscript(Bool.random(using: &generator) ? "hello" : "  ")
        case 3: .finalTranscript(Bool.random(using: &generator) ? "what time is it" : " ", instant: Bool.random(using: &generator))
        case 4: .firstToken
        case 5: .firstAudio
        case 6: .audioFinished
        case 7: .bargeIn
        case 8: .captureFailed(Bool.random(using: &generator) ? screenDenial : "Traceback exception error: HTTP brain: failed;")
        case 9: .timeout
        case 10: .cancel
        default: .reset
        }
    }

    private static func activeNames(_ phase: CompanionTurnPhase) -> [String] {
        switch phase {
        case .listening: ["listening"]
        case .transcribing: ["transcribing"]
        case .thinking: ["thinking"]
        case .speaking: ["speaking"]
        default: []
        }
    }

    private static func noSpokenLine(_ commands: [CompanionTurnCommand]) -> Bool {
        commands.allSatisfy { command in
            if case .speakError = command { return false }
            return true
        }
    }

    private static func hasBargeCancels(_ commands: [CompanionTurnCommand]) -> Bool {
        guard let speech = commands.firstIndex(of: .stopSpeech),
              let flight = commands.firstIndex(of: .cancelFlight),
              let model = commands.firstIndex(of: .cancelLLM) else { return false }
        return speech < flight && flight < model
            && commands.filter { $0 == .stopSpeech }.count == 1
            && commands.filter { $0 == .cancelFlight }.count == 1
            && commands.filter { $0 == .cancelLLM }.count == 1
    }

    private static func words(_ line: String) -> Int {
        line.split { $0.isWhitespace }.count
    }

    private static var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private static func firstInteger(_ pattern: String, in text: String) throws -> Int {
        let expression = try NSRegularExpression(pattern: pattern)
        let range = NSRange(text.startIndex..., in: text)
        guard let match = expression.firstMatch(in: text, range: range),
              let slice = Range(match.range(at: 1), in: text),
              let value = Int(text[slice]) else {
            throw ExpectationError.missing(pattern)
        }
        return value
    }

    private struct SeededGenerator: RandomNumberGenerator {
        var state: UInt64
        init(_ seed: UInt64) { state = seed == 0 ? 0xA5A5_5A5A_1234_5678 : seed }
        mutating func next() -> UInt64 {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return state
        }
    }

    private enum ExpectationError: Error { case missing(String) }
}
