# UI/UX journeys

Executable contracts for these journeys live in `Tests/ZeusCoreTests/UIUXContractTests.swift`.
Linux runs the ZeusCore types: `NotchOpenRules`, `NotchOpenDelay`, `TopBarLayout`, `DictationBehavior`, `ScribeSessionMachine`, `MotionTokens`, and `MotionReduction`.
Hover dwell, shift peek, file swipe, Escape, Return, approval focus, settings focus, section phases, hub phases, the decision row, and the dynamic-type ramp stay Mac-only. Those production types are AppKit, and the phase machines were not extracted.
The Mac acceptance below is a person-level pass: screenshots and pixel samples from the running app.
It follows the same step record as `scripts/human-qa.sh` (action, visible result, evidence file).
This document does not run that pass. A Linux host cannot compile the app.

Pixel samples are points in the captured window, origin top-left, in points. A sample is the
colour at that point after the screenshot is taken, not a guess from a still that was not produced
by the step. Reduce Motion and Reduce Transparency are read from the spec values in the contract
tests. Those tests never write the system settings.

## Surfaces

| Surface | States the contract walks |
|---|---|
| Island and notch | idle, hover, peek, expanded |
| Pointer and clicks | press, hold, double click, triple click, right swipe |
| Keys | focus order, Escape, Return |
| Settings | the production sidebar order, including the twelve sections below |
| Keys | AgentPicker focus, Escape, Return |
| Decision | JevBudget.allows when the cap is unset, zero, or positive |
| Scribe and Murmure | ScribeSessionMachine and DictationBehavior |
| Hubs | SourceCapabilities and NowPlayingArbiter |

The twelve settings sections are General, Appearance, Notifications, Sounds, Voice, Dictation,
Shortcuts, Integrations, Permissions, Privacy, Diagnostics and License. The live sidebar also
carries Insomnia, Murmure, Polyglot, Engine, Features, Beamer, Tiling, Shelf and About. iPhone
stays hidden until pairing exists.

## Evidence names

Each step writes `shot-<id>.png` and, where a sample is named, `pixel-<id>.json` with `x`, `y`
and the sampled colour. The run folder matches `scripts/human-qa.sh`: a private directory, a
`report.md`, and a `receipt.json` whose SHA-256 covers the shots.

## J1. Island at rest

1. Launch the app. The menu bar shows the closed island and no expanded panel.
2. Screenshot `shot-j1-idle.png`.
3. Pixel `pixel-j1-island`: the island body is opaque black when Island background is Black.
4. Switch Island background to Transparent. Screenshot `shot-j1-transparent.png`. The body, outline
   and glow are gone. The mascot and wing text remain. The hardware notch stays black on its own.
5. The open panel is black in both settings. Do not treat a transparent closed island as a
   transparent panel.

## J2. Hover, dwell, leave

1. Set Open the notch on to Hover. Move the pointer onto the island and off again before the dwell.
   The panel stays closed. Screenshot `shot-j2-cancelled.png`.
2. Rest on the island for the selected dwell (Fast 0.10 s, Standard 0.25 s, Relaxed 0.60 s).
   The panel expands. Screenshot `shot-j2-open.png`.
3. Pixel `pixel-j2-panel`: centre of the expanded body is black.
4. Move the pointer off the panel. It returns to the island after the close delay, unless VoiceOver
   is running, the panel is pinned, a menu is open, the prompter is rolling, or the agent picker
   is open.
5. Repeat step 2 with Reduce Motion on. The panel changes place without a spring. The contract
   value is instant for every spring token, and the 0.12 s crossfade is the one fade that stays.

## J3. Click trigger

1. Set Open the notch on to Click. Hover the island past the relaxed dwell. It stays closed.
   Screenshot `shot-j3-hover.png`.
2. Press once on the island. The panel opens. Press again, then twice more. The panel stays open.
   Screenshot `shot-j3-clicks.png`.
3. Hold the pointer down on the closed island. A hold is not a click, so the panel stays closed.
4. While calibrating a drawn notch, a click does not open the panel.

## J4. Peek

1. With the panel closed, raise an approval. The island grows a peek card and does not become the
   full panel. Screenshot `shot-j4-peek.png`.
2. Pixel `pixel-j4-card`: the card fill is inside the peek, and a point 40 pt beside the card is
   not the card (the rest of the menu bar stays usable).
3. The current app does not peek when Shift is held alone, and it does not reveal a tab strip when Tab is held alone. Those two gestures are not part of this contract.

## J5. Right swipe

1. Swipe right across the island with no file on the drag pasteboard. The phase does not change.
2. Drag files onto the island. The panel opens on Shelf. Screenshot `shot-j5-shelf.png`.
3. The Shelf tab is the selected tab in the shot.

## J6. Expanded panel, focus, Escape, Return

1. Open the panel. Screenshot `shot-j6-tabs.png`. The tab order starts at Home and includes
   Murmure and Scribe.
2. Each tab's accessibility label is its help title, its trait includes button, and its identifier
   is `notch.tab.<id>`. More is `notch.more`.
3. Move focus forward from the first tab until it stops on More, then backward until it stops on
   Home. The order is the same on a second pass.
4. Escape while the agent picker is closed does not dismiss the panel and does not approve anything.
   Screenshot `shot-j6-escape.png` still shows the panel.
5. Open the picker with sessions. Return opens the highlighted session's terminal and closes the
   picker. With no sessions, Return only closes the picker. Escape closes the picker and leaves
   any approval undecided.

## J7. Approval row

1. Raise a normal approval. Screenshot `shot-j7-approval.png`.
2. Focus order is Deny, Approve, then Allow this whole chat when that action is offered.
3. Return does not approve. Activate Approve. The card leaves and the verdict is allow.
   Screenshot `shot-j7-allowed.png`.
4. Raise another card and activate Deny. The verdict is deny. A second activation does not
   change the verdict.
5. With details hidden on a card that has its own actions, only Deny remains.
6. A change preview shows the command block above the buttons. High risk is visible as its own chip.
7. Identifiers the contract requires: `approval.deny`, `approval.approve`, `approval.trust`.

## J8. Decision row

The app does not have a decision-row phase machine (empty, loading, ready, error, recovery). The executable contract is `JevBudget.allows`: an unset cap and a zero cap refuse the call, and a positive cap allows a small estimate. Screenshot names below are not produced by that contract.

1. The row's contract identifier is `hub.decision`. The Mac pass records whether that identifier
   is present. The current source gap is `ZB-UIUX-DECISION-001` in `qa/uiux/findings.json`.

## J9. The twelve settings sections

The settings pages do not share an empty, loading, error, and recovery phase machine. The executable contract is the sidebar order parsed from `GSSection` in `GlanceSettingsWindow.swift`, with iPhone hidden. Focus clamp and per-section content phases are not part of this contract.

The twelve ids, in the order the contract pins, are general, appearance, sounds, notifications, shortcuts, and insomnia, then the tools group, then license, permissions, privacy, diagnostics, and about. The twelve names below are the ones the contract requires to be present:

| Section | Identifier | Empty shot | Loading shot | Error shot | Recovery shot |
|---|---|---|---|---|---|
| General | `settings.sidebar.general` | `shot-set-general-empty.png` | `shot-set-general-loading.png` | `shot-set-general-error.png` | `shot-set-general-ready.png` |
| Appearance | `settings.sidebar.appearance` | `shot-set-appearance-empty.png` | `shot-set-appearance-loading.png` | `shot-set-appearance-error.png` | `shot-set-appearance-ready.png` |
| Notifications | `settings.sidebar.notifications` | `shot-set-notifications-empty.png` | `shot-set-notifications-loading.png` | `shot-set-notifications-error.png` | `shot-set-notifications-ready.png` |
| Sounds | `settings.sidebar.sounds` | `shot-set-sounds-empty.png` | `shot-set-sounds-loading.png` | `shot-set-sounds-error.png` | `shot-set-sounds-ready.png` |
| Voice | `settings.sidebar.voice` | `shot-set-voice-empty.png` | `shot-set-voice-loading.png` | `shot-set-voice-error.png` | `shot-set-voice-ready.png` |
| Dictation | `settings.sidebar.dictation` | `shot-set-dictation-empty.png` | `shot-set-dictation-loading.png` | `shot-set-dictation-error.png` | `shot-set-dictation-ready.png` |
| Shortcuts | `settings.sidebar.shortcuts` | `shot-set-shortcuts-empty.png` | `shot-set-shortcuts-loading.png` | `shot-set-shortcuts-error.png` | `shot-set-shortcuts-ready.png` |
| Integrations | `settings.sidebar.integrations` | `shot-set-integrations-empty.png` | `shot-set-integrations-loading.png` | `shot-set-integrations-error.png` | `shot-set-integrations-ready.png` |
| Permissions | `settings.sidebar.permissions` | `shot-set-permissions-empty.png` | `shot-set-permissions-loading.png` | `shot-set-permissions-error.png` | `shot-set-permissions-ready.png` |
| Privacy | `settings.sidebar.privacy` | `shot-set-privacy-empty.png` | `shot-set-privacy-loading.png` | `shot-set-privacy-error.png` | `shot-set-privacy-ready.png` |
| Diagnostics | `settings.sidebar.diagnostics` | `shot-set-diagnostics-empty.png` | `shot-set-diagnostics-loading.png` | `shot-set-diagnostics-error.png` | `shot-set-diagnostics-ready.png` |
| License | `settings.sidebar.license` | `shot-set-license-empty.png` | `shot-set-license-loading.png` | `shot-set-license-error.png` | `shot-set-license-ready.png` |

Pixel `pixel-set-selected`: the selected sidebar row is filled and the row above it is not.
Confirm the iPhone row is absent. Insomnia, Murmure, Polyglot, Engine, Features, Beamer, Tiling, Shelf, and About are in the pinned order. There is no per-section empty, loading, error, or recovery shot in this contract.

## J10. Scribe

1. Idle Scribe shows Start, enabled. Screenshot `shot-scribe-idle.png`. Identifier `scribe.start`.
2. Start with permission granted moves to recording. End meeting now is enabled (`scribe.endNow`).
3. Keep recording (`scribe.keep`) returns to recording from the ending countdown.
4. Let the countdown finish. The page shows writing, then the notes. Screenshot `shot-scribe-notes.png`.
5. Start with permission denied. The page shows the error, then recovery. Screenshot `shot-scribe-error.png`.
6. Memory uses `scribe.memory.open`.
7. With Reduce Motion, incoming words appear whole. The meeting card entrance is a crossfade with
   no drop and no scale. With Reduce Transparency, the card fill is opaque.

## J11. Murmure

1. Hold to speak: press enters holding, further clicks stay holding, release commits, then idle.
   Screenshot `shot-murmur-hold.png` during holding and `shot-murmur-idle.png` after commit.
2. Press to start and stop: the first press records, the second commits, and a click during commit
   does not start a new take. Screenshot `shot-murmur-recording.png`.
3. Permission denied shows the error and then recovery. Identifier `hub.murmur.press`.

## J12. Hubs

Now playing, agents, and Murmure do not share an empty, loading, error, and recovery desk. The executable contract is `SourceCapabilities.allows` and `NowPlayingArbiter`: a source with no capabilities ignores play and next, play is allowed once the source has play/pause, an empty arbiter shows nothing, and a command with nothing shown goes to Music unless a player is pinned.

1. Screenshot `shot-hub-empty.png` is the Mac pass for an empty now-playing hub. It is not an executable phase walk.
2. Identifiers the Mac pass looks for: `hub.nowPlaying.play`, `hub.agents.reply`.

## J13. Motion, glass, type

1. Every spring and duration in the panel, peek, press and window fades comes from
   `Sources/ZeusCore/TopBar/MotionTokens.swift`. A literal duration or spring in a view is a
   finding in `qa/uiux/findings.json`, not a pass. Each finding marked `expect: closed` fails
   its catalog case while that site is still open. #257, #258, #259, #260, #262, and #263 each
   flip their own cases. Findings marked `expect: open` are deferred.
2. Reduce Motion: springs and the press scale collapse to instant (press scale becomes 1). The
   crossfade stays 0.12 s. Screenshot `shot-motion-reduced.png` beside `shot-motion-full.png`.
3. Reduce Transparency: a blurred surface becomes opaque. Screenshot `shot-glass-opaque.png`.
4. Dynamic type: ZeusCore has no shared type-scale table on this head. Screenshot the settings sidebar at medium and at the
   largest size when a Mac pass is run: `shot-type-medium.png`, `shot-type-accessibility.png`. Those shots are not an executable scale contract.

## What this pass does not prove

Shots and pixel samples prove a Mac run of these steps. They do not prove microphone capture,
a decision provider, or a signed release. Permission failures in J10 and J11 use a denied test
double, not a click on the system prompt.
