# Performance budgets

These are pass thresholds for later slices. No number in this file was measured for this spec. A row is open until a run on Tony's Mac records the samples below and the threshold holds.

Integration head for the code the budgets sit on: `2722dcb7497d5415fbc1fcb1f65c49629966a281`.

Existing ceilings that a later slice must not loosen while the new thresholds are still open:

- Key-up to first audio, direct API brain and a cloud voice: 1.2 s (`Sources/ZeusCore/Voice/VoiceLatencyTrace.swift:75`).
- Key-up to first audio, CLI brains only: 2.5 s (`Sources/ZeusCore/Voice/VoiceLatencyTrace.swift:77`).
- Voice leg alone, the Settings test button: 600 ms (`Sources/ZeusCore/Voice/VoiceLatencyTrace.swift:84`).
- Idle CPU at or under 1% of one core, idle resident memory at or under 150 MB (`Sources/ZeusCore/Performance/PerformanceBudget.swift:5-6`).
- Instant commands at or under 150 ms (`Sources/ZeusCore/Intent/InstantTable.swift:16`).

The exceed thresholds below are tighter than those ceilings on the routes Tony will actually hold. A pass is the exceed threshold. Meeting only the old ceiling is a recorded miss.

## How a sample is taken

Every interval is an `os_signpost` interval (`OSSignposter` / `os_signpost`) with a static name and no transcript, answer, or key in the metadata. The same intervals are mirrored into the existing `[ZEUS] voice-latency` line (`Sources/ZeusCore/Voice/VoiceLatencyTrace.swift:54-68`) so `scripts/voice-latency.sh` can still print a percentile. XCTest records them with `XCTOSSignpostMetric` where the test host can run, and with `XCTClockMetric`, `XCTMemoryMetric`, and `XCTCPUMetric` for launch, memory, and CPU.

Percentiles use 30 kept turns after 5 discarded warm-up turns, unless a row says otherwise. p50 is the 15th kept sample in sorted order. p95 is the 29th. One machine, one power state, one display refresh, per session. A session that mixes 60 Hz and 120 Hz, or battery and power adapter, is not a result.

Linux cannot run these. A green portable test is not a pass.

## Budgets

| Budget | Start | End | p50 | p95 | Measurement | Pass |
|---|---|---|---|---|---|---|
| Hotkey to listening indicator | Right Option or the primary talk key key-down timestamp on the event | Companion phase published as `listening`, before any microphone call returns | 30 ms | 50 ms | Signpost `companion.hotkey-to-listening`. 30 presses, buddy policy "When I call him". | p95 under 50 ms. The microphone signpost `companion.mic-start` is a different interval and must not be inside this one. |
| Microphone actually open | Same key-down | First input buffer from the chosen device | 80 ms | 150 ms | Signpost `companion.mic-start`. | p95 under 150 ms. A miss here does not excuse a miss on the indicator. |
| End of speech to first audio, on device | Key-up (`key_up` = 0 in the latency line) | First audio buffer scheduled for playback | 700 ms | 1,100 ms | `XCTOSSignpostMetric` on `voice.first-audio`, route flag `on-device`. On-device recognizer, local voice, network denied. | Both percentiles. 30 kept turns. |
| End of speech to first audio, direct stream | Key-up | First audio buffer scheduled | 900 ms | 1,400 ms | Same signpost, route flag `direct-stream`. Streaming brain, streaming voice, capture overlapped with speech. | Both percentiles. The first audio sample's signpost must precede the model stream's end signpost on at least 27 of 30 turns. |
| End of speech to first audio, CLI only | Key-up | First audio buffer scheduled | 2,000 ms | 3,200 ms | Same signpost, route flag `cli`. | Both percentiles. The old 2.5 s figure is not the pass. |
| Screen capture | Key-down, capture task started | JPEG bytes for every attached display, or a typed failure | 120 ms | 180 ms per display | Signpost `companion.capture`. Two-display fixture and Tony's real displays as separate sessions. | p95 under 180 ms per display. A denied permission ends the signpost with `denied` and is not a timing pass. |
| Parsed point to flight | Point tag parsed on the main actor | Buddy mode `flying` | 20 ms | 50 ms | Signpost `companion.point-to-flight`. | p95 under 50 ms. |
| Key-up to pointer visible | Key-up on a turn whose fixture answer contains a point | Buddy mode `flying` or `pointing` on the tagged display | 1,600 ms | 2,400 ms | Signpost `companion.key-up-to-pointer`, direct-stream route, capture overlapped. | Both percentiles. |
| Animation during speech | First audio buffer | 10 s later, or turn end if sooner | n/a | 0 dropped frames | Display-link timestamps on the buddy's screen. A gap over 1.5 frame periods is one drop. 60 Hz frame is 16.7 ms. 120 Hz frame is 8.3 ms. | Zero drops on that display. Run once at 60 Hz and once at 120 Hz when Tony's desk has both. The link is paused again within 1 s of idle (`BuddyController` already sleeps a settled spark). |
| Reduce Motion during speech | Same window as the row above, Reduce Motion on | Same | n/a | 0 moving frames | The pose is the rest frame of the phase. Flight is a single position write. | No interpolated frames. VoiceOver announcement of the phase still posts. |
| Idle CPU | 10 s after the last turn, buddy hidden, models unloaded | 60 s later | n/a | 1% of one core | `ProcessEnergy.cpuPercent` (`Sources/ZeusCore/Performance/PerformanceBudget.swift:79-96`) twice, 60 s apart. `XCTCPUMetric` on the idle test. | Average at or under `PerformanceBudget.idleCPUPercent` (1%). |
| Idle memory | Same window | Same | n/a | 150 MB | `ProcessEnergy.sample().residentMB` (physical footprint). `XCTMemoryMetric`. | At or under `PerformanceBudget.idleMemoryMB` (150). One local model may be resident only after a turn, and it unloads after 5 idle minutes (`ModelResidency` in the same file). |
| Memory during a turn | Key-down | Turn end | n/a | 400 MB with no local model, 900 MB with one local model | Footprint sampled at `first_audio` and at `turn_end`. | The matching ceiling. Two local models resident at once is a fail (`ModelResidency` keeps one). |
| Energy, idle | Same 60 s idle window | Same | n/a | Low | `powermetrics --samplers tasks --show-process-energy` for the Zeus process, plus the Activity Monitor Energy column. | The column reads Low or Very Low. High or Very High fails the sitting even if CPU is under 1%. The CPU and memory numbers remain the numeric pass. |
| Cold launch | Process start, first line of `main` | Notch has reported ready and the hotkey monitor is installed | 800 ms | 1,200 ms | Signpost `companion.launch`. 10 cold launches. No model preloaded. Buddy policy left at the default. | Both percentiles. A launch that shows the listening face before the monitor is installed is a fail. |
| Instant command, no model | End of the instant transcript | Spoken or notch answer committed | 50 ms | 150 ms | Signpost `companion.instant`. Network denied. | p95 under `InstantTable.latencyBudgetMs` (150). |

## Measuring on Tony's Mac

One sitting, after the slice under test is built on that Mac. Do not install over the copy he uses. Do not sign or notarize. Keep a note of the commit SHA, the Mac model, the macOS version, the refresh rate of each display, and whether the power adapter is connected.

1. Quit every Zeus process. Confirm with the process list that no Zeus binary is running.
2. Start the built app from the terminal so `log stream` can see it. Predicate: `eventMessage CONTAINS "[ZEUS] voice-latency"`. Leave that stream running.
3. Leave the Mac idle 60 s with the buddy hidden. Record idle CPU, resident memory, and the Energy column. This is the idle row.
4. Quit and cold-launch 10 times. Record `companion.launch` for each. Do not speak.
5. Power adapter connected, Reduce Motion off, VoiceOver off. Hold Right Option 30 times and say the fixture sentence "What time is it". Discard the first 5. Record indicator latency and instant-command latency. The network can stay up for this block because the instant route must not use it. Confirm the brain process list stays empty.
6. Same pose. Hold Right Option 35 times and say "Point at the clock". Discard the first 5. This is the direct-stream block if a cloud key is present, otherwise the CLI block, and the route flag on the log line says which. Record key-up to first audio, capture, and key-up to pointer.
7. Repeat step 6 with the network denied (the Mac's Wi-Fi off, no ethernet) and no model key in the keychain of this build's container. The on-device row must pass. Face unlock is sitting B in `e2e-proof-plan.md`, not this block.
8. Repeat step 6 on battery, at 50% or lower. Record it as its own session. It does not replace the adapter session.
9. Turn Reduce Motion on. One 10 s spoken reply. Confirm a still pose and zero interpolated frames.
10. If a second display is attached, run the two-display capture and the screen-2 point once. Unplug it during an idle moment and confirm the buddy remains on the built-in display.
11. Set the built-in display to 60 Hz if the Mac allows it, run the 10 s speech frame count, then set it to the highest refresh the panel offers and run the count again.
12. Stop the log stream. Copy the latency lines and the signpost export into a new evidence directory. Do not commit that directory.

A session is a pass only when every threshold for the routes that were actually available is met, the evidence directory names the SHA, and the log lines contain no transcript and no answer text. A missing display, a missing cloud key, or VoiceOver left on makes that session void, not a pass.

AirPods and a real face are sitting C and sitting B. They are not part of the percentile math above. A voice route that only passes on the built-in microphone is not a pass for the AirPods sitting.
