# Voice QA harness

This directory measures rendered speech. It does not change the app. The scripts are original fixture text. They are not transcripts of anyone.

Python 3.12. From the repository root:

```sh
python3.12 -m venv /tmp/zeus-voice-qa
/tmp/zeus-voice-qa/bin/pip install --require-hashes -r qa/voice/requirements.txt
/tmp/zeus-voice-qa/bin/python -m pytest qa/voice/tests/test_metrics.py -q
```

`metrics.py` reads a WAV and a timing JSON. `report.py` writes `metrics.json` and `report.md` for a directory of those pairs. `render_kokoro.py` renders the script set on Linux. `mac/render_mac.sh` is the Mac entrypoint.

## How a reply reaches a voice

The live utterance path on this branch is `VoiceTurnController` to `Speaker`.

1. A brain sentence, a fast-path acknowledgement, or `VoiceTurnController.say` calls `VoiceTurnController.voiced`.
2. `voiced` runs `PersonaCompliance.stripOminousHedges`, then `UltronSpeechText.prepared`. For the Ultron personality that replaces a spoken ellipsis. Plain personality leaves the text alone.
3. `Speaker.speak` queues the line. `Speaker.speak(sentenceStream:)` does the same, one sentence at a time, and returns `SpeakOutcome.firstAudioMs` for the first sentence that produced audio.
4. `speakLine` walks `VoiceSettings.routeDecisions()`. That is `UltronEngineRouter.chain` with `VoiceSettings.engineChoice` and `VoiceSettings.ultronAvailability()`. The first engine that returns audio is the one that spoke. The Mac voice is always last in that chain.
5. A talk-key press or `stopSpeaking` calls `Speaker.stop`. That cancels the queue, stops `UltronAudioChain`, and calls `AVSpeechSynthesizer.stopSpeaking(at: .immediate)`. `SpeechAttemptPolicy.mayPlay` refuses audio that finishes rendering after the cancel, so a late Kokoro file is deleted instead of played.

`VoiceRouting.resolve` is a pure helper covered by `VoiceRoutingTests`. `Speaker.speakLine` does not call it. The chain above is the one that speaks.

### Flags that choose the engine

| Key | What it does |
| --- | --- |
| `voice.engine.auto` | Missing or true: automatic order. Setting a provider in Settings writes false. |
| `voice.ttsProvider` | `kokoro`, `chatterbox`, `elevenLabs`, `openAICompatible`, or `gemini`. With automatic off, that engine leads and the rest of the automatic order remains as fallback. |
| `voice.engine` and `voice.engine.userSelected` | Launch-time `VoiceEngine` (`system`, `elevenLabs`, `kokoro`). The live chain still follows `engineAuto` and `voice.ttsProvider`. |
| `voice.kokoro.voice` | Kokoro voice id. Missing value is `am_michael` (`UltronCloudVoice.kokoroVoice`). |
| `voice.kokoro.speed` | Kokoro speed. Missing value is `0.88`. |
| `voice.kokoro.modelDir` | Model directory. Missing value is `~/AI-Brain-build/jarvis-laya-backend/models`. Setup uses `~/Library/Application Support/Zeus/Kokoro`. |
| `voice.elevenlabs.pausedUntil` | A 401 or 402 pauses ElevenLabs for 15 minutes. A timeout or network failure pauses it for 60 seconds in memory. |
| `voice.provider.pause.<provider>` | Other providers stay out of the chain until this date. |
| `voice.firstAudioMs.<engine>` | Smoothed time to first audio. In automatic mode a non-ElevenLabs engine over 2500 ms is tried after the faster ones. ElevenLabs is not demoted for being slow. |
| `voice.speakReplies` | `VoiceTurnController.say` speaks only when this is on. The talk path does not consult it. |

Automatic order in `UltronEngineRouter.autoOrder` is ElevenLabs, OpenAI, Gemini, Kokoro, then the Mac voice. An engine is skipped when its key is missing, its model is not set up, or it is paused. Chatterbox is used only when it is the explicit pick. There is no Settings value that means "system voice"; the Mac voice is the last resort when every earlier engine is skipped. With no keys and Kokoro not set up, the chain is the Mac voice alone.

Kokoro counts as ready when `kokoro-v1.0.onnx` and `voices-v1.0.bin` are both present and `import kokoro_onnx` succeeds (`KokoroWorker.isSetUp`).

## zeus.synthetic

This id is not on `codex/integration-20261111`. It is on PR 52 at `665b9167303f9596d5222b77a663e36f780d60d7`, in `Sources/ZeusCore/Companion/Persona.swift`.

`PersonaSyntheticVoice.voiceID` is `zeus.synthetic`. `ResolvedVoice.zeusDefault.voiceID` returns that string. Classic (`MascotPersona`) and Orb (`OrbPersona`) both use `PersonaVoicePreference.zeusDefault`. `PersonaVoiceResolver.resolve` always returns `.zeusDefault`. The stored persona key is `companion.persona`. The resolver does not read a voice flag; a leftover third-party voice flag does not change the id.

Nothing in `Speaker`, `KokoroWorker`, or `SystemVoiceRender` reads `zeus.synthetic`. The id is not sent to Kokoro, ElevenLabs, or `AVSpeechSynthesizer`. Text for a spoken reply still follows the chain above. The e2e bench on that commit (`qa/orb-e2e/BenchMain.swift`) reads the resolved id and checks that both personas return `zeus.synthetic`.

There is no headless app command that renders an arbitrary script as `zeus.synthetic`. `Zeus --voice-engine-selftest` speaks one fixed line through each available engine and writes a JSON receipt. That is not this script set. The Mac runbook leaves the provider unrendered and says so.

## Local Kokoro

`Speaker.speakKokoro` calls `KokoroVoice.render`, which is `KokoroWorkerSession.render`. The session writes one JSON line to a resident Python process: `text`, `voice`, `speed`, and an output path. `KokoroWorker.workerScript` constructs `Kokoro(onnx, voices)` and calls `create` with that voice and speed and with `lang="en-us"`. The finished WAV is scheduled on `UltronAudioChain`. Playback starts when the file is ready, so time to first audio includes the whole render. The default voice and speed are `am_michael` and `0.88`.

The weight URLs, fetched only after the person presses Set up, are the v1.0 files from `thewh1teagle/kokoro-onnx` releases: `kokoro-v1.0.onnx` and `voices-v1.0.bin`.

`qa/voice/render_kokoro.py` uses those same files and `kokoro-onnx` 0.6.1. It speaks a `bm_*` voice (default `bm_george`) at speed `0.88`. English scripts use `en-gb`. The French script uses `fr-fr`. The shipping worker's language remains `en-us`, and its default voice remains `am_michael`. The `[[BARGE-IN]]` marker is removed before synthesis. The timing JSON records the marker's character index and does not invent a stop time, because this render is not interrupted.

Kokoro-82M (hexgrad/kokoro) is Apache-2.0. The `kokoro-onnx` package that executes the ONNX export is MIT. `provenance.json` records the sha256 of the weight bytes that were hashed on this machine, the fetched Apache license file, and the package license. The weight files are not committed.

## AVSpeechSynthesizer fallback

`Speaker.speakSystem` builds an `AVSpeechUtterance` from the line. The voice is `UltronSystemVoicePick` for the detected language, else the voice chosen at `Speaker` init: premium and enhanced first, preferred deep male names, never Samantha and never a listed female or novelty voice. The rate is `AVSpeechUtteranceDefaultSpeechRate * 0.92`. The pitch multiplier is `0.82`.

`SystemVoiceRender.render` calls `AVSpeechSynthesizer.write` and forwards each PCM buffer to `UltronAudioChain`. If the output graph cannot start, or no buffer arrives within the watchdog, `Speaker` falls through to `synthesizer.speak`, still with that voice, rate, and pitch. The direct `speak` path does not enter the effect chain.

`qa/voice/mac/render_mac.sh` covers `say` and a small Swift `AVSpeechSynthesizer.write` script. Neither one runs the Ultron effect. Details are in `mac/RUNBOOK.md`.

## Metrics

| Field | Definition |
| --- | --- |
| `ttfa_s` | `first_audio_s - request_start_s` when the timing JSON has `first_audio_s`. Otherwise the first sample whose absolute amplitude is at least 0.01, mapped with `wav_origin_s`. |
| `inter_chunk_gaps_s` | Runs of silent 10 ms frames (RMS below 0.01) that sit between speech and last at least 0.10 s. Leading and trailing silence are not gaps. |
| `integrated_lufs` | pyloudnorm 0.1.1 integrated loudness, ITU-R BS.1770. Digital silence is negative infinity. |
| `true_peak` | Maximum absolute value after 4× `scipy.signal.resample_poly`. |
| `clipping_count` | Samples whose absolute value is at least 0.999. |
| `leading_onset_clip_count` | Clipped samples in the first 20 ms after speech onset. |
| `speech_rate_wps` | Whitespace words in `text` divided by the non-silent frame time. |
| `speech_rate_sps` | Vowel groups in `text` divided by that same time. `y` and French vowels count. A word with no vowel still counts as one. |
| `pitch_std_hz` | Standard deviation of autocorrelation F0 between 70 and 400 Hz. A low value is the robotic-prosody proxy. |
| `barge_in_stop_latency_s` | `playback_stopped_s - barge_in_requested_s`. Null unless both timestamps are present. |

The sine fixture is one second of a 200 Hz tone at amplitude 0.25, 48 kHz, phase π/2. pyloudnorm 0.1.1 reports its integrated loudness as -16.048946659687424 LUFS. The 4× resampled true peak of that finite buffer is 0.2832999554539534. The gap fixture is 0.10 s of silence, 0.30 s of tone, 0.20 s of silence, 0.30 s of tone. The clip fixture sets three samples to full scale.

## Scripts

| File | Case |
| --- | --- |
| `scripts/01-short-ack.txt` | Short acknowledgement |
| `scripts/02-long-answer.txt` | Long answer |
| `scripts/03-numbers-dates-currency-code.txt` | Numbers, a date, currency, and code |
| `scripts/04-question.txt` | A question |
| `scripts/05-error.txt` | An error message |
| `scripts/06-markdown-url.txt` | Markdown and URLs |
| `scripts/07-french.txt` | French |
| `scripts/08-barge-in.txt` | `[[BARGE-IN]]` interruption marker |

## Provider ledger

The character ledger in `providers/meter.py` is a local guard for renders on this machine. It is not tamper-proof. Anyone who can edit the JSON file, replace it, or point the path at another file can change the totals. The cap stops a test run from continuing. It is not a control on the provider's account.

## Render and report

```sh
qa/voice/render_kokoro.py --output /tmp/zeus-voice-kokoro
qa/voice/report.py /tmp/zeus-voice-kokoro --output /tmp/zeus-voice-kokoro
```

Weight files are cached under `~/.cache/zeus-voice-qa` unless `--cache` is set. On a Mac:

```sh
qa/voice/mac/render_mac.sh /tmp/zeus-voice-mac
qa/voice/report.py /tmp/zeus-voice-mac --output /tmp/zeus-voice-mac
```
