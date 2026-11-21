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

The script does not launch Zeus when `--zeus` is omitted (exit 2) or when `--fixture` is set. `qa/speed/test_action_speed.py` uses synthetic fixtures only. A trace line that carries `transcript` or `prompt`, or any key besides the three above, is refused.

`--ask` does not play audio or paint, so a harness run records `keyRelease`, `requestSent`, `firstModelToken`, and `firstToolDecision` when the model streams them. `firstTtsAudio`, `firstOverlayPaint`, and `pointerArrival` come from a real talk-key turn with the same flag on.

## Static profile

Walk from key release to first audio. Savings are estimates from the code, not a Mac measurement. The 8 s, 20 s, and 45 s values are ceilings. They are not sleeps on the success path, and they were not changed.

| # | Wait | Where | Proposed fix | Estimated saving |
|---|---|---|---|---|
| 1 | Drawing paints only when a sentence's audio starts. `begin` stores marks and shows nothing. | `TalkVisualPresenter.swift:59` and `:75`. The turn calls `reveal` from `speaker.speak` `onStart` at `VoiceTurnController.swift:1060`. | Open the canvas and place anchors on the first sentence. Stream edges as later marks arrive, in step with speech, not after the whole reply. | Up to the rest of the speech. The reference drawing waits until 29.8 s, after 21 s of speech. On the order of 10 to 20 s on a long drawing. Not implemented. |
| 2 | "18% of 240" used to miss the local arithmetic path and take a model round trip. | Was `PersonaArithmetic.swift` (only "what is" plus times, plus, minus). Now `PersonaArithmetic.swift:23`, reached by `InstantTable.spokenAnswer` and then `PersonaQueries.localAnswer` inside `VoiceTurnController.understand`. | Landed. Percent and "N percent of M" answer locally, including a leading "what is". | About 2 to 4 s versus the reference 3.9 s audio. Target remains under 1 s to first audio. The spoken line still needs TTS. |
| 3 | Cold model. Nothing warms at launch. Key down warms the connection or the lean process. A one-shot CLI paid about 1.4 s before the first streamed text. | `KeyDownWarmer.swift:31`. `PersistentClaudeSession.swift:5`. | Keep the persistent process across turns, which is already the lean path when it is up. A short tap can still miss the warm-up. | About 0.4 to 1.4 s when the process is cold. Not changed here. |
| 4 | Cold TTS. `prewarm` runs on key down, not at launch. The 4 s value is a first-audio cap, not a sleep. | `Speaker.swift:155`. `VoiceTTSChain.firstAudioTimeout` at `VoiceTTSChain.swift:14`. Playback starts in `markAudioReady` at `Speaker.swift:269`. | Key-down prewarm already overlaps speech. `--ask` does not prewarm and does not speak. | About 0.3 to 1.0 s when the voice socket is cold. The 4 s cap was not raised or lowered. |
| 5 | TTS waits for a sentence, a comma clause of at least 3 words, or 12 complete words. | `SpeechText.swift:10` and `SentenceSplitter.firstChunkWords` at `:64`. | Speak the first short clause sooner when the reply has no punctuation yet. Streaming after that hand-off already exists. | About 0.2 to 0.8 s before the first buffer. Not changed here. |
| 6 | Key up waits `TalkLatencyBudget.sttFinalCapMs` (450) for a recognizer final, then cancels and returns the latest partial. | `SpeechInput.swift:713` and `:721`. Constant at `TalkLatencyBudget.swift:34`. | On key release, do not also wait out a silence timer. Returning the partial at once would remove this cap. | Up to 450 ms. Not changed. The merged clock locks 450 ms. A 400 ms setting was not in this tree and was not introduced. |
| 7 | Pointer flight is admitted by real playback and is never before first audio. | `PointingController.swift:726` and `revealed` at `:727`. `PointingSelfTestReceipt` requires flight at or after first audio. | Move the target box as soon as the intent and the target are parsed, before TTS is ready. Keep the receipt's sync check on the narration flight, or the receipt will fail. | About 0.3 to 1.5 s of TTS startup. The reference box is at 4.3 s and on target at 5.1 s, with audio at 4.1 s. Not implemented. |
| 8 | A filler line at 900 ms when nothing has streamed. | `FastTier.fillerMs` at `TurnRace.swift:8`, the tick at `:138`, the effect at `FastRaceRun.swift:87`. | Landed for act-first turns. `ActFirst.suppressesFiller` (`ActFirst.swift:6`) covers a leading "draw", "where do I click", "this window", and "point at" or "point to". A tool or pointer tag also closes `TurnFillerGate` (`TurnFillerGate.swift`). The check is `VoiceTurnController.swift:1129`. A plain question can still take one preamble. | About 1 s of speech that used to precede the action on pointer, window, and draw questions. The reference capital filler was 2 s and is not an action, so that question can still use one preamble. |
| 9 | After the recognizer returns, a selected dictation engine can transcribe the samples again before the route runs. | `VoiceTurnController.swift:474`. | Skip the second pass when the live transcript is already the final text. | About 0.2 to 1.5 s when that engine is on. Not changed here. |
| 10 | Speculative brain start waits 700 ms of stable text during the hold. Screenshots are awaited before a model route. | `AheadBrain.pauseMs` at `BrainRoute.swift:96`, sleep at `AheadRunner.swift:69`. Screenshot join at `VoiceTurnController.swift:568` (capture starts at press, around `:282`). Race ticks every 100 ms (`FastRaceRun.swift:105`). | On key release, start immediately from the partial if the speculative run has not started. Let the text request begin while shots are still finishing, and attach shots when they arrive for routes that need them. | About 0 to 0.7 s after release when the pause did not finish during the hold, plus up to about 0.1 s of tick delay, plus whatever screenshot time is still in flight. Not changed here. |

A card that has finished a pointing turn lingers 25 s (`ExplanationDesktopCard.beginLinger`, `ExplanationDesktopCard.swift:105`). That is not on the path to first audio. A new voice question now clears it (`VoiceTurnController.questionStarted` at `:211`, `ExplanationController.clearStaleCard`, `PointingController.clearStaleCard`). A late show from the previous generation cannot bring the card back (`AnswerCardClearance`).

## Quick wins

Landed, each as a red commit whose tests compile and fail on assertions, then a green commit:

1. Stale card clears when a new question starts.
2. No filler preamble when the turn's first action is a pointer, a window question, a draw, or a tool or pointer tag.
3. Local percent fast path, extending `PersonaArithmetic` rather than a second command table. `InstantTable.spokenAnswer` already calls it, and the voice turn calls that before the model. The open, quit, and playback commands on #240 (`zeus-bot/fast-local-commands`, VO-13) are a different path and are not merged here.

Not landed, because they are not small or they fight an existing receipt:

1. Progressive drawing. Spec row 1.
2. Pointer before TTS. Spec row 7. The pointing receipt says the marker flight starts at or after first audio.

## What this does not change

No new network endpoint. No new permission prompt. No `Package.swift`, SDK, or CI workflow edit. The macOS app target currently fails to compile on integration because `PlacedMark` is declared in both `Sources/ZeusCore/Pointing/MarkLayout.swift` and `Sources/ZeusCore/Present/DrawingScene.swift`. That duplicate is not fixed here.
