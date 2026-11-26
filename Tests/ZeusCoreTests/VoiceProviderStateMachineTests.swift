import Foundation
import Testing
@testable import ZeusCore

@Suite("Voice provider state machines")
struct VoiceProviderStateMachineTests {
    private static let states: [ProviderReadiness] = [
        .unset, .validating, .ready,
        .error(.unauthorized), .error(.rateLimited), .error(.server(503)),
        .error(.timedOut), .error(.invalidResponse),
    ]

    private static let events: [ProviderReadinessEvent] = [
        .saveCredential, .validationStarted, .validationSucceeded,
        .validationFailed(.unauthorized), .validationFailed(.timedOut),
        .remove, .runtimeFailure(.server(500)), .runtimeFailure(.rateLimited), .retry,
    ]

    @Test func everyStateAndEventPairIsGuarded() {
        for state in Self.states {
            for event in Self.events {
                var machine = ProviderReadinessMachine(state: state)
                let before = machine.state
                let effect = machine.reduce(event)
                switch event {
                case .remove:
                    #expect(machine.state == .unset)
                    #expect(effect == .deleteCredential)
                case .saveCredential:
                    #expect(machine.state == .validating)
                    #expect(effect == .beginValidation)
                case .retry:
                    if case .error = before {
                        #expect(machine.state == .validating)
                        #expect(effect == .beginValidation)
                    } else if case .validating = before {
                        #expect(machine.state == .validating)
                        #expect(effect == .beginValidation)
                    } else {
                        #expect(machine.state == before)
                        #expect(effect == .ignored)
                    }
                case .validationSucceeded:
                    if case .validating = before {
                        #expect(machine.state == .ready)
                    } else {
                        #expect(machine.state == before)
                    }
                    #expect(effect == .ignored)
                case .validationFailed(let reason):
                    if case .validating = before {
                        #expect(machine.state == .error(reason))
                    } else {
                        #expect(machine.state == before)
                    }
                    #expect(effect == .ignored)
                case .runtimeFailure(let reason):
                    if case .ready = before {
                        #expect(machine.state == .error(reason))
                    } else {
                        #expect(machine.state == before)
                    }
                    #expect(effect == .ignored)
                case .validationStarted:
                    #expect(machine.state == before)
                    #expect(effect == .ignored)
                }
            }
        }
    }

    @Test func randomEventSequencesStayInsideTheGuards() {
        var rng = SplitMix64(seed: 0xC0FFEE)
        let events = Self.events
        for _ in 0..<200 {
            var machine = ProviderReadinessMachine()
            #expect(machine.state == .unset)
            for _ in 0..<40 {
                let event = events[Int(rng.next() % UInt64(events.count))]
                let before = machine.state
                let effect = machine.reduce(event)
                if effect == .ignored {
                    let changed = machine.state != before
                    let allowedChange = changed && isLegalChange(from: before, event: event, to: machine.state)
                    #expect(!changed || allowedChange)
                }
                #expect(isLegalState(machine.state))
            }
            let removed = machine.reduce(.remove)
            #expect(removed == .deleteCredential)
            #expect(machine.state == .unset)
        }
    }

    @Test func theActiveVoiceDefaultsToTheLocalVoice() {
        var selection = VoiceProviderSelectionMachine()
        #expect(selection.choice == .local)
        selection.reduce(.select(ElevenLabsTTSAdapter.id))
        selection.reduce(.chooseVoice(providerID: ElevenLabsTTSAdapter.id, voiceID: "rachel"))
        #expect(selection.choice == .provider(ElevenLabsTTSAdapter.id))
        #expect(selection.voiceID(for: ElevenLabsTTSAdapter.id) == "rachel")
        selection.reduce(.selectLocal)
        #expect(selection.choice == .local)
        #expect(selection.voiceID(for: ElevenLabsTTSAdapter.id) == "rachel")
        selection.reduce(.select(GoogleCloudTTSAdapter.id))
        selection.reduce(.remove(ElevenLabsTTSAdapter.id))
        #expect(selection.choice == .provider(GoogleCloudTTSAdapter.id))
        selection.reduce(.remove(GoogleCloudTTSAdapter.id))
        #expect(selection.choice == .local)
        selection.reduce(.select("  "))
        selection.reduce(.select(VoiceProviderChoice.localID))
        #expect(selection.choice == .local)
    }

    private func isLegalState(_ state: ProviderReadiness) -> Bool {
        switch state {
        case .unset, .validating, .ready, .error: true
        }
    }

    private func isLegalChange(from before: ProviderReadiness, event: ProviderReadinessEvent, to after: ProviderReadiness) -> Bool {
        switch (before, event, after) {
        case (.validating, .validationSucceeded, .ready): true
        case (.validating, .validationFailed(let reason), .error(let got)) where reason == got: true
        case (.ready, .runtimeFailure(let reason), .error(let got)) where reason == got: true
        default: false
        }
    }
}

/// A fixed generator so the property walk is the same on every machine.
struct SplitMix64: Sendable {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
