# Presets v2 files versus integration

Base: `codex/integration-20261111` `2722dcb7497d5415fbc1fcb1f65c49629966a281`.

| File | Tag |
| --- | --- |
| `SWEEPS.md` | PR-authored |
| `Sources/Zeus/Brain/ZeusPrompt.swift` | needed #53, #116, #139 |
| `Sources/Zeus/Settings/GSVoiceCards.swift` | needed #53, #116, #139 |
| `Sources/Zeus/Settings/VoiceProvidersCard.swift` | needed #53, #116, #139 |
| `Sources/Zeus/Voice/PluginVoiceBridge.swift` | needed #139 |
| `Sources/Zeus/Voice/Speaker.swift` | needed #139 |
| `Sources/Zeus/Voice/VoiceSettings.swift` | needed #53, #116, #139 |
| `Sources/ZeusCore/Providers/CredentialStore.swift` | PR-authored |
| `Sources/ZeusCore/Providers/ElevenLabsTTSAdapter.swift` | needed #139 |
| `Sources/ZeusCore/Providers/FishAudioProviderStub.swift` | needed #53, #116, #139 |
| `Sources/ZeusCore/Providers/GoogleCloudTTSAdapter.swift` | needed #139 |
| `Sources/ZeusCore/Providers/ProviderEngineBook.swift` | needed #53, #116, #139 |
| `Sources/ZeusCore/Providers/ProviderHTTP.swift` | needed #53, #116, #139 |
| `Sources/ZeusCore/Providers/ProviderLog.swift` | needed #53, #116, #139 |
| `Sources/ZeusCore/Providers/ProviderMachines.swift` | needed #53, #116, #139 |
| `Sources/ZeusCore/Providers/ProviderPlaybackGate.swift` | needed #116 |
| `Sources/ZeusCore/Providers/ProviderRegistry.swift` | needed #53, #116, #139 |
| `Sources/ZeusCore/Providers/ProviderTypes.swift` | PR-authored |
| `Sources/ZeusCore/Providers/TTSProvider.swift` | needed #53, #116, #139 |
| `Sources/ZeusCore/Providers/VoiceProviderE2E.swift` | needed #53, #116, #139 |
| `Sources/ZeusCore/Providers/VoiceProviderSession.swift` | needed #139 |
| `Sources/ZeusCore/Providers/VoiceQualityMeter.swift` | PR-authored |
| `Sources/ZeusCore/Providers/VoiceQualityPreset.swift` | PR-authored |
| `Sources/ZeusCore/Voice/SpeakPath.swift` | needed #139 |
| `Sources/ZeusCore/Voice/UltronEngineRouter.swift` | needed #53, #116, #139 |
| `Sources/ZeusCore/Voice/UltronVoicePlan.swift` | needed #53, #116, #139 |
| `Sources/ZeusCore/Voice/VoiceProviderKeychain.swift` | needed #53, #116, #139 |
| `Sources/ZeusCore/Voice/VoiceTTSProvider.swift` | needed #53, #116, #139 |
| `Tests/ZeusCoreTests/OpenAISpeechRetirementTests.swift` | needed #53, #116, #139 |
| `Tests/ZeusCoreTests/ProviderEngineBookTests.swift` | needed #53, #116, #139 |
| `Tests/ZeusCoreTests/ProviderPlaybackGateTests.swift` | needed #116 |
| `Tests/ZeusCoreTests/QA20FixTests.swift` | needed #53, #116, #139 |
| `Tests/ZeusCoreTests/SpeakPathFixTests.swift` | needed #139 |
| `Tests/ZeusCoreTests/UltronElevenFirstTests.swift` | needed #53, #116, #139 |
| `Tests/ZeusCoreTests/UltronVoicePipelineTests.swift` | needed #53, #116, #139 |
| `Tests/ZeusCoreTests/VoiceCatalogTests.swift` | needed #53, #116, #139 |
| `Tests/ZeusCoreTests/VoiceProviderAdapterTests.swift` | needed #139 |
| `Tests/ZeusCoreTests/VoiceProviderE2EJourneyTests.swift` | needed #53, #116, #139 |
| `Tests/ZeusCoreTests/VoiceProviderFakeTests.swift` | needed #53, #116, #139 |
| `Tests/ZeusCoreTests/VoiceProviderLiveContractTests.swift` | needed #53, #116, #139 |
| `Tests/ZeusCoreTests/VoiceProviderRegistryTests.swift` | needed #53, #116, #139 |
| `Tests/ZeusCoreTests/VoiceProviderSessionTests.swift` | needed #139 |
| `Tests/ZeusCoreTests/VoiceProviderStateMachineTests.swift` | needed #53, #116, #139 |
| `Tests/ZeusCoreTests/VoiceQualityNoUpstreamRouteTests.swift` | PR-authored |
| `Tests/ZeusCoreTests/VoiceQualityPresetTests.swift` | PR-authored |
| `Tests/ZeusCoreTests/VoiceQualityRouteSecurityTests.swift` | PR-authored |
| `qa/closed-loop/human_qa.py` | needed #53, #116, #139 |
| `qa/providers-e2e/report.py` | needed #53, #116, #139 |
| `qa/providers-e2e/run.sh` | needed #53, #116, #139 |
| `scripts/human-qa.sh` | needed #53, #116, #139 |
| `scripts/human-qa.swift` | needed #53, #116, #139 |
| `specs/008-providers/e2e-mac.md` | needed #53, #116, #139 |
| `specs/008-providers/plan.md` | needed #53, #116, #139 |
| `specs/008-providers/research.md` | needed #53, #116, #139 |
| `specs/008-providers/spec.md` | needed #53, #116, #139 |

No parked-stack paths are in this branch. `synthesizeIfEnabled` is defined in `Sources/ZeusCore/Providers/VoiceQualityPreset.swift` and called from `Tests/ZeusCoreTests/VoiceQualityPresetTests.swift`.

