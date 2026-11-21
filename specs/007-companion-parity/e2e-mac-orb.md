# Orb end-to-end

One command, from a detached clone of this branch. It does not install Zeus and it does not start `/Applications/Zeus.app`. There is no `.xcodeproj` and no XCUITest target, so this does not use XCUITest. Playwright is not used.

Fakes only. Speaking audio is the injected bands bass 0.35 and mid 0.55. Every other orb state is silent. No microphone, no LLM, and no TTS provider is called.

```sh
git clone https://github.com/mysticalsin/Zeus-native.git "$HOME/zeus-orb-mac-clone"
cd "$HOME/zeus-orb-mac-clone"
git fetch origin zeus-bot/companion-persona-orb
git switch --detach origin/zeus-bot/companion-persona-orb
qa/orb-e2e/run.sh
```

Expected first stage: `Ran 5 tests` and `OK` from `qa/orb-e2e/test_runner.py`.

Expected last lines:

```
orb-e2e: pass
output: /tmp/zeus-e2e/orb/<sha8>
{"pass": 19, "fail": 0, "skip": 0, "infra": 0}
```

`$TMPDIR` is used when it is set. Override the directory with `ZEUS_E2E_OUT`.

The same script writes:

- `summary.json` — sha, pass/fail/skip/infra counts, per-test durations and attempt counts, frame p50/p95/dropped, CPU and memory
- `junit.xml`
- `png/idle.png`, `listening.png`, `thinking.png`, `speaking.png`, `compacting.png`, `error.png`, `reduce-motion.png`
- `bench.json` — the Swift fake bench
- `commands.txt` — the command lines below

On this Linux host the PNGs are plots of the Swift simulation. They are not a Metal render. `summary.json` says `png_source: simulation_plot`. A Mac with the built app can still run `build/Zeus.app/Contents/MacOS/Zeus --orb-proof <dir>` for Metal encodes. That command is not part of the default script, because Linux cannot build or launch the app.

## Commands

```sh
qa/orb-e2e/run.sh
python3 qa/orb-e2e/test_runner.py
swiftc -O -o "$ZEUS_E2E_OUT/orb-bench" Sources/ZeusCore/Companion/*.swift qa/orb-e2e/BenchMain.swift
"$ZEUS_E2E_OUT/orb-bench" "$ZEUS_E2E_OUT/bench.json"
```

`run.sh` runs the unit tests, then `qa/orb-e2e/runner.py`, which compiles the bench and runs every journey below. The Swift checks also live in the existing `ZeusCoreTests` target as `OrbE2EJourneyTests` (`swift test --filter OrbE2EJourneyTests` on a Mac). `Package.swift` is unchanged.

## Journeys

The product turn machine belongs to S1 (`CompanionTurnMachine.swift`, `CompanionTurnPhase.swift`). This suite does not create those files. `OrbTurnOracle` and `qa/orb-e2e/spec_oracle.py` are the spec table. The run fails if they disagree.

Legal rows, plus `sleep_or_display_change` from every phase to `interrupted` with effect `discard capture`:

| From | Event | To |
|---|---|---|
| idle | key_confirmed | listening |
| idle | key_tap_inside_confirm | idle |
| idle | mouse_down_while_arming | idle |
| listening | key_up | transcribing |
| listening | double_tap_latch | listening |
| listening | silence_timer_on_latch | transcribing |
| listening | escape | idle |
| listening | capture_denied_at_start | error |
| transcribing | partial_committed_instant | speaking |
| transcribing | partial_committed_needs_brain | thinking |
| transcribing | empty_partial | idle |
| transcribing | recognizer_failure | error |
| thinking | first_sentence_ready | speaking |
| thinking | brain_failure | error |
| thinking | key_down | interrupted |
| speaking | playback_ended | idle |
| speaking | key_down | interrupted |
| speaking | escape | interrupted |
| interrupted | cleanup_key_held | listening |
| interrupted | cleanup_key_up | idle |
| error | line_spoken | idle |
| error | key_down | listening |

That is 22 specific rows and 7 applications of the any-phase row, 29 legal applications. The other 111 phase/event pairs from those events are illegal and must be rejected. An unknown event is illegal too.

- **Persona.** Classic leaves the prompt byte-identical. Orb appends the addendum. Selecting Orb, reading the defaults again (the relaunch), then selecting Classic, persists both ways.
- **Hold to talk.** `idle → listening → transcribing → thinking → speaking → idle`. Orb visuals for those phases are idle, listening, thinking, speaking, idle.
- **Interrupt while speaking.** `key_down` goes to `interrupted` with effects `stop speech`, `stop flight`, `stop capture`. Key up returns to idle. Key still held returns to listening.
- **Error.** Capture denied at the start of listening goes to `error` and speaks the short line. The line being spoken returns to idle. `error` is not an orb.ts color, so the visual state stays idle. Every Jarvis spoken line is ten words or fewer.
- **Compacting.** Radius target 12, no lines, no electrons.
- **Reduce Motion.** Tumble, camera drift, and electrons stay frozen. Particle positions do not move. The opacity breathe is the only motion.
- **Multiple monitors.** One top bar per display and no extra window, for 1, 2, and 3 displays. `NotchController` still says one borderless window per display. The orb does not open a window.
- **Voice flag.** `companion.jarvisCloudVoice.enabled` defaults off. Orb and Classic both resolve to the existing Zeus voice.
- **LLM only.** The addendum is the system-prompt overlay. Face presence and `InstantTable` do not reference the persona, a URL session, or a model client. Instant time answers are chosen before `.brain`.

## Frames, CPU, attribution

Each state, including reduce-motion, is timed for 30 frames at a 60 Hz step and 30 frames at a 120 Hz quantum. p50 is the 15th sorted sample. p95 is the 29th. A frame whose wall time is over 1.5 periods is a drop (25 ms at 60 Hz, 12.5 ms at 120 Hz). Pass is zero drops at both rates. A 120 Hz quantum that does not cross a 60 Hz step is near 0 ms, so the 120 Hz p50 can be 0. The integrating frames are the p95.

Idle CPU must be under 1% of one core and resident memory under 150 MB. On a host that cannot launch `Zeus.app`, the script samples a quiescent `sleep` process and records `subject: sleep` in `summary.json`. That is the sampler and the threshold, not a claim that the Mac app was measured. When a Zeus pid is what you need, run the app from the clone and point the sample at that pid; do not use `/Applications`.

Attribution: `LICENSES/jarvis2.0-LICENSE` is the upstream text (1677 bytes). The same text is in `Resources/NOTICES.txt`, which About shows through Acknowledgements. `scripts/bundle.sh` copies both `NOTICES.txt` and `jarvis2.0-LICENSE` into `Contents/Resources`.

## Forge checks

1. **Verifier-owned properties.** `spec_oracle.py` owns the transition table, the 30-sample percentiles, the finite-particle check, and the rate-match check. It is not the Swift simulation.
2. **Skip/xfail gate.** A result of `skip` or `xfail` fails `forge.skip_xfail_gate`. The journey sources must not contain `XCTSkip`, `XCTExpectFailure`, or pytest skip/xfail marks.
3. **Spec boundaries.** The journeys above are the boundaries from the companion plan and the orb source: 29 legal transitions, 111 illegal pairs, ten-word lines, Classic by default, compacting targets, frozen Reduce Motion.
4. **Timeout.** A case that exceeds its timeout is run once more. A second timeout is `infra`, not a product failure. An assertion failure is not retried.

No other retries.

## Pass

`summary.json` has `"result": "pass"`, skip 0, infra 0, fail 0, seven PNGs, and `frame-budget` drops of 0 at 60 and 120. `junit.xml` has no `<failure>` and no `<error>`.
