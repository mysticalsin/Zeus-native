import Foundation

/// How a third provider would be added. Fish Audio is the example. It is not implemented and it is
/// not in `ProviderRegistry`.
///
/// Official reference, for the person who writes the adapter later:
/// https://docs.fish.audio/api-reference/endpoint/openapi-v1/text-to-speech
///
/// 1. Add one adapter file that conforms to `TTSProvider`. Build HTTPS requests only, with
///    `ProviderHTTPBudget.requestTimeout`, and keep the key out of the URL and out of logs.
/// 2. Add one `ProviderRegistry` entry whose descriptor id is the adapter id.
/// 3. `VoiceProviderRegistryTests.everyDescriptorHasAnAdapterAndViceVersa` fails until those two ids match.
public enum FishAudioRegistrationSteps: String, CaseIterable, Sendable {
    case adapterFile = "Add one adapter file that conforms to TTSProvider."
    case registryEntry = "Add one ProviderRegistry entry with the same id."
    case completenessTest = "The registry test keeps the descriptor list and the adapter list identical."
}
