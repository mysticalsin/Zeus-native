import Testing
@testable import ZeusCore

@Suite("Speech route gate")
struct SpeechRouteGateTests {
    @Test func onDeviceSpeaksWhenTheNetworkIsSilentAndNoKeyIsPresent() {
        let decision = SpeechRouteGate.decide(choice: .onDevice, key: .missing, network: .silent)
        #expect(decision == .onDevice)
    }

    @Test func onDeviceStaysOnDeviceWhenAKeyAndTheNetworkAreBothPresent() {
        let decision = SpeechRouteGate.decide(choice: .onDevice, key: .present, network: .answers)
        #expect(decision == .onDevice)
        if case .cloud = decision {
            Issue.record("on-device speech became a cloud route")
        }
    }

    @Test func zeusSetupUsesOnDeviceSpeech() {
        #expect(SpeechRouteGate.choice(for: .zeusSetup) == .onDevice)
        let quiet = SpeechRouteGate.decide(path: .zeusSetup, key: .missing, network: .silent)
        let ready = SpeechRouteGate.decide(path: .zeusSetup, key: .present, network: .answers)
        #expect(quiet == .onDevice)
        #expect(ready == .onDevice)
    }

    @Test func openAIRunsOnlyWhenItIsSelectedWithAKeyAndANetworkAnswer() {
        let decision = SpeechRouteGate.decide(path: .openAI, key: .present, network: .answers)
        #expect(decision == .cloud(.openAI))
        #expect(decision != .cloud(.elevenLabs))
        #expect(decision != .onDevice)
    }

    @Test func elevenLabsRunsOnlyWhenItIsSelectedWithAKeyAndANetworkAnswer() {
        let decision = SpeechRouteGate.decide(path: .anthropicElevenLabs, key: .present, network: .answers)
        #expect(SpeechRouteGate.choice(for: .anthropicElevenLabs) == .cloud(.elevenLabs))
        #expect(decision == .cloud(.elevenLabs))
        #expect(decision != .cloud(.openAI))
        #expect(decision != .onDevice)
    }

    @Test func selectingOpenAIDoesNotAuthorizeElevenLabs() {
        let selected = SpeechRouteGate.decide(choice: .cloud(.openAI), key: .present, network: .answers)
        #expect(selected == .cloud(.openAI))
        let other = SpeechRouteGate.decide(choice: .cloud(.elevenLabs), key: .present, network: .answers)
        #expect(other == .cloud(.elevenLabs))
        #expect(selected != other)
    }

    @Test func aCloudRouteWithNoKeyIsRefusedEvenWhenTheNetworkAnswers() {
        for route in SpeechCloudRoute.allCases {
            let decision = SpeechRouteGate.decide(choice: .cloud(route), key: .missing, network: .answers)
            #expect(decision == .refused(.missingKey))
            #expect(decision != .onDevice)
            #expect(decision != .cloud(route))
        }
    }

    @Test func aCloudRouteWithNeitherKeyNorNetworkRefusesTheMissingKey() {
        let openAI = SpeechRouteGate.decide(path: .openAI, key: .missing, network: .silent)
        let eleven = SpeechRouteGate.decide(path: .anthropicElevenLabs, key: .missing, network: .silent)
        #expect(openAI == .refused(.missingKey))
        #expect(eleven == .refused(.missingKey))
    }

    @Test func aCloudRouteWithAKeyAndASilentNetworkDoesNotFallBackToOnDevice() {
        for route in SpeechCloudRoute.allCases {
            let decision = SpeechRouteGate.decide(choice: .cloud(route), key: .present, network: .silent)
            #expect(decision == .refused(.networkSilent))
            #expect(decision != .onDevice)
            #expect(decision != .cloud(route))
        }
    }

    @Test func theAnthropicPathWithAKeyAndASilentNetworkIsRefused() {
        let decision = SpeechRouteGate.decide(path: .anthropicElevenLabs, key: .present, network: .silent)
        #expect(decision == .refused(.networkSilent))
    }

    @Test func theSameFactsDecideTheSameWayTwice() {
        let first = SpeechRouteGate.decide(path: .openAI, key: .present, network: .answers)
        let second = SpeechRouteGate.decide(path: .openAI, key: .present, network: .answers)
        let refused = SpeechRouteGate.decide(path: .openAI, key: .present, network: .silent)
        #expect(first == second)
        #expect(first == .cloud(.openAI))
        #expect(refused == .refused(.networkSilent))
    }

    @Test func everyProviderPathMapsToOneSpeechRoute() {
        var seen: [PointingProviderPath: SpeechRouteChoice] = [:]
        for path in PointingProviderPath.allCases {
            seen[path] = SpeechRouteGate.choice(for: path)
        }
        #expect(seen[.zeusSetup] == .onDevice)
        #expect(seen[.openAI] == .cloud(.openAI))
        #expect(seen[.anthropicElevenLabs] == .cloud(.elevenLabs))
        #expect(seen.count == PointingProviderPath.allCases.count)
    }
}
