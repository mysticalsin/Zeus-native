# Feature Specification: Notch parity

**Feature Branch**: `004-notch-parity`

**Created**: 2026-11-19

**Status**: Draft

**Input**: Tony, 2026-11-19 13:13 through 13:17 BRT. Behaviour only. The reference product is not named. Its source is not used.

## How a task is done

A plan item is done only when a test named in `checklist.md` has been run and the result is written in that file's "verified on" field. A blank field means not done. This docs head fills none of those fields.

Evidence levels:

- **unit**: a pure ZeusCore test, no device and no network
- **integration**: an app test with a synthetic service, still no live network and no camera
- **native Mac**: `swift test` or the owned-window host on a Mac
- **live service**: a real Music, Spotify, lyrics, or camera run on Tony's Mac

No number in this spec is a measured result. Targets are budgets. False-accept and false-reject rates are unmeasured.

## Contract map

Homes are the files on main `d6d45dde`. "Parity branch `2c443191`" is the earlier branch that carried extra behaviour. Private paths on that branch are not reused. Commit `249d327e` is not cherry-picked and its message is not repeated.

| ID | Wanted behaviour | Home on main `d6d45dde` | Also on `2c443191` | Wave |
| --- | --- | --- | --- | --- |
| R-001 | Shuffle and repeat for Music and Spotify. Repeat-one hidden for Spotify. No script without Automation consent. 3 s timeout. | `Sources/ZeusCore/TopBar/MusicModes.swift` (Spotify modes are off/all only, lines 24–29 and 74–79). `Sources/Zeus/TopBar/MusicPlayerFeed.swift` refuses a script when Automation is off (about lines 98–102 and 139–140). `Sources/Zeus/TopBar/TopBarViews.swift` draws the controls (about lines 556–558). | Same rules, no new public timeout found | Wave 1. The 3 s script timeout is missing on main. |
| R-002 | Lyrics ladder: strict, then cleaned, then search. A distinct "service not answering" state. Backoff honours Retry-After. Never cache a failure as "no lyrics". | `Sources/ZeusCore/Lyrics/LyricsMatching.swift` steps `.exact`, `.cleaned`, `.search` (about lines 173–226). `LyricsFlow.swift` phase `.unavailable` is not cached; `.answered(.none)` is the cached miss (lines 13–18, 105–110). `LyricsBackoff` (lines 307–324) honours Retry-After and doubles to 15 minutes. | Same | Wave 1. Jitter on the wait is missing. |
| R-003 | Word-by-word highlight from estimated timing, a whole-line fallback setting, a macOS 14 fallback. | Setting `lyrics.wordByWord` in `Sources/Zeus/Settings/GlanceSettingsPages.swift` (about line 370). `Sources/ZeusCore/Lyrics/LyricWords.swift`. | `LyricWordTiming` on `2c443191` | Wave 1 gap: the macOS 14 fallback and the whole-line setting are not pinned as a pair. |
| R-004 | Keep the display awake only while music plays, inside the existing battery and heat rules. | `Sources/Zeus/TopBar/MusicAwakeHold.swift`, `KeepAwakeSession.swift`. | Same | Wave 1. Confirm the hold ends on pause. |
| R-005 | Open-on-click option. Collapse on pause: instant, delay, or never. | Open exists as `MusicCommand.open`. Collapse is not on main. | `PlaybackCollapse` on `2c443191` | Wave 1. Port the public collapse rule only. |
| R-006 | Rounded bottom corners per selected screen, click-through, above full screen. | `DisplaySelection` in `Sources/ZeusCore/AgentHubRules.swift` (lines 106–143). `NotchController` click-through (about lines 49 and 606). | Same | Wave 1, with the multi-display rule below. |
| R-007 | Live own-process CPU, memory, thermal, and audio rows, with copy. | No own-process live rows found on main. | Not a public-API addition found | Wave 1, public process info only. |
| R-008 | Output device list, transport icons, read-back. | Output device menu exists. Icons by transport are not on main. | `OutputDeviceIcon` on `2c443191` | Wave 1. Port the public icon map. |
| R-009 | Drawn notch on notchless displays, with size calibration. | `Sources/ZeusCore/TopBar/DrawnNotch.swift`, `Sources/Zeus/Notch/DrawnNotchModel.swift`, `GSDrawnNotchCard.swift`. | Same | Wave 1, one drawn notch per notchless display. |
| R-010 | Several media readers, one active, with pinning. | `NowPlayingArbiter`, `NowPlayingSource.swift`, `NowPlayingHub.swift`. | Same, plus a system reader that this spec does not take | Wave 1. Pinning stays. The system-wide reader stays out (R-014). |
| R-011 | Browser media through the existing extension: MediaSession play, pause, seek. | `Sources/ZeusCore/TopBar/BrowserMedia.swift`. | Same | Wave 1. Chromium only, through the extension Zeus already ships. |
| R-012 | Exact word times when the lyrics file has them. | `LyricLine` has no word stamps on main. | `LyricWordTiming.displayWords` on `2c443191` | Wave 1 as a pure parser of times already in the file. Any new dependency is proposed and not added. |
| R-013 | Per-app EQ and volume with public process taps. Exclude Zeus and call apps. Rebuild on device change. No orphan mute. A denial banner. | `Sources/ZeusCore/Audio/EqualiserPolicy.swift` `targets` already skips Zeus. | Same | Wave 1 only where the tap is the public API. No new entitlement. |
| R-014 | System-wide now playing through an undocumented gate. | Not on main. | `scripts/now-playing-media.c` links a private framework on `2c443191` | Held. Not in Wave 1 or Wave 2. |
| R-015, R-016 | AirPods battery and listening mode. | Not on main. | Earbud overlay on `2c443191` asks for Bluetooth and uses private keys | Wave 2. Own setting, off. Probe, hide when absent, unknown rather than 0, read back after every set. A Bluetooth usage string and prompt are allowed for this contract only. |
| R-017 | Focus name. | Not on main. | `FocusNameStore` on `2c443191` reads a store file and can ask for Full Disk Access | Wave 2. Public Focus Filter first. The store file only if Tony opts in, with a plain-label fallback. Off by default. |
| R-018 | Lock-screen music card. | Not on main. | `LockScreenPlayerSpace` on `2c443191` uses a private window-server space | Wave 2. Own setting, off. Load symbols fail-closed. A fresh window per lock. After unlock, check that clicks are not swallowed. A "read-only, no controls" option. |
| R-019 | AirPlay speaker names. | Not on main. | `ReceiverCatalog` on `2c443191` uses Bonjour and a Local Network usage string | Wave 2. Own setting, off. Local Network usage string allowed for this contract only. |
| R-020 | Phone drop. | Not on main. | Not found as a safe public path | Wave 2 stage 1: a QR code and a Safari upload page. Not plain HTTP on shared Wi-Fi without a one-time token and TLS, or a local-only scope. Stage 2, a companion app, is specified only and not built. |
| R-021 | Light appearance for Settings. | Settings pages are dark. | Not found | Wave 1. |
| R-022 | Signed one-click updater. | No updater dependency on main. | None | Wave 2. Sparkle 2 is the approved dependency for this contract only, with EdDSA signatures and rollback and downgrade guards. The feed URL and key generation stay placeholders. Never commit a private key. Do not publish. |
| R-023 | Face verification as the approval identity check, plus the fuller unlock Tony asked for at 13:16. | Presence exists: `Sources/Zeus/FacePresence/FaceVision.swift` calls `VNDetectFaceRectanglesRequest`, `VNDetectFaceLandmarksRequest`, `VNDetectFaceCaptureQualityRequest`, and `VNGenerateImageFeaturePrintRequest`. `Sources/ZeusCore/FacePresence/FaceVault.swift` stores vectors, not images. The camera usage string and `com.apple.security.device.camera` already exist. | Presence tests exist. No approval wiring. | Wave 2. Detail below. |
| R-024 | Setup inside the notch. | Onboarding is a separate window. | None | Held. |
| R-025 | Animated artwork. | Static art on the music wing. | None | Held. Leave it out. |

The music wing on main (`Sources/Zeus/TopBar/TopBarViews.swift`, closed-wing music layout) stays. This spec does not restyle it.

## Wave 1

Public APIs only. No new permission prompt. No new entitlement. Top bar visuals and animations stay. The only extra window is the explain overlay from slice 001, and this wave does not build that overlay.

### Multi-display

The top bar appears on every connected display, not only the main one.

- A display with a notch uses the real notch. A notchless display uses the drawn notch (R-009), calibrated per display.
- Per-display corner radius, click-through, and full-screen level follow R-006.
- Rebuild on connect, disconnect, resolution change, and arrangement change. `DisplaySelection.needsRebuild` is the rule. The default today is `NotchDisplayMode.builtIn` (one screen). Wave 1 shows every screen.
- One controller owns audio and actions. The other bars mirror. They do not each start playback, scripting, or capture.

### Settings

One place per feature. Plain labels. Sensible defaults. No jargon. Every held contract is a row that says "not available yet". It is not hidden and it is not a broken control.

### Shuffle, repeat, and lyrics

R-001 and R-002 as in the map. Add the 3 s script timeout and jitter on the lyrics wait. Do not cache `.unavailable` as `.none`.

## Wave 2

Each item has its own setting, off by default, and fails closed. Red tests come first. The private-API and new-permission allowance applies only to R-015, R-016, R-017, R-018, R-019, R-020, R-022, and R-023.

### R-023 Face verification for approvals

Camera face verification is the primary identity check for a Zeus approval, so Tony does not type a password for that approval. Touch ID or `LocalAuthentication` is the fallback. This is the check spec 003 (approval sync) calls before a card or a terminal choice counts as answered. Spec 003 still clears both places within 300 ms once the check succeeds.

**Capture.** `AVFoundation` for the camera. Vision for face rectangles and landmarks, which `FaceVision.analyze` already requests.

**Identity model.** The match needs an on-device face embedding. This repo contains no `.mlmodel`, `.mlpackage`, or other weight file. The only embedding Zeus computes today is Apple's image feature print from `VNGenerateImageFeaturePrintRequest` (`FaceVision.featurePrint`, revision `VNGenerateImageFeaturePrintRequest.currentRevision`). That call uses the operating system. It does not bundle weights, and Apple's SDK terms are what allow the call. It is not a face-verification model with a published false-accept rate.

A separate face-recognition weight file is not bundled. The plan that introduced presence rejected one such file because its terms were research-only and do not allow redistribution. No other model with a licence that allows redistribution has been identified. Until one is identified and the licence is checked, Zeus must not download or vendor weights. The match, if it ships before that, may use only the public Vision feature print already in the tree. A claimed false-accept rate for a bundled model is blocked.

**Enrolment.** Several poses. Store only an encrypted template in the Keychain with an access-control flag that requires biometric or user presence. Never store a raw image, a crop, or a thumbnail. Never send a frame, a landmark, or a template off the device. Never log them.

**Liveness.** A blink or a head turn is required. Reject a virtual camera. Reject a photo or a screen replay. The existing spoof cues (glare and a device-shaped rectangle) are deny-only. They cannot by themselves accept a face.

**Threshold.** The match score has a threshold chosen so a false accept is worse than a false reject. The number is not invented here. It is written down only after the metric task runs.

**Failures.** Low light, too far, a covered camera, camera permission denied, and timeout each have their own sentence. Each offers Touch ID or `LocalAuthentication`. After N failed attempts the check locks. N is set in the red test before the code, and the test fails if a further attempt can still approve.

**Kill switch and audit.** One switch stops the camera and refuses face approval. The audit log records time, result (allowed, refused, fallback, locked), and no biometric value, image, or template.

**Permission.** Camera only. No new entitlement. The camera entitlement already in the app is the one this uses. No Accessibility prompt is added for this check.

**Onboarding.** Say plainly that macOS has no Face ID and that an app cannot unlock the Mac login screen by itself. Offer Touch ID or Apple Watch for approvals. Offer optional camera presence (lock when away, wake when back) with the default off and a plain explanation of the camera permission. The 13:16 fuller unlock, if built, stores the login password only in the Keychain behind biometric or user-presence access control, never in the repo and never in a log. Onboarding states that risk in words. Presence without that password remains the default.

**Clean-room.** New face-approval code does not copy another product's files. The presence code already in the tree stays. New tests do not import another product's sources.

**Live check.** A native script, `qa/face-approval-live.md`, is the list Tony runs later with his own face. This spec does not record a result for that run.

### The other Wave 2 contracts

- **R-015, R-016.** Bluetooth usage string and prompt. Probe the battery keys and the listening-mode property at runtime. Hide a control the device does not have. Show unknown rather than 0. Read back after every set. Fail closed if the symbol is missing.
- **R-018.** Private window-server space. If the symbol does not load, the card is not shown. A new window for each lock. After unlock, a test proves clicks are not swallowed. The setting includes "read-only, no controls".
- **R-017.** Try the public Focus Filter. The Full Disk Access file is a second path behind its own opt-in, with a plain label. Off shows nothing and reads nothing.
- **R-019.** Bonjour names for AirPlay speakers. Local Network usage string. Off does not browse.
- **R-020.** Stage 1 is the QR page. Shared Wi-Fi requires a one-time token and TLS, or the listener is local-only. Stage 2 is this paragraph only.
- **R-022.** Sparkle 2 may be added later, EdDSA, with rollback and downgrade checks. Placeholders for the feed URL and the key. No private key in git. Nothing is published from this spec.

## Held

R-014, R-024, and R-025 stay held. Settings shows them as "not available yet". R-014 is not implemented with the private now-playing framework.

## Requirements

- **FR-001**: Wave 1 uses public APIs only and adds no permission prompt.
- **FR-002**: The top bar's existing visuals and animations stay. One controller acts. Other displays mirror.
- **FR-003**: Every display gets a bar. Notchless displays get the drawn notch.
- **FR-004**: Settings has one plain row per contract. Held rows say "not available yet".
- **FR-005**: Shuffle and repeat keep Spotify on off/all only, script only with consent, and time out at 3 s.
- **FR-006**: Lyrics stay on the strict, cleaned, then search ladder. A failure is `.unavailable`, never a cached `.none`. The wait honours Retry-After and adds jitter.
- **FR-007**: Wave 2 settings default off and fail closed.
- **FR-008**: Face approval uses the camera and Vision, stores only an encrypted template, and falls back to Touch ID or `LocalAuthentication`. No bundled weights of unknown licence.
- **FR-009**: False-accept and false-reject figures are reported only from a real run. This spec states none.
- **FR-010**: No private API outside the Wave 2 contracts listed above.

## Success criteria

- **SC-001**: The checklist's "verified on" column is filled from a command log. An empty cell is not a pass.
- **SC-002**: A three-display fixture shows three bars, one action path, and a drawn notch only on the notchless rows.
- **SC-003**: A Spotify repeat control never offers "one". A script is not built when consent is false. A script older than 3 s is abandoned.
- **SC-004**: A lyrics failure does not become a cached miss. The next wait is the server's Retry-After when one was sent, plus jitter, else the doubling delay.
- **SC-005**: Face approval locked after N failures cannot approve. The audit line for that lock contains no float vector and no image byte.

## Assumptions

- Main `d6d45dde` is the baseline. The parity branch SHA cited above is evidence of what existed there, not a commit to replay.
- Slice 001's explain overlay is the only new window this work may add, and Wave 1 does not add it.
- The 45 s and 20 s timeouts are unchanged.
