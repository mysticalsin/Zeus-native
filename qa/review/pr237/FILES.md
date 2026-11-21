# PR 237 files versus the PR base

Base: `zeus-bot/voice-providers` `16c2d697dcd479f6cbe510ad65fda731b82194fa`.
Code head these tags were read from: `f00007895b6091afc7cfa33dee3ceede290ef7d0`.
Changed files: 77.

PR-authored means the blob at this head is not the blob from #116, #139, or #229. Inherited means the bytes match that merge's head.

| File | Tag |
| --- | --- |
| `LICENSES/jarvis2.0-LICENSE` | inherited #229 |
| `Resources/NOTICES.txt` | inherited #229 |
| `SWEEPS.md` | PR-authored |
| `Sources/Zeus/App/DebugCommands.swift` | inherited #229 |
| `Sources/Zeus/App/DebugForward.swift` | inherited #229 |
| `Sources/Zeus/Brain/ZeusPrompt.swift` | inherited #229 |
| `Sources/Zeus/Companion/Orb/OrbMascotView.swift` | inherited #229 |
| `Sources/Zeus/Companion/Orb/OrbMetalRenderer.swift` | inherited #229 |
| `Sources/Zeus/Companion/Orb/OrbOffscreenHarness.swift` | inherited #229 |
| `Sources/Zeus/Companion/PersonaSetting.swift` | inherited #229 |
| `Sources/Zeus/Overlay/BuddyOverlayView.swift` | inherited #229 |
| `Sources/Zeus/Settings/GSVoiceCards.swift` | inherited #229 |
| `Sources/Zeus/Settings/GlanceSettingsPages.swift` | inherited #229 |
| `Sources/Zeus/Voice/PluginVoiceBridge.swift` | inherited #139, #229 |
| `Sources/Zeus/Voice/Speaker.swift` | inherited #229 |
| `Sources/Zeus/Voice/UltronAudioChain.swift` | inherited #229 |
| `Sources/Zeus/Voice/VoiceSettings.swift` | inherited #229 |
| `Sources/ZeusCore/Companion/JarvisPersona.swift` | inherited #229 |
| `Sources/ZeusCore/Companion/MascotPersona.swift` | inherited #229 |
| `Sources/ZeusCore/Companion/OrbAudio.swift` | inherited #229 |
| `Sources/ZeusCore/Companion/OrbPersona.swift` | inherited #229 |
| `Sources/ZeusCore/Companion/OrbSimulation.swift` | inherited #229 |
| `Sources/ZeusCore/Companion/OrbTurnOracle.swift` | inherited #229 |
| `Sources/ZeusCore/Companion/Persona.swift` | inherited #229 |
| `Sources/ZeusCore/Providers/ElevenLabsTTSAdapter.swift` | inherited #139, #229 |
| `Sources/ZeusCore/Providers/GoogleCloudTTSAdapter.swift` | inherited #139, #229 |
| `Sources/ZeusCore/Providers/ProviderPlaybackGate.swift` | inherited #116 |
| `Sources/ZeusCore/Providers/ProviderTypes.swift` | inherited #139, #229 |
| `Sources/ZeusCore/Providers/VoiceProviderSession.swift` | inherited #139, #229 |
| `Sources/ZeusCore/Providers/VoiceQualityMeter.swift` | PR-authored |
| `Sources/ZeusCore/Providers/VoiceQualityPreset.swift` | PR-authored |
| `Sources/ZeusCore/Voice/PersonaSpeakRoute.swift` | inherited #229 |
| `Sources/ZeusCore/Voice/SpeakPath.swift` | inherited #139, #229 |
| `Sources/ZeusCore/Voice/UltronEngineRouter.swift` | inherited #229 |
| `Sources/ZeusCore/Voice/UltronVoicePlan.swift` | inherited #229 |
| `Tests/ZeusAppTests/DebugCommandTests.swift` | inherited #229 |
| `Tests/ZeusCoreTests/OpenAISpeechRetirementTests.swift` | inherited #229 |
| `Tests/ZeusCoreTests/OrbE2EJourneyTests.swift` | inherited #229 |
| `Tests/ZeusCoreTests/OrbPersonaTests.swift` | inherited #229 |
| `Tests/ZeusCoreTests/OrbSimulationTests.swift` | inherited #229 |
| `Tests/ZeusCoreTests/PersonaSpeakRouteTests.swift` | inherited #229 |
| `Tests/ZeusCoreTests/PersonaSwapTests.swift` | inherited #229 |
| `Tests/ZeusCoreTests/ProviderPlaybackGateTests.swift` | inherited #116 |
| `Tests/ZeusCoreTests/QA20FixTests.swift` | inherited #229 |
| `Tests/ZeusCoreTests/SpeakPathFixTests.swift` | inherited #139, #229 |
| `Tests/ZeusCoreTests/UltronElevenFirstTests.swift` | inherited #229 |
| `Tests/ZeusCoreTests/UltronVoicePipelineTests.swift` | inherited #229 |
| `Tests/ZeusCoreTests/VoiceCatalogTests.swift` | inherited #229 |
| `Tests/ZeusCoreTests/VoiceProviderAdapterTests.swift` | inherited #139, #229 |
| `Tests/ZeusCoreTests/VoiceProviderSessionTests.swift` | inherited #139, #229 |
| `Tests/ZeusCoreTests/VoiceQualityPresetTests.swift` | PR-authored |
| `Tests/ZeusCoreTests/VoiceQualityRouteSecurityTests.swift` | PR-authored |
| `qa/orb-e2e/BenchMain.swift` | inherited #229 |
| `qa/orb-e2e/reportlib.py` | inherited #229 |
| `qa/orb-e2e/run.sh` | inherited #229 |
| `qa/orb-e2e/runner.py` | inherited #229 |
| `qa/orb-e2e/spec_oracle.py` | inherited #229 |
| `qa/orb-e2e/test_runner.py` | inherited #229 |
| `qa/review/pr237/01-VoiceQualityMeter-part1.patch` | PR-authored |
| `qa/review/pr237/02-VoiceQualityMeter-part2.patch` | PR-authored |
| `qa/review/pr237/03-VoiceQualityPreset-part1.patch` | PR-authored |
| `qa/review/pr237/04-VoiceQualityPreset-part2.patch` | PR-authored |
| `qa/review/pr237/05-VoiceQualityPreset-part3.patch` | PR-authored |
| `qa/review/pr237/06-VoiceQualityPreset-part4.patch` | PR-authored |
| `qa/review/pr237/07-VoiceQualityPreset-part5.patch` | PR-authored |
| `qa/review/pr237/08-VoiceQualityPresetTests-part1.patch` | PR-authored |
| `qa/review/pr237/09-VoiceQualityPresetTests-part2.patch` | PR-authored |
| `qa/review/pr237/10-VoiceQualityPresetTests-part3.patch` | PR-authored |
| `qa/review/pr237/11-VoiceQualityPresetTests-part4.patch` | PR-authored |
| `qa/review/pr237/12-VoiceQualityPresetTests-part5.patch` | PR-authored |
| `qa/review/pr237/13-VoiceQualityRouteSecurityTests-part1.patch` | PR-authored |
| `qa/review/pr237/14-VoiceQualityRouteSecurityTests-part2.patch` | PR-authored |
| `qa/review/pr237/15-VoiceQualityRouteSecurityTests-part3.patch` | PR-authored |
| `qa/review/pr237/16-VoiceQualityRouteSecurityTests-part4.patch` | PR-authored |
| `qa/review/pr237/INDEX.md` | PR-authored |
| `scripts/bundle.sh` | inherited #229 |
| `specs/007-companion-parity/e2e-mac-orb.md` | inherited #229 |

## Speak path, keys, Keychain, logging, network

`synthesizeIfEnabled` is defined in `Sources/ZeusCore/Providers/VoiceQualityPreset.swift` and called from `Tests/ZeusCoreTests/VoiceQualityPresetTests.swift`. No other file calls it.

The only PR-authored files under `Sources/` are `VoiceQualityMeter.swift` and `VoiceQualityPreset.swift`. Both touch the speak path, keys, and network. There is no further PR-authored `Sources/` file to slice. Keychain updates live in inherited `CredentialStore.swift` (`#53` via the PR base, unchanged versus #139/#229).

