# Human QA: driving the real Zeus like a person

`scripts/human-qa.sh` opens a packaged `Zeus.app`, then hovers the notch, presses buttons, moves sliders, types and
presses Esc through the macOS Accessibility API, the way a person would. After each action it waits for the visible
result and records how long that took. It is for you to run on your Mac. CI never runs it and the script refuses to.

## Run it

```sh
bash scripts/human-qa.sh /path/to/Zeus.app --screenshots
bash scripts/human-qa.sh /path/to/Zeus.app --only settings      # one journey
bash scripts/human-qa.sh /path/to/Zeus.app --allow-mic          # also presses Scribe Start/Stop (microphone)
```

Journeys: `launch topbar settings record scribe alerts talk`. A full run also quits Zeus, relaunches it, checks the
settings persisted and restores your original values. `--only` skips the quit and restart check and leaves Zeus
running; any setting that journey changed (the `topbar` one flips two) is not restored.

First time: System Settings > Privacy & Security > Accessibility > switch on your terminal app, then reopen it. The
script checks this without prompting. `--screenshots` also needs Screen Recording for the terminal, or it only
captures the wallpaper. If macOS blocks the app as unverified, `xattr -dr com.apple.quarantine /path/to/Zeus.app`.

## What it touches

- Needs: the app bundle outside the repository, Zeus not already running (it will not touch your running copy).
- It moves your mouse to the top of the screen, and types "what time is it" into Zeus Chat. Leave the Mac alone
  for the few minutes it runs.
- Zeus has no throwaway settings domain for a full GUI run (`--qa-startup` is a probe only), so the run uses your real
  settings. It asks `y/N` first (`--yes` skips the question). It saves your settings to `defaults-before.plist` in the
  evidence folder, then changes two things (Show Zeus in screen shares, top bar position) and restores both at the end.
- It never starts a recording: the Record countdown is cancelled with Esc, and if Esc fails the button cancels it, before
  it reaches 0. It never uses the microphone unless `--allow-mic`. It never requests a permission.
- Typing a question into Chat sends it to your connected AI provider (a few tokens).
- Reads only: crash reports `~/Library/Logs/DiagnosticReports/Zeus*` newer than the start, and the app's unified log.

## Evidence

`~/AI-Brain-build/zeus-human-qa/<timestamp>/` (private, mode 700):

| File | What |
|---|---|
| `report.md` | PASS / FAIL / MANUAL per step, latencies, waits over 2 s, log lines around failures |
| `receipt.json` | machine-readable verdict, counts, step list, SHA-256 of the files |
| `results-main.json`, `results-persist.json` | raw step records from the driver |
| `zeus-log.txt` | `log stream --predicate 'process == "Zeus"'` for the whole run |
| `freeze-*.sample.txt` | `sample <pid> 3` taken when a step waited over 2 s (a hang) |
| `driver-*.log`, `driver-info-*.json`, `state.json`, `defaults-before.plist` | driver trace, screens, restore data |
| crash reports | copies of any new `Zeus*.ips` |

Verdict: `pass`, `pass-with-manual` (MANUAL steps only need your eyes and ears) or `fail` (any FAIL, a step that never
ran, a new crash report, or a driver error). The exit code is 0 only for the two pass verdicts.

## Steps

| Journey | Steps | Notes |
|---|---|---|
| launch | 4 | window under 3 s, top bar opens on hover under 3 s, no crash |
| topbar | 7 | More menu, Settings opens, screen-share toggle both ways, menu agrees with Settings, position slider moves |
| settings | 27 | every sidebar page renders under 1 s (19 pages), About credit and version, Dictation sound picker and preview, Jev limit shows 10, language packs and speaker recognition cards |
| record | 6 | main display preselected, real display names, countdown, Esc cancel, no capture |
| scribe | 9 | opening animation, Up next or empty state, chips, Memory window panes and search; Start only with `--allow-mic` |
| alerts | 2 | page opens; test alert is MANUAL |
| talk | 2 | typed question and time to first answer text (10 s budget); voice is MANUAL |
| quit | 1 | quits within 8 s |
| persist | 5 | relaunch, both settings survived, restore, quit |

Controls missing from a build (for example the dictation sound picker or the speaker card on a branch that does not
have them yet) are reported FAIL "not found", not skipped. Latencies include the Accessibility lookup, so they run a
little high; the budgets are generous enough for that. Record steps are MANUAL when Screen Recording is not granted
to Zeus. Latest dictation, scribe and record work lives on sibling branches, so run this on the merged build.

Identifiers the driver prefers: `notch.more`, `notch.tab.*`, `settings.sidebar.<page>`,
`settings.appearance.topBarPosition`, `settings.appearance.topBarPositionReset`, `settings.engine.jevLimit`,
`record.capture`, `scribe.start`, `scribe.memory.open`, `chat.message`, `memory.search`. It falls back to labels.

## MANUAL checklist (automation cannot judge these)

- [ ] Ultron voice sounds right and starts fast after you finish speaking (first word near 1.5 s).
- [ ] Dictation release-to-text feels instant.
- [ ] Dictation Start/Stop sounds: Soft click, Glass, Pop, Airy and None each sound distinct; Airy is pleasant.
- [ ] Dictation cues with the default Crystal style: the rising chime plays the instant the dictation key goes down (hold, double-tap, press to toggle, top bar button), the falling chime the instant you release or press again (not after the words are pasted), and Escape or "No speech heard" plays one low blip. Repeat with the wake word listening and with a call app open but idle: the cues still play.
- [ ] Speaker names are right in a real call with 2 or 3 people (Zoom, Teams or Meet).
- [ ] Starting a Teams or Zoom call shows the meeting auto-start prompt ("Ask me").
- [ ] A real alert (calendar, agent approval) peeks out of the notch and clears.
- [ ] Scribe and Record look premium: spacing, motion, the countdown ring, the Memory window mascot.
- [ ] The notch does not hide the top bar on a notched Mac; try the position slider on your display.
- [ ] Record: start a short real recording, stop, and check the clip plays.
- [ ] Settings pages feel instant when you click quickly through them.
