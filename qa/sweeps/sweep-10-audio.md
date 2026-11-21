# Sweep 10 — audio and voice pipeline

Lens: capture, playback, device changes, sample rate, barge-in, ducking, the recording indicator, first-word latency, fallback order, provider errors, voice ids, and the provider 700 ms budget.

This file is a reading of the integration branch and the open voice heads. It does not change those branches. No audio device was exercised on this VM, so every row is a static finding with a failing-test sketch. A Mac run is still required before any row is called proven on hardware.

Ledger read first: `zeus-bot/bug-ledger` `255e52aba94234e2b194fd81b2cf4b93e628cc93` (`specs/bugs/ledger.md`, PR #54). Rows already there are listed at the end and are not given a new id.

## Heads read

| Head | SHA | PR |
| --- | --- | --- |
| `codex/integration-20261111` | `2722dcb7497d5415fbc1fcb1f65c49629966a281` | integration |
| `zeus-bot/local-voice-contract` | `329bfc2045ed2e7802331ef052468bfdc436f779` | #30 |
| `zeus-bot/companion-turn-machine` | `ab0880462e65a89a55181e7500ebe1d3859d5f1a` | #51 |
| `zeus-bot/companion-persona-orb` | `665b9167303f9596d5222b77a663e36f780d60d7` | #52 |
| `zeus-bot/voice-providers` | `16c2d697dcd479f6cbe510ad65fda731b82194fa` | #53 |
| `zeus-bot/media-playback-control` | `563a462830199b557e5cdecc9761d17e674f4ef9` | #56 |
| `zeus-bot/murmur-mic-first` | `6a57313b5b53f8452b56e2059961b311475371f9` | #21 |
| `zeus-bot/voice-latency` | `05e70f1a4e1f` (stacked on the right-command branch) | #10 |

`AVAudioSession` does not appear in the integration tree. Capture and playback use `AVAudioEngine` and Core Audio. The defects below are engines that do not follow a device change, do not keep a single output graph, and do not apply the budgets and voice id the later heads name.

Scribe's detector asks before it records unless "Start automatically" is chosen and ready (`Sources/ZeusCore/Scribe/ScribeAutoStart.swift:953-957` on integration). A tap still starts a recording from the idle page (`Sources/Zeus/Scribe/ScribeIdleView.swift:285`). That path is not filed here.

## Findings

### S10-01

| | |
| --- | --- |
| Severity | P1 |
| Branch / SHA | `codex/integration-20261111` `2722dcb7497d5415fbc1fcb1f65c49629966a281` |
| File:line | `Sources/Zeus/App/VoiceTurnController.swift:259` and `:288`; spoken reply `:1029` and `:1152`; deep answer `:1263-1265`; short `say` `:1275-1280` |
| Owner | Voice turn. Playback commands that can start music into this gap are PR #56. |

`duckBegin` runs when listening starts. `duckEnd` runs when the key is released, before the answer is spoken. The reply at `:1029` and the deep answer at `:1263` call `speaker.speak` with no duck. `say` is the only speech path that holds the duck until `isSpeaking` is false.

Sketch: music is playing. Press the talk key, release, and let the reply start. `SystemAudioDucker.end` has already restored the output volume. The reply and the music play together at the pre-listen level. A test can record the duck calls around `runScriptedTurn` and expect `duckBegin` to still be held while `speaker.speak` runs.

### S10-02

| | |
| --- | --- |
| Severity | P1 |
| Branch / SHA | `codex/integration-20261111` `2722dcb7` |
| File:line | `Sources/Zeus/Voice/SystemAudioDucker.swift:8-26` and `:28-39` |
| Owner | Voice ducking. |

`begin` snapshots `SystemVolume.defaultOutput()` once and stores that device id. Nothing listens for a default-output change while the duck is held. `end` restores only `duckedDevice`.

Sketch: start a listen (S10-01's duck is active). Connect or disconnect a Bluetooth output so the default device id changes. The new default stays at its own volume, so music on it is full while Zeus speaks. The previous device stays at the ducked scalar until `end`. Expect `begin` to re-read the default output on a device-list change and to restore every device it touched.

### S10-03

| | |
| --- | --- |
| Severity | P1 |
| Branch / SHA | `codex/integration-20261111` `2722dcb7` |
| File:line | `Sources/Zeus/Voice/SystemAudioDucker.swift:19-20`; `Sources/Zeus/App/VoiceTurnController.swift:227` and `:259`; `:1275-1280` |
| Owner | Voice turn. |

`begin` returns immediately when `quiet != nil`. There is no depth. `say` starts a task that calls `duckEnd` when `isSpeaking` becomes false. A talk-key press during that `say` calls `speaker.stop()` (`:227`), which makes `isSpeaking` false, then `duckBegin` (`:259`), which no-ops because the duck is already held. The `say` task then calls `duckEnd` and restores the volume while the new listen is open.

Sketch: call `say("Approved.")`, then `press()` before the sleep loop finishes. Assert the output volume is still the ducked scalar after `press` returns. Today the later `duckEnd` wins.

### S10-04

| | |
| --- | --- |
| Severity | P1 |
| Branch / SHA | `codex/integration-20261111` `2722dcb7` |
| File:line | `Sources/Zeus/Voice/UltronAudioChain.swift:189-194` and `:206-225` |
| Owner | Voice playback graph. |

On `AVAudioEngineConfigurationChange` the chain stops the player and resets the pending count and the ledger. It leaves `wired == true`. `prepare` starts the engine again and does not reconnect. A headset sample-rate change (48 kHz built-in versus the headset rate) leaves the graph attached at the old output format. `isPlaying` goes false, so the sentence pump treats the line as finished and schedules the next one into a graph that was not rebuilt.

Sketch: schedule a buffer, post `AVAudioEngineConfigurationChange` for that engine, then schedule another buffer. Expect a reconnect at the new output format and the unfinished buffer to be retried. Today the first buffer is dropped and `wire()` is skipped.

### S10-05

| | |
| --- | --- |
| Severity | P1 |
| Branch / SHA | `codex/integration-20261111` `2722dcb7` |
| File:line | `Sources/Zeus/Scribe/ScribeLiveCapture.swift:337-363` and `:408-417`; system tap `:606-649` and `:620` |
| Owner | Scribe recording. |

The microphone path rebuilds on `AVAudioEngineConfigurationChange`. The system tap reads `kAudioTapPropertyFormat` once, pins a private aggregate to `defaultOutputUID()` at start, and never subscribes to the default output. `sampleRate` stays at the value captured then. A later format with `mSampleRate == 0` keeps the 48 kHz default (`:620`). The mic tap also installs with `outputFormat(forBus:)` read before `prepare` and `start`, and the block closes over that rate for duration (`:354-363`).

Sketch: start a recording, then change the default output to a headset and back. Microphone frames resume. System-audio frames stay on the old device and the old rate, so the resampler (`ScribeResampler`, built with `pipe.inputRate`) pitches that side. A zero-rate tap format is treated as 48 kHz. Expect the system tap to be torn down and built again on the new default, and the mic tap format to be read after the engine is running.

### S10-06

| | |
| --- | --- |
| Severity | P1 |
| Branch / SHA | `codex/integration-20261111` `2722dcb7` |
| File:line | `Sources/Zeus/Voice/WakeWordListener.swift:58-83`; `Sources/Zeus/Voice/WakeWordController.swift:100-109` |
| Owner | Wake word. |

`WakeWordListener` installs a tap and starts the engine. It does not observe `AVAudioEngineConfigurationChange`. `stop` removes the tap only when `engine.isRunning` (`:72-76`). After a headset change the engine is stopped by the system, the tap stays installed, and the controller still holds `listener`, so `evaluate` will not call `startListener` (`listener == nil` is required). Status stays "Listening".

Sketch: enable the wake word, post a configuration change (or switch the default input), and read `cliStatus` plus whether a new buffer arrives. Expect a removed tap and a new engine, or status "Paused". Today the status stays "Listening" and no new listener is started until the feature is toggled. The fixed 4096-frame tap (`:64-66`) is also about 85 ms at 48 kHz and about 256 ms at a 16 kHz headset, so the wake window moves with the device rate.

### S10-07

| | |
| --- | --- |
| Severity | P1 |
| Branch / SHA | `codex/integration-20261111` `2722dcb7` |
| File:line | `Sources/Zeus/App/VoiceTurnController.swift:224` and `:243-256`; `:452-453`; `Sources/Zeus/Voice/SpeechInput.swift:677-681` |
| Owner | Talk key / Murmur's shared `SpeechInput`. PR #21 changes focus and insert order; it does not guard this stop. |

`press` cancels `turnTask` and then opens a new capture. `finishTurn` always begins with `speech.stop` and does not check `Task.isCancelled` or the new session id. `SpeechInput.stop` sets `stopRequested` and releases whatever engine is current.

Sketch: `release()`, then `press()` before `speech.stop` resumes. `listening` is true and the buddy shows listen, and the cancelled turn's `stop` takes the new engine. A test can set `beforeStopAudioForTesting` to call `press` and then assert the session id returned by the new `start` is still running. Today that session is stopped.

### S10-08

| | |
| --- | --- |
| Severity | P1 |
| Branch / SHA | `zeus-bot/voice-providers` `16c2d697dcd479f6cbe510ad65fda731b82194fa` |
| File:line | `Sources/ZeusCore/Providers/ProviderTypes.swift:208-214`; `Sources/ZeusCore/Providers/VoiceProviderSession.swift:193` and `:346-368`; `Sources/ZeusCore/Providers/ProviderHTTP.swift:54-60` and `:102-104` |
| Owner | PR #53 |

`ProviderLatencyVerdict.firstAudioP50Ms` is 700. The session's abort threshold is `firstAudioBudgetMs`, initialised to `directStreamP95Ms` (1400). `PluginVoiceBridge` never calls `setFirstAudioBudget`. The comparison runs only after the first chunk has arrived. A provider that sends no bytes waits for `ProviderHTTPBudget.requestTimeout` (8 s). `SpeakOutcome` records `meetsVoiceLeg` (600) and `meetsDirectStreamP95` (1400) and does not record `meetsFirstAudioP50`.

Sketch: a transport that yields its first chunk at 701 ms. Expect `ProviderFailure.timedOut` and the local voice. Today 701 ms is under 1400 ms, so the cloud clip is kept. A second transport that yields nothing: expect abort at 700 ms. Today the call sits until the 8 s resource timeout. `setFirstAudioBudget(ms:)` is only used from `VoiceProviderE2EJourneyTests` with 5 ms.

### S10-09

| | |
| --- | --- |
| Severity | P1 |
| Branch / SHA | `zeus-bot/voice-providers` `16c2d697` |
| File:line | `Sources/ZeusCore/Providers/ElevenLabsTTSAdapter.swift:24-28`; `Sources/ZeusCore/Providers/GoogleCloudTTSAdapter.swift:28-32`; `Sources/ZeusCore/Providers/VoiceProviderSession.swift:344-368`; `Sources/Zeus/Voice/PluginVoiceBridge.swift:146-154` |
| Owner | PR #53. The 24 kHz frame contract is PR #30. |

The ElevenLabs request is `audio/mpeg` with no `output_format`. The integration speaker asks for `pcm_24000` (`Sources/Zeus/Voice/ElevenLabsVoice.swift:56` and `:128` on the same base). Google asks for MP3 and does not set `sampleRateHertz`. The session appends every chunk and returns only after the stream finishes. `PluginVoiceBridge.speak` then plays the whole blob. The duplex contract on #30 is 3200 floats at 24 kHz (`Sources/ZeusCore/Voice/DuplexVoiceBackend.swift:3-8` on `329bfc20`). This path never produces that frame.

Sketch: a stream of three MPEG chunks, first chunk at 100 ms, last chunk at 2 s. Expect `play` to be called when the first chunk is valid audio. Today `speak` returns one buffer after the last chunk, and `firstAudioMs` is the first-byte time, not the time the speaker scheduled a sample.

### S10-10

| | |
| --- | --- |
| Severity | P1 |
| Branch / SHA | `zeus-bot/voice-providers` `16c2d697` |
| File:line | `Sources/Zeus/Voice/Speaker.swift:210-225`; `Sources/ZeusCore/Providers/VoiceProviderSession.swift:71-83` |
| Owner | PR #53. The "only when chosen" rule is integration `Sources/ZeusCore/Voice/UltronEngineRouter.swift:87`. |

When a provider is selected and `speak` returns `.localFallback`, the chain is Kokoro and Chatterbox, then the Mac voice. `localReady` is true when either Kokoro or Chatterbox is ready, and the local step always attempts `.chatterbox` after `.kokoro`. Chatterbox is a reference-clip clone (`Sources/Zeus/Voice/ChatterboxVoice.swift:1-18` on integration). The reference path is `voice.chatterbox.referencePath` when that file exists. The router on integration says that engine is used only when the owner picks it. A provider timeout or a 401 reaches it anyway. The existing `routeDecisions()` order (ElevenLabs, OpenAI, Gemini, Kokoro, Mac voice) is skipped for that turn.

Sketch: select the provider, force `.timedOut`, with Kokoro missing and a reference clip present. Expect the Mac voice. Today `attempt(.chatterbox)` runs first.

### S10-11

| | |
| --- | --- |
| Severity | P1 |
| Branch / SHA | `zeus-bot/voice-providers` `16c2d697` |
| File:line | `Sources/ZeusCore/Providers/ProviderTypes.swift:121-142`; `Sources/ZeusCore/Providers/GoogleCloudTTSAdapter.swift:131-132` |
| Owner | PR #53 |

`fromHTTPStatus` maps 401 and 403 to `.unauthorized`, 429 to `.rateLimited`, and 5xx to `.server`. 402 falls through to `.invalidResponse` ("No audio"). A 401 body that means credits are used up is not read. A synthesize 400 (bad voice name, as the comment says) is also `.invalidResponse`. `wrap` maps "not connected" and DNS failures to `.invalidResponse` rather than `.offline`. The stream helper turns a missing status (`0`) into `fromHTTPStatus(500)`.

The integration mapper (`Sources/ZeusCore/Voice/ProviderFailureMessage.swift:15-22` and `UltronVoicePlan.pauseSeconds`) treats 402 as credits and pauses 15 minutes, and treats 429 as 60 seconds. The provider session does not use that mapper. `noteRuntime` runs only for `.unauthorized` and `.rateLimited` (`VoiceProviderSession.swift:406-408`), so a 402 stays "ready" and the next sentence tries the same account.

Sketch: synthesize responses 402, 401 with a credits status word, and a stream that completes with no status line. Expect credits, rejected key, and offline. Today all three are "No audio" or "server-500", and 402 does not leave the provider in error.

On the integration speaker, a non-200 from the OpenAI stream returns nil and is recorded as `.offline` (`Sources/Zeus/Voice/Speaker.swift:395` and `:228`). A 401 and a timeout share that reason.

### S10-12

| | |
| --- | --- |
| Severity | P1 |
| Branch / SHA | `zeus-bot/voice-providers` `16c2d697` and `zeus-bot/companion-persona-orb` `665b9167303f9596d5222b77a663e36f780d60d7` |
| File:line | `Sources/ZeusCore/Providers/VoiceProviderSession.swift:292-295`; `Sources/ZeusCore/Providers/ElevenLabsTTSAdapter.swift:50-53` and `:76-82`; `Sources/ZeusCore/Companion/Persona.swift:24-33` and `:63-70` on #52 |
| Owner | PR #53 for the speak path. PR #52 for the persona rule. |

#52 resolves every persona to `zeus.synthetic` and ignores a stored third-party voice flag. #53's provider sources do not reference `PersonaVoiceResolver` or `zeus.synthetic`. `saveKey` stores `voices.first` when nothing is chosen. The ElevenLabs list keeps every `voice_id` the account returns. `pathComponent` only rejects a slash and `..`. A cloned id is a legal path segment and is sent on the next `speak`.

Sketch: a voices payload whose first id is a cloned voice and whose later id is `zeus.synthetic`. After `saveKey`, expect the stored id to be `zeus.synthetic` or expect no automatic choice. Today the stored id is the first row, and `speak` sends it. The integration stock id (`Sources/Zeus/Voice/ElevenLabsVoice.swift:12-13`) is a separate saved-id fallback and is also not checked against `zeus.synthetic`.

### S10-13

| | |
| --- | --- |
| Severity | P1 |
| Branch / SHA | `zeus-bot/voice-providers` `16c2d697` |
| File:line | `Sources/Zeus/Voice/PluginVoiceBridge.swift:25-34` and `:60-64`; `Sources/Zeus/Settings/VoiceProvidersCard.swift:208-218`; `Sources/Zeus/Voice/Speaker.swift:182-189` |
| Owner | PR #53 |

`speakLocally` builds an `AVSpeechUtterance` with no voice and the default rate, on a synthesizer that `PluginAudioPlay` owns. The test-voice button calls it when the cloud clip does not play. `PluginAudioPlay.stop` stops the player and the WAV engines and does not call `stopSpeaking` on that synthesizer. `Speaker.stop` stops a different synthesizer (`Speaker.synthesizer`) and then `PluginAudioPlay.stop`. A barge-in or Stop Speaking leaves the test-voice utterance running. The utterance also bypasses the voice picker that the integration Mac path uses (`Speaker.bestVoice`).

Sketch: fail the provider, tap Test voice, then call `Speaker.stop`. Expect silence. Today the plugin synthesizer keeps speaking, and the voice is the system default.

### S10-14

| | |
| --- | --- |
| Severity | P1 |
| Branch / SHA | `zeus-bot/voice-providers` `16c2d697` |
| File:line | `Sources/Zeus/Voice/PluginVoiceBridge.swift:37-57` and `:83-92` |
| Owner | PR #53 |

Each WAV starts a new `AVAudioEngine`, connects the player to the main mixer at the file's processing format, and appends the engine. Completion is the file callback, which stops the engine and ends the playback token. There is no `AVAudioEngineConfigurationChange` observer and no route-change handler on the MP3 `AVAudioPlayer` (`:12-23`). If the device changes before the callback, `WavFinish.complete` does not run. `ProviderPlaybackGate` depth stays above zero. `ProviderSentencePump.canDequeue` then stays false (`Sources/ZeusCore/Providers/ProviderPlaybackGate.swift:59-60`), so the next sentence waits.

Sketch: `play` a WAV, post a configuration change, and do not invoke the file callback. Expect `isPlaying == false` and the temp file removed. Today depth stays 1. This is a different stuck path from ZB-027 (an older `end` token). The happy-path leak in ZB-023 is closed on this head by `WavFinish.complete`.

### S10-15

| | |
| --- | --- |
| Severity | P2 |
| Branch / SHA | `zeus-bot/companion-turn-machine` `ab0880462e65a89a55181e7500ebe1d3859d5f1a` |
| File:line | `Sources/ZeusCore/Companion/CompanionTurnMachine.swift:124-125` and `:232-237` |
| Owner | PR #51 |

From `.speaking`, `.bargeIn` and `.cancel` go to `.interrupted` with `stopSpeech`, `cancelFlight`, and `cancelLLM`. They do not include `startMic` or `startCapture`. Those two commands are only on `keyDown` from `.idle`, `.interrupted`, or `.error`. `VoiceTurnController` on integration does not send these events, so the machine is not what a live talk key runs.

Sketch: phase `.speaking`, event `.bargeIn`. Expect `stopSpeech` and `startMic` in one step, the way `.listening`'s barge-in includes `stopMic`. Today the mic stays closed until a later `keyDown`.

### S10-16

| | |
| --- | --- |
| Severity | P2 |
| Branch / SHA | `zeus-bot/local-voice-contract` `329bfc2045ed2e7802331ef052468bfdc436f779` |
| File:line | `Sources/ZeusCore/Voice/DuplexVoiceBackend.swift:3-23`; `Sources/ZeusCore/Voice/VoiceSessionState.swift:5-16` |
| Owner | PR #30. The live engines are on integration. |

The contract is one 24 kHz frame, 3200 samples, spoken one frame ahead of the user. `VoiceSessionEvent` is start, started, push, close, closed, and fail. There is no interrupt, no device change, and no sample-rate event. Integration has no `DuplexVoiceBackend` conformer and no `setVoiceProcessingEnabled` call, so a live barge-in has no echo cancellation on the input node. `FakeDuplexVoiceBackend` is the only implementation, and it is a canned frame list.

Sketch: search `Sources/Zeus` for a type that pushes `VoiceFrame` into an `AVAudioEngine` input tap. The search is empty. A device-rate buffer of 480 or 512 samples cannot be passed to `push` without a resampler that does not exist on this branch.

### S10-17

| | |
| --- | --- |
| Severity | P1 |
| Branch / SHA | `codex/integration-20261111` `2722dcb7` |
| File:line | `Sources/Zeus/Scribe/ScribeController.swift:160-177`; `Sources/ZeusCore/TopBar/RecordingMotion.swift:4-5` |
| Owner | Scribe recording indicator. |

`topBarFeedback` returns a snapshot for `.starting`, `.processing`, `.complete`, and `.failed`. For `.idle`, `.recording`, and `.ending` it returns nil. The closed-notch recording wing's producer list is Recordly plus a meeting fixture "until Meetings wiring is unblocked." While the microphone is open for a meeting, the top bar does not show the recording control. The in-page "Recording" label (`Sources/Zeus/Scribe/ScribePage.swift:638`) is visible only on that page.

Sketch: start Scribe, leave the page, and read `topBarFeedback()`. Expect a visible recording snapshot whose phase is the live session and whose stop action calls `requestEnd`. Today the value is nil for the whole time `isRecording` is true.

### S10-18

| | |
| --- | --- |
| Severity | P2 |
| Branch / SHA | `codex/integration-20261111` `2722dcb7` |
| File:line | `Sources/Zeus/Voice/Speaker.swift:389-401` and `:429-432`; `Sources/ZeusCore/Voice/UltronEngineRouter.swift:87-88`; `Sources/ZeusCore/Voice/VoiceTTSChain.swift:14` |
| Owner | Integration voice fallback. PR #53 replaces this chain only when a provider is selected (S10-10). |

Automatic order is ElevenLabs, OpenAI, Gemini, Kokoro, then the Mac voice. ElevenLabs has a timer that cancels the route at `firstAudioTimeout` (4 s). OpenAI checks that deadline only inside the byte loop, and only while no audio has arrived (`:400`). A connection that stays open and sends nothing does not hit the check. Gemini builds a request with `timeout: 20` and waits for the whole body (`:432`) before Kokoro can start. Neither path is the 700 ms provider budget.

Sketch: OpenAI accepts the request and writes no bytes. Expect the attempt to end at 4 s and Kokoro to start. Today the function stays in `for try await byte`. Gemini with a 10 s response: expect Kokoro to have started by 4 s. Today Gemini occupies the chain until the body arrives or 20 s elapses.

### S10-19

| | |
| --- | --- |
| Severity | P2 |
| Branch / SHA | `zeus-bot/media-playback-control` `563a462830199b557e5cdecc9761d17e674f4ef9` |
| File:line | `Sources/ZeusCore/TopBar/MediaCommandRouter.swift:286` and `:325` |
| Owner | PR #56 |

The router accepts `.play` from the paused and unknown states with no input for "Zeus is speaking" or "the output is ducked." A search of `MediaCommandRouter.swift` and `MediaCommandCoordinator.swift` on this head has no voice or duck symbol. Together with S10-01, Play during a reply starts the player at full volume.

Sketch: state `.paused`, Zeus `isSpeaking == true`, command `.play`. Expect `.rejected` or a duck held across the play. Today the transition to `.playing` is legal.

## Already in the ledger

These were read on `255e52ab` and are not new ids.

| Ledger | What this sweep saw | On the current head |
| --- | --- | --- |
| ZB-027 | `ProviderPlaybackGate.end` ignores a token that is not the latest generation. Overlapping `begin` calls leave `isPlaying` true. | Still present at `Sources/ZeusCore/Providers/ProviderPlaybackGate.swift:36-39` on #53 `16c2d697`. S10-14 is a different stuck path (the completion callback never runs). |
| ZB-016 | Provider clips were outside `isSpeaking` and the sentence pump. | #53 now consults the gate from `Speaker`. The gate bugs are ZB-027 and S10-14. |
| ZB-023 | A WAV engine and its temp file were never stopped. | `WavFinish.complete` stops the engine and deletes the file on the happy path (`PluginVoiceBridge.swift:83-92`). The device-change hole is S10-14. |
| ZB-007 | `send` followed redirects and could replay `xi-api-key` and `X-Goog-Api-Key`. | `ProviderHTTPRedirect.forwarded` returns nil for both `send` and `stream` (`ProviderHTTP.swift:155-166` on `16c2d697`). |
| ZB-026 | Home Play does not start a player that is not already running. | Still the integration behaviour #56 is replacing. S10-19 is the missing speech gate on that replacement. |
| ZB-033 | Music launch uses a wall clock and does not cancel its sleep. | Still on #56 `MediaCommandCoordinator.swift`. Not refiled. |
| ZB-017 | The dictation control does nothing during transcribe and rewrite. | The microphone is already released by `finish` before those phases. This sweep did not find a second mic-open bug there. PR #21 does not change `speech.cancel()`. |
| ZB-014 | The turn clock used the wall clock. | The ledger's later note matches this head: `CompanionTurnMachine` takes a clock, and the system clock is uptime. Not refiled. |
| ZB-010 | The equaliser imports Darwin and the portable gate runs it. | A gate classification issue. The import is the macOS filter. Not a voice-pipeline defect. |

## Counts

| | |
| --- | ---: |
| New findings | 19 |
| P1 | 14 |
| P2 | 5 |
| Ledger rows cited, not refiled | 9 |
| Heads read | 8 |

New ids: S10-01 through S10-19. No P0 in this lens beyond the music-start failure already filed as ZB-026.
