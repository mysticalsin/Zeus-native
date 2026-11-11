# Zeus voice pipeline

Zeus speaks as an original synthetic persona: a deep baritone, calm, precise diction, a faint synthetic sheen,
measured pacing, dry wit, quiet courtesy and a hint of grandeur. It does not clone or imitate any real actor's
voice and quotes no film lines. The persona and the voice effect are the default on a fresh install.

## Why the Mac voice "Samantha" was heard (build 0405391)

The log line `engine=system voice=Samantha default` came from three facts together: no ElevenLabs or OpenAI key
in the Zeus Keychain (`voice: ready engines=` was empty), Kokoro not set up, and a system fallback that picked
the best-quality voice for the locale, which on a Mac with only compact voices is Samantha. The old fallback
also used `AVSpeechSynthesizer.speak`, which bypasses any audio processing, so no Ultron effect was applied.

## Engine routing (`ZeusCore/Voice/UltronEngineRouter.swift`)

`auto` (default) tries, in order: ElevenLabs (key or worker route), OpenAI voice, Kokoro (on this Mac), then the
Mac voice. Paused engines (after a 401, quota or timeout) are skipped, and an engine whose recent first-audio time
is over 2.5 s drops behind a faster one. Chatterbox clones from a reference clip, so it is used only when chosen.
Picking one engine in Settings makes it lead; the rest remain as fallbacks. The Mac voice is always last.
Every spoken line logs `engine=... voice=... effect=60% reason=... first_audio_ms=...` (keys are never logged).

## Voices per engine

- ElevenLabs: Voice Design from a text description (`VoiceDesigner`). The first ElevenLabs use with no saved voice
  designs one once in the background, keeps the first preview and stores only the voice id (Keychain account
  `elevenlabs.voice-id`). Until then the stock voice speaks. Delivery settings: stability 0.35, style 0.3, speed 0.95.
- OpenAI: model `gpt-4o-mini-tts`, voice `onyx`, with tone instructions (sent only to gpt-4o models), raw 24 kHz
  PCM streamed while it downloads.
- Kokoro: `am_michael` at speed 0.88, rendered per sentence.
- Mac voice: the deepest male voice installed (`UltronSystemVoicePick`: premium and enhanced first, never Samantha,
  never a female or novelty voice), rate 0.92 of normal, pitch 0.82, rendered to buffers with
  `AVSpeechSynthesizer.write` and played through the same effect chain.

## Effect chain (`Sources/Zeus/Voice/UltronAudioChain.swift`)

Every engine's audio is converted to 24 kHz mono and played through one `AVAudioEngine` graph:
time pitch (-350 cents at 60 %, -450 at 100 %), EQ (low shelf 140 Hz up to +7.5 dB, high shelf 4.5 kHz up to
+5 dB), radio-tower distortion at a very low mix (up to 8 %), a 10 ms comb delay (feedback up to 35 %, wet up to
14 %) for the metallic sheen, and a small room (wet up to 10 %), with an output trim. The numbers by intensity
are `UltronEffectParameters.make(percent:)`. Settings > Voice has the toggle and an intensity slider (0 to 100 %,
default 60 %). Intensity 0 or the toggle off is neutral. The same graph runs offline for silent previews and tests.

## Latency and the sentence API

Playback starts when the first buffer of the first sentence arrives. ElevenLabs and OpenAI stream bytes into the
player; Kokoro and the Mac voice schedule per sentence. A sentence is scheduled, not awaited, so the next sentence
is requested while the previous one plays. The engine is warmed lazily on the first talk-key press
(`Speaker.talkKeyPressed`), never at launch.

The brain agent calls this protocol (`ZeusCore/Voice/SentenceStreaming.swift`):

```swift
@MainActor public protocol SentenceSpeaking: AnyObject {
    func speak(sentenceStream: AsyncStream<String>) async -> SpeakOutcome
    func prewarm()
    func stop()
}
```

`Speaker` conforms. Feed it complete sentences, for example from `SentenceChunker` (`feed(delta)` returns finished
sentences, `flush()` returns the tail). The call returns when the last sentence has played or the task is
cancelled; `SpeakOutcome` carries the engine, voice, reason and time to first audio. `Speaker.speak(_:)`, used by
`VoiceTurnController` today, queues a sentence the same way.

## Self-test

`bash scripts/voice-selftest.sh [--silent] [<Zeus.app>]` runs `Zeus --voice-engine-selftest`: one fixed line through
each available engine with the effect, then a receipt in `~/AI-Brain-build/voice-selftest/` listing engine,
availability reason, spoke or not, and time to first audio in ms. It exits 0 when the Mac voice spoke through the
effect and was not Samantha. It refuses to run in CI. `--silent` runs the chain with the volume at zero.
