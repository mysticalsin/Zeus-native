import Foundation
import Testing
@testable import ZeusCore

@Suite("Voice provider registry")
struct VoiceProviderRegistryTests {
    @Test func everyDescriptorHasAnAdapterAndViceVersa() {
        let entries = ProviderRegistry.entries
        let descriptorIDs = entries.map(\.descriptor.id)
        let adapterIDs = entries.map { $0.make().descriptor.id }
        #expect(descriptorIDs == adapterIDs)
        #expect(Set(descriptorIDs).count == descriptorIDs.count)
        #expect(descriptorIDs.count >= 2)
        for entry in entries {
            let made = entry.make()
            #expect(made.descriptor == entry.descriptor)
            #expect(ProviderRegistry.make(entry.descriptor.id)?.descriptor.id == entry.descriptor.id)
            #expect(ProviderRegistry.descriptor(entry.descriptor.id) == entry.descriptor)
            #expect(entry.descriptor.kind == .tts)
            #expect(entry.descriptor.docsURL.scheme == "https")
            #expect(!entry.descriptor.displayName.isEmpty)
            #expect(entry.descriptor.credentialFields.contains { $0.masked && $0.id == ProviderCredentialLocation.account })
            #expect(entry.descriptor.capabilities.contains(.listVoices))
            #expect(entry.descriptor.capabilities.contains(.streamingSynthesis))
            #expect(entry.descriptor.capabilities.contains(.validateCredential))
        }
    }

    @Test func speechAndLanguageKindsStayReservedUntilAnAdapterExists() {
        #expect(ProviderKind.allCases == [.tts, .stt, .llm])
        #expect(ProviderRegistry.entries.allSatisfy { $0.descriptor.kind == .tts })
        #expect(ProviderRegistry.make("fish-audio") == nil)
        #expect(ProviderRegistry.descriptor("fish-audio") == nil)
        #expect(!ProviderRegistry.entries.map(\.descriptor.id).contains(VoiceProviderChoice.localID))
        #expect(FishAudioRegistrationSteps.allCases.count == 3)
    }

    @Test func theFirstAdaptersAreElevenLabsAndGoogleCloud() {
        #expect(ProviderRegistry.descriptor(ElevenLabsTTSAdapter.id)?.displayName == "ElevenLabs")
        #expect(ProviderRegistry.descriptor(GoogleCloudTTSAdapter.id)?.displayName == "Google Cloud Text-to-Speech")
        #expect(ProviderCredentialLocation.service(for: ElevenLabsTTSAdapter.id) == "app.zeus.voice-provider.elevenlabs")
        #expect(ProviderCredentialLocation.service(for: GoogleCloudTTSAdapter.id) == "app.zeus.voice-provider.google-cloud-tts")
        #expect(ProviderCredentialLocation.account == "api-key")
        #expect(ProviderCredentialLocation.itemClass == "generic-password")
        #expect(ProviderCredentialLocation.accessible == "when-unlocked-this-device-only")
    }
}
