# Action speed

Owner ask, 21 Nov 2026: go super deep, as fast if not faster, and better. The measure is action speed, not animation. This is reference-app parity. The other product is called the reference app in this repo.

Time zero is talk-key release. The harness path `Zeus --ask` has no key, so that path uses the moment `--ask` starts as time zero and labels it `keyRelease`. A Debug build is required. `--ask` is compiled out of release builds.

## Targets

Measured the same way as the reference baseline, from key release.

| Stage | Target |
|---|---|
| First audio | p50 at or under 2.0 s, p95 at or under 3.0 s |
| Pointer on target | at or under 3.0 s |
| First card or drawing element | at or under 4.0 s, streamed as it arrives |
| Filler | none when an action is possible. Act first. |
| Stale card | clears when the next question starts |

These ceilings are not edited by this work: the 8 s first-text budget (`FastTier.firstTextBudgetMs`), the 20 s cursor-agent limit (`Router.swift:155`), the 45 s deep budget (`FastRaceRun.swift:192`, `AnthropicAPIProvider.swift:80`), and the speech-to-text final cap below. No 1400 ms abort constant was found, and none was added.

## Reference baseline

Frame by frame, seconds from key release, on the owner's Mac.

| Prompt | Kind | Audio | Card or drawing | Pointer | Done | Note |
|---|---|---|---|---|---|---|
| What's the capital of Australia and its population? | capital | 2.4 | card 9.4 | | 14.8 | a 2 s "I'm checking" line stands in for the action |
| What is this window? | window | 2.8 | | | | |
| 18% of 240 | percent | 3.9 | | | | remote model for trivial math |
| Make it shorter | shorter | 4.9 | | | | follow-up |
| Draw how my router talks to my Mac | router | 5.9 | first drawing 29.8, drawing ends 68.9 | | | first drawing only after all 21 s of speech |
| Where do I click to change my wallpaper? | wallpaper | 4.1 | | box 4.3, on target 5.1 | | |

An earlier coarser pass, before the frame measurement, saw first audio at 3.6 to 4.9 s (7.6 s for a drawing), a pointer box at 4.6 s, a card near 8.5 s, a drawing at 8.7 s, the pointer answer done at 5.8 s, and short answers done at 9 to 14 s. The table above is the comparison baseline the harness prints.

Reference weaknesses this work is aimed at: a filler line before acting, a card that stays up across an unrelated next answer, and no observed multi-step click walkthrough. The walkthrough is not built here.

## Stages

One turn id (a UUID). Monotonic nanoseconds, not wall time. Offsets in the harness are milliseconds from `keyRelease`, integer division of the nanosecond gap, floored at zero.

| Stage | When it is marked |
|---|---|
| `keyRelease` | Talk key up (`VoiceTurnController.swift` release), a wake turn, or `--ask` start |
| `sttFinal` | Transcript accepted (`VoiceTurnController.complete`) |
| `requestSent` | Brain request handed to the race, the replay, or `--ask` |
| `firstModelToken` | First streamed model text |
| `firstToolDecision` | First point, highlight, action, or draw tag |
| `firstTtsAudio` | First TTS buffer played (`Speaker.markAudioReady`, `Speaker.swift:269`) |
| `firstOverlayPaint` | First answer card caption, or the first drawing reveal that paints |
| `pointerArrival` | Companion told to fly to the target (`BuddyController.point` and `flight`) |

The first mark of a stage on a turn wins. A negative gap cannot shrink `TalkLatencySample.firstAudioMs`: that sum clamps each span at zero (`TalkLatencyBudget.swift`). Capture-ready is not a stage of first audio.

`TalkLatencySample` is the merged clock from #341 (`zeus-bot/talk-latency-budget` at `e76eb6444e2a4c303a68a8170239a969f727a032`). This branch merged it with a normal merge, commit `348d9af418e738bb654ba559ec3baf0af2e6b068`. It was not rebased and not stacked. `firstAudioTargetMs` stays 1200. `sttFinalCapMs` stays 450. This work does not retune either constant. A 400 ms cap was not in the tree. It stays pending and was not applied on top of the merged 450 ms cap.

## Trace

`ActionSpeedTrace` in `Sources/ZeusCore/Voice/ActionSpeedTrace.swift`.

The flag `ZEUS_ACTION_SPEED_TRACE` must be exactly `1`. It is off by default. While it is off, marks are dropped and a file path is ignored, so a leftover path cannot write.

When the flag is on, events stay in memory (at most 4096) and, if a file is set, one JSON line is appended:

```json
{"turn":"AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE","stage":"keyRelease","monoNs":10}
```

The keys are only `turn`, `stage`, and `monoNs`. No transcript, prompt, answer, or other text. `ZEUS_ACTION_SPEED_TRACE_FILE` overrides the path. Otherwise the file is `~/Library/Application Support/Zeus/action-speed.jsonl`. The directory is mode 0700 and the file is mode 0600. A turn id that is not a UUID is dropped.

## Harness

```sh
ZEUS_ACTION_SPEED_TRACE=1 python3 qa/speed/action_speed.py --n 20 --zeus .build/debug/Zeus
```

Run that from the repository root on a Mac, with a Debug `Zeus` binary. `--n` defaults to 20 and is the repeat count for each of the six prompts. The script sets the flag and a private trace file on the child process, drives `Zeus --ask` once per repeat, and prints a p50/p95 table plus JSON. Nearest rank: for 20 samples, p50 is the 10th sorted value and p95 is the 19th.

Each stage row also carries the reference frame time in milliseconds, `delta_p50_ms` (Zeus p50 minus that reference), and `versus_reference`: `faster`, `slower`, `same`, `unmeasured`, or `no_baseline`. A stage with no Zeus sample is `unmeasured`. It is not treated as faster than the reference and it is not inside a target ceiling. Reference marks that are not Zeus stages (`filler`, `answerDone`, `pointerBox`, `drawingEnd`) are printed beside the table so they stay in the comparison.

## Score

`score.passed` is true only when every applicable budget row is `inside`. `unmeasured` fails the score. `over` fails the score. An empty trace fails the score. A missing live sample is not a pass.

| Budget | Ceiling | Applies to |
|---|---|---|
| First audio p50 | 2000 ms | every prompt |
| First audio p95 | 3000 ms | every prompt |
| Pointer p50 and p95 | 3000 ms | wallpaper (the baseline records `pointerArrival`) |
| First card or drawing, p50 and p95 | 4000 ms | capital and router (the baseline records `firstOverlayPaint`) |

A prompt that does not point is not required to record `pointerArrival`. A prompt that does not show a card or a drawing is not required to record `firstOverlayPaint`. 2000 ms, 3000 ms, and 4000 ms are inside. 2001 ms of first-audio p50, 3001 ms of pointer, and 4001 ms of first visual are over.

A `--zeus` run whose score fails exits 4. A missed prompt still exits 3. A missing binary exits 2. `--fixture` exits 0 and prints the score; that exit means the fixture was read. It does not mean the budgets passed. `TalkLatencyBudget.firstAudioTargetMs` stays 1200. `sttFinalCapMs` stays 450. This score does not retune either constant.

The reference app is not launched. `baseline_s` is the owner's frame table above. There is no reference-app binary in this harness.

The script does not launch Zeus when `--zeus` is omitted or the path is not a file (exit 2), or when `--fixture` is set. A `--zeus` run that loses a prompt (timeout, the process cannot start, a trace without `keyRelease`, or any count other than one turn) still prints the rows it has and exits 3. The miss record is the prompt kind and the reason. It does not store the prompt. `qa/speed/test_action_speed.py` uses synthetic fixtures only. A trace line that carries `transcript` or `prompt`, or any key besides the three above, is refused.

`--ask` does not play audio or paint, so a harness run records `keyRelease`, `requestSent`, `firstModelToken`, and `firstToolDecision` when the model streams them. `firstTtsAudio`, `firstOverlayPaint`, and `pointerArrival` come from a real talk-key turn with the same flag on. Those empty stages stay `unmeasured` on the `--ask` path.

## Static profile

Walk from key release to first audio. Savings are estimates from the code, not a Mac measurement. The 8 s, 20 s, and 45 s values are ceilings. They are not sleeps on the success path, and they were not changed.

| # | Wait | Where | Proposed fix | Estimated saving |
|---|---|---|---|---|
| 1 | Drawing used to paint only when a sentence's audio started. `begin` stored marks and showed nothing. | `TalkVisualPresenter.begin` calls `DrawingPaintLead.sentenceDueOnArrival` and reveals that sentence before returning. Later sentences still wait for `reveal`, which the turn calls from `speaker.speak` `onStart`. | Landed. The earliest sentence paints when the draw tag arrives. Later sentences still stream with their audio, not after the whole reply. | Up to the rest of the speech on a long first sentence. The reference drawing waits until 29.8 s, after 21 s of speech. This is not a Mac measurement. |
| 2 | "18% of 240" used to miss the local arithmetic path and take a model round trip. | Was `PersonaArithmetic.swift` (only "what is" plus times, plus, minus). Now `PersonaArithmetic.swift:23`, reached by `InstantTable.spokenAnswer` and then `PersonaQueries.localAnswer` inside `VoiceTurnController.understand`. | Landed. Percent and "N percent of M" answer locally, including a leading "what is". | About 2 to 4 s versus the reference 3.9 s audio. Target remains under 1 s to first audio. The spoken line still needs TTS. |
| 3 | Cold model. Nothing warms at launch. Key down warms the connection or the lean process. A one-shot CLI paid about 1.4 s before the first streamed text. | `KeyDownWarmer.swift:31`. `PersistentClaudeSession.swift:5`. | Keep the persistent process across turns, which is already the lean path when it is up. A short tap can still miss the warm-up. | About 0.4 to 1.4 s when the process is cold. Not changed here. |
| 4 | Cold TTS. `prewarm` runs on key down, not at launch. The 4 s value is a first-audio cap, not a sleep. | `Speaker.swift:155`. `VoiceTTSChain.firstAudioTimeout` at `VoiceTTSChain.swift:14`. Playback starts in `markAudioReady` at `Speaker.swift:269`. | Key-down prewarm already overlaps speech. `--ask` does not prewarm and does not speak. | About 0.3 to 1.0 s when the voice socket is cold. The 4 s cap was not raised or lowered. |
| 5 | TTS waits for a sentence, a comma clause of at least 3 words, or 12 complete words. | `SpeechText.swift:10` and `SentenceSplitter.firstChunkWords` at `:64`. | Speak the first short clause sooner when the reply has no punctuation yet. Streaming after that hand-off already exists. | About 0.2 to 0.8 s before the first buffer. Not changed here. |
| 6 | Key up waits `TalkLatencyBudget.sttFinalCapMs` (450) for a recognizer final, then cancels and returns the latest partial. | `SpeechInput.swift:713` and `:721`. Constant at `TalkLatencyBudget.swift:34`. | On key release, do not also wait out a silence timer. Returning the partial at once would remove this cap. | Up to 450 ms. Not changed. The merged clock locks 450 ms. A 400 ms setting was not in this tree and was not introduced. |
| 7 | Pointer flight is admitted by real playback and is never before first audio. | `PointingController.revealed`. `PointingSelfTestReceipt` requires flight at or after first audio. `onReveal` is still the only caller. | Landed for the box only. `ExplanationController.paintTargetBox` paints capture-space rings from the resolved scene before `speech.render`. Playback samples that do not yet include those rings keep them. The narration flight still starts in `revealed` at playback admission. | About 0.3 to 1.5 s of TTS startup before the box. The reference box is at 4.3 s and on target at 5.1 s, with audio at 4.1 s. The flight clock did not move. This is not a Mac measurement. |
| 8 | A filler line at 900 ms when nothing has streamed. | `FastTier.fillerMs` at `TurnRace.swift:8`, the tick at `:138`, the effect at `FastRaceRun.swift:87`. | Landed for act-first turns. `ActFirst.suppressesFiller` (`ActFirst.swift:6`) covers a leading "draw", "where do I click", "this window", and "point at" or "point to". A tool or pointer tag also closes `TurnFillerGate` (`TurnFillerGate.swift`). The check is `VoiceTurnController.swift:1129`. A plain question can still take one preamble. | About 1 s of speech that used to precede the action on pointer, window, and draw questions. The reference capital filler was 2 s and is not an action, so that question can still use one preamble. |
| 9 | After the recognizer returns, a selected dictation engine can transcribe the samples again before the route runs. | `VoiceTurnController.swift:474`. | Skip the second pass when the live transcript is already the final text. | About 0.2 to 1.5 s when that engine is on. Not changed here. |
| 10 | Speculative brain start waits 700 ms of stable text during the hold. Screenshots are awaited before a model route. | `AheadBrain.pauseMs` at `BrainRoute.swift:96`, sleep at `AheadRunner.swift:69`. Screenshot join at `VoiceTurnController.swift:568` (capture starts at press, around `:282`). Race ticks every 100 ms (`FastRaceRun.swift:105`). | On key release, start immediately from the partial if the speculative run has not started. Let the text request begin while shots are still finishing, and attach shots when they arrive for routes that need them. | About 0 to 0.7 s after release when the pause did not finish during the hold, plus up to about 0.1 s of tick delay, plus whatever screenshot time is still in flight. Not changed here. |

A card that has finished a pointing turn lingers 25 s (`ExplanationDesktopCard.beginLinger`, `ExplanationDesktopCard.swift:105`). That is not on the path to first audio. A new voice question now clears it (`VoiceTurnController.questionStarted` at `:211`, `ExplanationController.clearStaleCard`, `PointingController.clearStaleCard`). A late show from the previous generation cannot bring the card back (`AnswerCardClearance`).

## Quick wins

Landed, each as a red commit whose tests compile and fail on assertions, then a green commit:

1. Stale card clears when a new question starts.
2. No filler preamble when the turn's first action is a pointer, a window question, a draw, or a tool or pointer tag.
3. Local percent fast path, extending `PersonaArithmetic` rather than a second command table. `InstantTable.spokenAnswer` already calls it, and the voice turn calls that before the model. The open, quit, and playback commands on #240 (`zeus-bot/fast-local-commands`, VO-13) are a different path and are not merged here.

Landed in the same draft, with the decision tested on Linux. The app files were not compiled here:

4. The earliest drawing sentence paints when the draw arrives (`DrawingPaintLead`). Later sentences still wait for audio.
5. The pointer box paints before speech (`PointerBoxLead`). The narration flight still starts at or after first audio, so the pointing receipt's sync check is unchanged.

Still not changed here: the 12-word first chunk, the locked 450 ms speech-to-text cap, the second transcription pass, and the speculative brain pause. Those sit on the locked clock, or in `VoiceTurnController` and `BrainRoute`.

## What this does not change

No new network endpoint. No new permission prompt. No `Package.swift`, SDK, or CI workflow edit. The macOS app target currently fails to compile on integration because `PlacedMark` is declared in both `Sources/ZeusCore/Pointing/MarkLayout.swift` and `Sources/ZeusCore/Present/DrawingScene.swift`. That duplicate is not fixed here.

Linux cannot build or run the macOS app. The synthetic harness tests do not prove a native measurement, and they do not prove the reference app. A Mac with a Debug `Zeus` binary is required before `--zeus` can time a turn. Audio, paint, and pointer stages still need a real talk-key turn with the trace flag on. `qa/feature-map.json` has no action-speed obligation; those native suites stay on the Mac.
