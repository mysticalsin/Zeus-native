# OpenWhispr integration into native Zeus

Source reviewed on 9 November 2026: [mysticalsin/openwhispr](https://github.com/mysticalsin/openwhispr),
commit `e2f96ef01579f88a187a4179b357119208b50ab7`. Its upstream is OpenWhispr/openwhispr.
The desktop source is MIT, copyright 2024 OpenWhispr Team. The full license and
adaptation attribution are in `NOTICES.md` and the packaged `Resources/NOTICES.txt`.
Separate model, binary, and font licenses still need checking before those assets ship.

## Implemented integration

Zeus now uses a native Swift adaptation of OpenWhispr's local Whisper dictionary-echo
recovery. The source behavior is in `src/utils/dictionaryEchoFilter.js` and
`src/helpers/audioManager.js` (`processWithLocalWhisper`). Whisper can sometimes
recite its vocabulary prompt instead of recognizing the recording. Zeus previously
returned that text directly.

`WhisperPromptRecovery` recognizes whole hint-list recitals or a hint word repeated at
least three times. It checks only the prompt actually sent to the model, including
Zeus's `Names:` prefix and prompt-length bound. A suspect answer triggers exactly one
decode of the same recorded samples with no vocabulary prompt. Faster-whisper also
disables its VAD on that retry, matching the upstream recovery technique for recordings
with long pauses. WhisperKit and whisper.cpp do not add a new VAD pass.

The recovery is wired into all three existing local Whisper engines: WhisperKit,
whisper.cpp and faster-whisper. It does not choose a new engine, upload audio, install
a runtime, download a model, or open a capture device. Errors propagate through the
existing native engine error path. Zeus's normal fallback remains Apple on-device.

Zeus deliberately preserves an unprompted answer even when it confirms the same
dictionary terms: they may be genuine dictated words. It also leaves one- and two-term
dictation alone and does not use a volume threshold that could discard quiet speech.
Cancellation is checked before decoding, after the first answer, and after recovery.

### Acknowledged cross-turn correction

The native dictation controller now recognizes a new turn beginning with **“no, I
meant …”** as an explicit replacement of the **entire previous dictation**. It does
not guess which earlier word should change. The preview title and completion/recovery
messages state that scope. Command recognition uses the raw transcript before any AI
rewrite; quoted or reported speech and corrections inside a longer utterance keep
their existing behavior. The replacement payload uses local vocabulary/polish only.

Zeus earns an in-memory insertion receipt only when the same editable, nonsecure AX
element and owning app acknowledge its exact inserted UTF-16 span, expected character
count, and collapsed caret. It reads only that Zeus-authored span with `AXStringForRange`,
never the surrounding field value. Auto-send, a replaced selection, unsupported AX
APIs and unacknowledged key delivery do not earn receipts. Cancellation, a changed field
observed at turn start, or a subsequent ordinary insertion clears the old receipt.
The subrole classifier distinguishes an explicit AX `noValue` from a failed lookup:
unreadable, unsupported, secure and unknown subroles all fail closed. This intentionally
limits automatic replacement to editors exposing the required standard attributes.

A correction rechecks the app, retained field identity, original span contents, count
and caret, then uses `AXSelectedTextRange`/`AXSelectedText` setters and verifies the
result. It never sends backspaces or replaces the whole field value. Without proof,
the original text stays untouched and Zeus copies the proposed replacement with an
instruction to select the entire prior dictation and paste. If a setter was attempted
but acknowledgment is missing, it reports uncertainty and keeps the proposal in
history without automatically copying, retrying, or duplicating it. Only a preview
handoff can reactivate the original app; an unprompted app/field switch fails closed.

AX has no transactional compare-and-set API: these checks minimize races but cannot
make another app's text storage atomic. Native automated adapter validation is still
required before claiming support for a specific editor. All verification in this wave
is automated; no manual clickthrough, accessibility field reads, capture, runtime/model
installation, or model/network transcription was performed by the agent.

## Source comparison and next work

| Area | OpenWhispr source | Zeus today | Concrete next step / acceptance gate |
|---|---|---|---|
| Capture and latency | `audioManager.js`, `pcmTap.js`: 16 kHz PCM retained from mic open, avoiding FFmpeg after Stop | Native Float PCM, resampling, Parakeet and WhisperKit; no Electron encode/IPC step | Keep native PCM; measure cold/warm stop-to-insert latency on Tony's Mac against the same consented corpus |
| Local Whisper lifecycle | `whisperServer.js`: resident loopback server, health checks, request generation, bounded restart | WhisperKit is kept warm; whisper.cpp/faster-whisper launch a process per decode | Package a pinned signed whisper-server binary, implement a native lifecycle owner with loopback-only binding, warm load, cancellation, crash recovery and idle release; prove it in a notarized bundle before switching defaults |
| Model distribution | `models/registryData.js`, `registryDownloadTrust.js`, `installedModels.js`: signed catalogs, pinned hashes, trusted publishers and remembered installed models | Static model choices, WhisperKit completion marker; ggml download readiness is only file existence | Add pinned model hashes and atomic verified installation; interruption must keep the last valid model and failed files must never report Ready |
| Local multilingual engines | `parakeetManager.js`, sherpa-onnx support for Parakeet/Orukeet/Cohere | FluidAudio Parakeet v3/Ultra and WhisperKit already native | Benchmark existing native coverage first; a new sherpa engine requires binary/model license, architecture support, provenance, language tests and packaging evidence |
| Vocabulary | `dictionaryEchoFilter.js`, `dictionaryPromptCap.js`, `dictionaryKeywords.js` | Native bounded hint prompt, replacements, learned vocabulary, cloud keyword validation | Local echo-recovery port is implemented. Before adding tail stripping or broad fuzzy replacement, prove no deletion of real short speech, names or snippets |
| Correction | Cleanup routing and transcript fencing in `config/prompts` / `audioManager.js` | Local within-turn correction plus whole-turn replacement of the last acknowledged Zeus insertion | Shared receipt/executor regressions cover identity, UTF-16 spans, text/count/caret drift, cancellation, setter failure and bounded acknowledgment; native automated editor-adapter acceptance remains required |
| Dictation motion | `components/dictation/PillWaveform.tsx`, `waveformMath.ts`: 11 bars, measured level every 80 ms, 4–22 px range, reset at start/freeze at stop, reduced-motion handling | Native recording/level views and transcript reveal | Port measured waveform history and state transitions through SwiftUI, then record start/listen/stop/process/result transitions on macOS and compare actual motion; source inspection is not parity evidence |
| Reliable delivery | `resources/macos-fast-paste.swift`, `helpers/clipboard.js`: pasteboard read acknowledgement before restoration, Chromium typing workaround | PID/focused-owner checks, per-key ownership, transient clipboard, delayed restore and exact AX readback for correction receipts | Existing clipboard restoration still uses its delay; automate slow-editor, app/field switching, secure-field rejection, cancellation and no-duplicate acceptance before advertising universal editor support |
| Cloud/self-hosted ASR | Provider routing and `examples/custom-asr-shim`: explicit endpoint/provider choice and dictionary-aware requests | OpenAI and ElevenLabs with explicit keys/settings | Add another provider only with an explicit UI choice and documented data route. No silent local-to-cloud fallback |

## Verification and limits

`WhisperPromptRecoveryTests` uses fake decoders and covers genuine short speech,
Unicode vocabulary, one retry only, prompt/VAD removal, unchanged unprompted confirmation,
empty retry, failure and cancellation. It opens no device and makes no network request.
Native engine files must compile in macOS CI; the real models must still run against
consented quiet/paused/multilingual samples and focused-app insertion before acceptance.
`TextInsertionReceiptTests` runs the actual shared replacement executor with synthetic
field storage; `DictationOwnershipIntegrationTests` also proves an unconfirmed result
passes through the actual finish flow without relabeling it copied or retrying it.
Reproduce the portable subset with `python3 qa/portable-core/prepare.py --group
dictation-insertion --output /tmp/zeus-insertion-check --run` (use a new output directory).

This integration is a real shared behavior port, not a replacement of Zeus with the
OpenWhispr application. No donor runtime was installed or launched. Full dictation motion,
packaged model availability, real transcription accuracy, signing and notarization remain
separate release gates. A successful synthetic test is not a live recording receipt.
