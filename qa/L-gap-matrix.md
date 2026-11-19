# L gap matrix

Behavior check of Zeus on `swarm/B1` (base `4b4bb8fe624395e109806afb67d520331d317ca0`) against present brief P0-P6. Reference only: `ref/present-reference/agent/AGENT_IMPLEMENTATION_BRIEF.md` and Atticus spec O8, O10. No code, prompts, or art were copied.

Lane B1 owns L0, L1, L2, L3. L4, L5, L7 stay listed so the gaps are visible. They are not this lane.

## What already exists

| Area | Where | What it does | Coordinate space |
|---|---|---|---|
| Menu bar, notch, settings, onboarding | `Sources/Zeus/App`, `Sources/Zeus/Notch`, `Sources/Zeus/TopBar` | App lifecycle and the panel. Permissions include Screen Recording (`PermissionsModel.swift` checks `CGPreflightScreenCaptureAccess`). | AppKit points |
| Screen capture | `Sources/Zeus/Screen/ScreenCapture.swift` | Every display, Zeus windows excluded, longest side 1280 px. Returns nothing without permission. | Capture pixels, top-left, y down. `globalPoint` (line 48) writes AppKit global points. |
| Screenshot model | `Sources/ZeusCore/Brain.swift` `ScreenShot` | Holds JPEG size plus `displayFrame` in AppKit points. No display id, no scale. | AppKit points |
| Point and highlight tags | `Sources/ZeusCore/ZeusTag.swift` `PointTarget` | Model output is screenshot pixels. `VoiceTurnController` (around line 404) maps them with `ScreenCapture.globalPoint` and calls `buddy.point`. | Pixels, then AppKit |
| Accessibility frames | `Sources/ZeusCore/Mac/AXSnapshot.swift` line 40 | Element frames are Quartz points, top-left of the main display, y down. | Quartz / AX |
| AppKit to Quartz flip | `Sources/ZeusCore/Overlay/CursorPresence.swift` `flipToQuartz` | One rect flip using the main display height. Assumes the main display starts at x = 0. | AppKit and Quartz |
| Display list | `Sources/ZeusCore/AgentHubRules.swift` `DisplayDescriptor` | Id, AppKit frame, notch, built-in. No scale. | AppKit points |
| Cursor-side presence | `CursorAnchor`, `SpringFollow` | Pill near the pointer. Exponential follow, rate 28. Offset (+18, -18). | AppKit points |
| Companion | `Sources/Zeus/Overlay/BuddyController.swift` | Click-through window per display. Follow offset (+28, -22). Exponential follow, rate 28. Quadratic Bezier flight, lift `min(0.2 * d, 80)`, smoothstep, scale 1 to 1.3 to 1. Duration `distance / 800` clamped to 0.6...1.4 s (750 ms at 600 pt). Never posts a real mouse move. | Model stores AppKit global. `BuddyOverlayView.local` flips to top-left of that display. |
| Show-me ink | `Sources/ZeusCore/Mac/Annotation.swift`, `Sources/Zeus/Mac/MarkOverlay.swift` | Strokes in AppKit global points. Canvas flips per display, same formula as the companion. Trail is a fading polyline, not a gesture model. Panel is excluded from capture (`sharingType = .none`). | AppKit, then per-display canvas |
| Speech | `VoiceTurnController.say` | Speaks the reply. Pointing starts when the tag arrives, not on a word clock. | n/a |
| Walkthrough | `Sources/Zeus/Mac/WalkthroughController.swift` | Flies the companion to a step target. Does not wait for the correct click. | AppKit via `globalPoint` |

The same y-flip is written out in three places: `ScreenCapture.globalPoint`, `CursorAnchor.flipToQuartz`, and the two overlay `local` functions. None of them take a window frame, a backing scale, or a negative display origin as a named input. `DisplayDescriptor` cannot tell 1080p from a 2x panel.

## Brief rows

| Row | Zeus today | Lane |
|---|---|---|
| P0 Baseline and one mapper | Capture, permissions, overlay, and TTS exist. There is no single mapper and no scale on a display. Tests do not touch TCC. | L0, this lane |
| P1 Physical pointer | No actuator. The companion does not move the system pointer. No stop-on-user-input button release, because no button is held. | L5, not this lane. Stays off. |
| P2 Companion follow and flight | Flight shape matches the brief (Bezier, lift, smoothstep, 750 ms at 600 pt, scale pulse). Follow is an exponential ease, not a spring with response 0.2 s and damping 0.6. Offset is (28, -22), not (35, 25) logical. No glow 8 to 14 to 8. No retained velocity. No rebase test for an unplugged display. Reduced motion collapses the flight. | L1, this lane |
| P2 + O8 Ring on the element | Arrival plays a short strike at the companion point. It is not snapped to an AX frame. It does not clear on the next click. Landing tolerance is not defined at 1080p or 4K. | L1, this lane |
| P3 Spatial trail | Show-me strokes and a drive trail exist. No activation threshold, dwell, Catmull-Rom, 8 pt stroke, one-second age fade, or raw-point retention after the ink fades. | L2, this lane |
| P4 Drawing and reveal | No shared drawing schema. No rect, circle, arrow, line, path, label, or math marks. No reveal mask, pen travel, or step list. | L2, this lane. O10 schema here. |
| P5 Speech timeline | Speech and the flight are not on one clock. No cancel of ink on user input or hotkey. No silent dictate-file timing hook. | L3, this lane. O10 timing here. |
| P6 Guided targets | `[POINT]` and walkthrough fly the companion. No ring distinct from the trail, no "wrong click does not advance", no voice next/back, no marks that follow the window. | L4, not this lane |
| L7 Always-on capture | Capture runs when a turn asks. It is not on every ask, not text-first, and not deleted as a named privacy step. | Not this lane |

## L0 decision

One mapper in ZeusCore, used by later lanes. Overlay points are the canvas space the companion and the ink already draw: origin at the top-left of one display, y down, in points.

Spaces:

| Space | Origin | Y |
|---|---|---|
| `screen` | Bottom-left of the main display, AppKit global. Displays left or below can be negative. | Up |
| `ax` | Top-left of the main display. Accessibility frames. | Down |
| `display` | Bottom-left of one display. | Up |
| `window` | Bottom-left of a window frame. | Up |
| `pixel` | Top-left of one display. Backing pixels when no capture is given (`points * scale`). Capture pixels when a capture size is given (the 1280-long-side shot). | Down |
| `overlay` | Top-left of one display. What the overlay canvas draws. | Down |

Scale is per display: 1 for 1080p, 2 for Retina. A ring lands within 24 px at 1080p and 48 px at 4K (scale 2, or a panel at least 3840 px wide). In points that is 24 pt on 1x 1080p and on 2x Retina, and 48 pt on a 4K panel running at scale 1.

The mapper does not move the pointer, draw, or read the screen. Callers pass display frames in. That keeps it testable with no window server.
