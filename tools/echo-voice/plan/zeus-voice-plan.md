# Zeus voice layer: red-first plan draft (Echo, 2026-11-20)

**Status:** this is a draft for coordination with Zeus's owner agent (2600f360) via the parent. No repo change was made and nobody was contacted. It was read-only from the public GitHub repo [mysticalsin/Zeus-native](https://github.com/mysticalsin/Zeus-native):
- `main` = `d6d45dd` (2026-11-19 04:02 UTC = 01:02 BRT);
- `codex/integration-20261111` = `2722dcb`, 6 commits ahead of main, touching 3 files, none in voice/TTS.

## What Zeus already has (verified at d6d45dd)
- **TTS engine router:** `UltronEngine` = elevenLabs, openAI, gemini, kokoro, chatterbox, system, plus a pure `UltronEngineRouter.chain(...)` with skip reasons and slow-engine demotion ([UltronEngineRouter.swift](https://github.com/mysticalsin/Zeus-native/blob/d6d45ddeae334e63134f11eb36be1d663b2637b3/Sources/ZeusCore/Voice/UltronEngineRouter.swift)).
  - There is also an older `VoiceTTSProvider` enum with fallback and pause tracker ([VoiceTTSProvider.swift](https://github.com/mysticalsin/Zeus-native/blob/d6d45ddeae334e63134f11eb36be1d663b2637b3/Sources/ZeusCore/Voice/VoiceTTSProvider.swift)).
  - It has a 4 s first-audio timeout ([VoiceTTSChain.swift](https://github.com/mysticalsin/Zeus-native/blob/d6d45ddeae334e63134f11eb36be1d663b2637b3/Sources/ZeusCore/Voice/VoiceTTSChain.swift)).
- **Sentence streaming contract:** `SentenceSpeaking.speak(sentenceStream:) -> SpeakOutcome`, with `firstAudioMs` ([SentenceStreaming.swift](https://github.com/mysticalsin/Zeus-native/blob/d6d45ddeae334e63134f11eb36be1d663b2637b3/Sources/ZeusCore/Voice/SentenceStreaming.swift)). `Speaker` conforms. Every engine's audio goes to 24 kHz mono through the Ultron effect chain ([VOICE-PIPELINE.md](https://github.com/mysticalsin/Zeus-native/blob/d6d45ddeae334e63134f11eb36be1d663b2637b3/docs/VOICE-PIPELINE.md)).
- **Local Kokoro is already a resident Python worker:** JSON lines on stdin, kokoro-onnx, in a private venv under Application Support/Zeus/Python ([KokoroWorker.swift](https://github.com/mysticalsin/Zeus-native/blob/d6d45ddeae334e63134f11eb36be1d663b2637b3/Sources/Zeus/Voice/KokoroWorker.swift), [LocalPython.swift](https://github.com/mysticalsin/Zeus-native/blob/d6d45ddeae334e63134f11eb36be1d663b2637b3/Sources/Zeus/Voice/LocalPython.swift)).
- **Persona rule:** an original synthetic deep-baritone "Ultron" voice, which "does not clone or imitate any real actor's voice" (VOICE-PIPELINE.md). The latency targets are talk-key-up to first audio p50 ≤ 1.2 s (API brains) and ≤ 2.5 s (CLI brains) ([VOICE-LATENCY.md](https://github.com/mysticalsin/Zeus-native/blob/d6d45ddeae334e63134f11eb36be1d663b2637b3/docs/VOICE-LATENCY.md)).
- **Tests and checks:** Swift Testing (`@Suite`, `@Test`, `#expect`) in `Tests/ZeusCoreTests`. Repo rules (AGENTS.md): use `swift test --filter SuiteName` for a focused change and `./tools/check.sh development` for the gate. Update the bindings in `qa/feature-map.json` alongside the change. Tests use synthetic records and generated audio only.

So the "voice layer" is **not greenfield**. TTS slots into the existing router. Two-way conversation is new: today's turn is STT → brain → TTS in `VoiceTurnController`, and a duplex model would replace that loop for a "conversation mode".

## Where things plug in
| Capability | Engine | Plug point | Transport |
|---|---|---|---|
| Read text aloud (FR+EN) | Kyutai **Pocket TTS** (Rust binary, CPU), then optionally Kyutai TTS 1.6B (MLX) | A new `UltronEngine` case behind a flag, after the cloud engines and before `.kokoro` in `autoOrder` once proven | Resident child process, like `KokoroWorker` (stdin/stdout or its `serve` command; the exact `serve` API is **unverified**) |
| Two-way conversation | **Haru-4B** via `haru_mlx.native` | A new `DuplexVoiceBackend`, used only in an opt-in "conversation mode", **not** in `UltronEngineRouter` | Haru's Unix socket in `$TMPDIR` with frames `struct.pack("<BI", kind, len)` ([native.py](https://github.com/higurashi-ai/Haru/blob/7fe6b7665f8bf035998f401f8cb779fbe53f2751/haru_mlx/haru_mlx/native.py), Swift client [Connection.swift](https://github.com/higurashi-ai/Haru/blob/7fe6b7665f8bf035998f401f8cb779fbe53f2751/haru_mlx/swift/Shared/Connection.swift)). The message kinds are **not yet read** |

## Smallest first PR slice (red first, flag off, ZeusCore only, no new dependency, no model)
**Branch:** `voice/local-backend-contract` (name TBD by the Zeus owner).

**Adds (ZeusCore, pure Swift):**
1. `Sources/ZeusCore/Voice/DuplexVoiceBackend.swift`
   - `struct DuplexFrame { audio: [Float] /*3200 @ 24 kHz*/; text: String; index: Int }`
   - `protocol DuplexVoiceBackend: Sendable { func start(persona: String) async throws -> DuplexFrame; func step(userAudio: [Float]) async throws -> DuplexFrame; func close() async }`
   - `enum DuplexVoiceError: Error { case badFrameSize(Int), notStarted, closed }`
   - `final class FakeDuplexVoiceBackend: DuplexVoiceBackend`. It returns canned silent frames with scripted text, enforces 3200-sample frames, keeps the model one frame ahead (start → index 0, each step → index + 1), and throws after `close()`. This mirrors Haru's `DuplexSession` contract ([session.py](https://github.com/higurashi-ai/Haru/blob/7fe6b7665f8bf035998f401f8cb779fbe53f2751/haru_mlx/haru_mlx/session.py)).
2. `Sources/ZeusCore/Voice/LocalVoiceFlags.swift`
   - `struct LocalVoiceFlags { var conversationMode = false; var pocketTTS = false }` is read from UserDefaults keys `voice.conversationMode.enabled` and `voice.pocketTTS.enabled`. **Both default to false.**

**Tests (written first, so they fail to compile and run red):** `Tests/ZeusCoreTests/LocalVoiceBackendContractTests.swift`
- `startReturnsFrameZeroOf3200Samples`
- `stepAdvancesOneFrameAhead` (frames 1…n)
- `stepRejectsWrongFrameSize` (`badFrameSize(3199)`)
- `stepBeforeStartThrowsNotStarted`
- `closeThenStepThrowsClosed`
- `flagsDefaultOff` (fresh UserDefaults suite → both false)
- `routerChainUnchangedWhenFlagsOff`: `UltronEngineRouter.chain` for a fixed availability matrix equals today's output. This is a regression guard; it passes before and after, and it protects existing behaviour.

**Failing test to start with:** `LocalVoiceBackendContractTests/startReturnsFrameZeroOf3200Samples`. It fails today because `DuplexVoiceBackend` and `FakeDuplexVoiceBackend` don't exist.

**TEST COMMAND** (run on Tony's Mac, the repo root of the QA clone; Linux can't build the app target):
```sh
swift test --filter LocalVoiceBackendContractTests
```
Then the gate: `./tools/check.sh development` and a `qa/feature-map.json` binding for the new suite.

**Explicitly out of scope for slice 1:**
- no audio I/O;
- no Python, Rust binary or model download;
- no change to `Speaker`, `VoiceTurnController` or `UltronEngine`;
- no UI.

## Next slices (each red-first, flag off)
2. **Pocket TTS engine adapter.**
   - `UltronEngine.pocketTTS`, with a skip reason "Pocket TTS not set up" until the binary and voice are present.
   - Router tests: it is absent when the flag is off, and placed before `.kokoro` when the flag is on and it is ready.
   - Process adapter tested with a fake binary script emitting a known WAV.
   - Needs: Tony's OK to download the official release binary (`pocket-tts-*-aarch64-apple-darwin.tar.gz`, verified against `SHA256SUMS`), accepting the HF gate, and a voice whose licence is not non-commercial.
3. **Haru socket adapter.** `HaruSocketDuplexBackend: DuplexVoiceBackend` over the Unix socket. It is tested against a fake socket server that replays recorded protocol frames. First read `native.py` and its message kinds.
4. **Conversation mode UI + audio I/O.** It is gated by `voice.conversationMode.enabled` and by mic consent through the OS prompt only. Measure first-audio and RTF with `haru_bench.py` and Zeus's `voice-latency.sh`.

## Risks
- Memory: Haru bf16 peaks at about 13.5 GB, plus Zeus, Whisper/Parakeet and a TTS engine, all on 32 GB unified memory. Measure before enabling both together.
- The persona conflicts with French voices. Kokoro French has only a female voice, and the Pocket TTS/Kyutai French catalog voices need checking against the deep-baritone persona plus the effect chain.
- Every bundled voice is a recorded person under a dataset licence (VCTK CC-BY, donations CC0). Avoid non-commercial voices (Expresso, EARS) and never clone.
- Haru is a base model that "does not follow instructions". Conversation mode would be chit-chat, not Zeus's tool-using brain.

## Agreed with Zeus (2026-11-20 16:10 BRT)
1. Read-aloud = new `VoiceEngine` case (VoiceSettings.swift) behind flag, rendering via existing `SpeechOutputProvider.render(_:)` through `PointingSpeechRouter`. No new router.
2. `DuplexVoiceBackend` in ZeusCore: `Sendable`, methods `async throws`; frame-size and lifecycle errors as specified.
3. Base: codex/integration-20261111 (ZeusCore-only, Linux-testable; rebase after PlacedMark fix).
4. Extra test: flags-off path makes no network call or process launch.
Branch: zeus-bot/local-voice-contract (Zeus's writer). Echo = domain reviewer; Devin, Inspector, Sentinel gate.
