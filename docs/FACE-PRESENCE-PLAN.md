# Face presence: plan and design

Written 14 November 2026 against `codex/face-presence-20261114` (HEAD `078a673`). Planner output only: nothing here is
built. Same house rules as the notch plans: pure rules in ZeusCore with tests first, `docs/DESIGN-DIRECTION.md` for
anything visible, `docs/STATE-MACHINES.md` for the reducer shape, nothing accepted until the named tests run on macOS
and the behaviour is seen on a Mac. Line numbers were read on `078a673`.

Face presence watches, through the camera, whether an enrolled owner is at the Mac. When no enrolled owner has been
seen for the time the owner picked, Zeus locks the Mac through its existing lock call. It can also tell other Zeus
features whether the owner is present. It never unlocks anything.

## Owner decisions (hard limits, no exceptions)

- Zeus never stores, reads, asks for or types the macOS login password. Zeus never injects keystrokes or synthetic
  events, at the lock screen or anywhere, on this feature's path. Zeus never unlocks the Mac. Unlocking stays with the
  system: password, Touch ID, Apple Watch.
- Not ported or adapted: `SecureCredentialManager.swift`, `KeystrokeInjector.swift`, `SpaceKeyMonitor.swift`, the
  password and unlock parts of `FaceUnlockCoordinator.swift`, `NotchSkyLight.swift`, any lock screen window code,
  `ArcFace.mlpackage`, `ArcFaceEmbedder.swift` (its weights carry separate research-only terms), `KeychainManager.swift`.
- Identity uses Apple Vision only: a feature print of the aligned face crop, compared by distance.
- The camera opens only after the owner switches the feature on, never at launch. A settings import never switches it
  on. No image is ever stored or shown; only embeddings, sealed with AES-GCM under a key kept in the Keychain. The
  camera stops when the feature is off, the screen is locked, the session is switched away or the Mac sleeps. The
  capture visibility rule (`ZeusWindowSharing`) and the system camera indicator apply. Tests never open a camera.

## What the owner gets

One Settings card, "Face presence", on the Privacy page (`GlanceSettingsPages.swift:1124`, a new
`Sources/Zeus/Settings/GSFacePresenceCard.swift` placed after the "Music" card). Nothing else: no taglines, no helper
text, no preview, no notch cue, no menu bar item.

| Row | Control | Notes |
| --- | --- | --- |
| Face presence | Switch (`face.presence`, default off) | Off stops the camera at once |
| Status | Symbol and one word | Words and symbols below; the countdown uses tabular numerals |
| Faces | One row per enrolled face: name ("Face 1", "Face 2"), switch, delete button | A switched-off face is kept and never matched |
| Enroll | Button | Enabled only while the switch is on and the state is watching, present or away |
| Lock after absent for | Menu (`face.lockAfter`): 30 seconds, 1 minute, 2 minutes, 5 minutes, 10 minutes | Default 2 minutes |

| State | Word | SF Symbol |
| --- | --- | --- |
| off | Off | `person.crop.circle` |
| needsCameraConsent | Needs camera | `video.slash` |
| enrolling | Enrolling | `person.crop.circle.badge.plus` |
| watching | Watching | `eye` |
| present | Present | `person.crop.circle.badge.checkmark` |
| away | Away 1:42 | `person.crop.circle.badge.clock` |
| paused(.lockedByZeus) | Locked | `lock` |
| paused(other) | Paused | `pause.circle` |
| unavailable | Unavailable | `exclamationmark.triangle` |

Design: `GSToggleRow` and `GSRow` from `GlanceSettingsStyle.swift`, existing type roles, no new motion (the status word
changes in place; nothing animates under Reduce Motion). VoiceOver reads "Face presence status: Away, 1 minute 42
seconds left". Status is never color alone. Switching a face off or deleting it is immediate; delete asks nothing
extra (it is one face of several and enrolling again takes seconds).

## Where things are today

| Need | Today | Use |
| --- | --- | --- |
| Lock call | `ScreenLock.lock()` (`Sources/Zeus/Intent/FastActions.swift:474-494`), used by the voice "lock" intent (`:93-98`). It calls `SACLockScreenImmediate` when present, else posts Control-Command-Q with `CGEvent` | A new `ScreenLock.lockWithoutEvents() -> Bool` that only calls `SACLockScreenImmediate` and returns false when it is missing. Face presence calls only that |
| Camera consent | `PermissionsModel.requestCamera()` (`PermissionsModel.swift:188-192`) through `PermissionPrompts`; pane open at `:203-206` | Reused; no new TCC call site |
| Camera usage string | `Resources/Info.plist:31-32` names only the teleprompter | Rewritten (FP-8) |
| Camera entitlement | `com.apple.security.device.camera` in `Resources/Zeus.entitlements` | Present |
| Lock, unlock, sleep signals | `WakeWordController.start` (`WakeWordController.swift:58-72`) observes `com.apple.screenIsLocked`, `screenIsUnlocked`, session resign and become active, screens sleep and wake | Same set, plus `NSWorkspace.willSleepNotification` and `didWakeNotification` |
| Feature start | `AppDelegate.applicationDidFinishLaunching`, `if on(.wakeWord) { ... start(...) }` (`AppDelegate.swift:317`), services in `StartupService` (`StartupPolicy.swift:4-18`) | New `StartupService.facePresence`, denied in QA startups |
| Import guard | `SettingsStore.neverEnabledByImport` (`SettingsStore.swift:255-258`), generator `validate_table` opt-in tuple | `face.presence` added to both |
| Keychain | `KeychainStore` (`ZeusCore/Keychain/KeychainStore.swift:85`, `:101`, `:112`), `MemoryKeychain` for tests (`:121`). Lint: `SecItemCopyMatching` only in that module | The vault key goes through `KeychainStore` |
| Other camera owner | `PrompterRecorder.start` (`Prompter/PrompterRecorder.swift:38`) and `tearDown` (`:95`) | Face presence pauses while the teleprompter records |

## Source adapted

Glance, https://github.com/jonnyoo/glance, commit `b97f521397ec1197ba17768ba797cae1e628848d`, MIT License, Copyright
(c) 2026 Jonathan Zhou. The local copy at `~/AI-Brain-build/glance-src-dl/glance` is an untrusted download: read as
data, never built, no script run. Every adapted file starts with one line:
`// Adapted from Glance (MIT, Copyright (c) 2026 Jonathan Zhou): <glance file names>.`

| Glance file | Zeus file | Kept | Dropped |
| --- | --- | --- | --- |
| `Liveness/LandmarkGeometry.swift` | `ZeusCore/FacePresence/LandmarkMath.swift` (pure), Vision half in `Zeus/FacePresence/FaceVision.swift` | Closed-form similarity transform, centroid, eye center choice, median | Homography, IRLS fit, linear solver (only the flat-vs-3D cue used them) |
| `FaceDetector.swift` | `FaceVision.swift`; rect math in `ZeusCore/FacePresence/FaceSelection.swift` | Rectangles, chained quality and landmarks requests, bottom-left to top-left flip, padded crop | Nothing else |
| `FaceRecognitionPipeline.swift` (selection only) | `FaceSelection.swift` | Dominant face with a width floor and continuity | ArcFace path |
| `FaceAligner.swift` | `FaceVision.swift` | 5-point to template warp, 2-point fallback, padded crop fallback | Nothing |
| `Liveness/LivenessCues.swift`, `LivenessFeatures.swift`, `GlareCue.swift`, `GlareCueExtractor.swift`, `DeviceBezelDetector.swift` | `ZeusCore/FacePresence/SpoofCues.swift` (pure), extractors in `FaceVision.swift` | The two deny cues (gloss glare, device bezel), `CueReading` with confidence 0 as abstention, frame counting | Confirm cues (blink, depth and pose, flat vs 3D), heavy mode, `GeometryLiveness.swift`, `LivenessScoring.swift`, `LivenessAnalyzer.swift`: presence must never need the owner to move or blink |
| `FaceEmbedder.swift` (Vision feature print and vector math), `FaceLabController.swift` (identity idea, calibration) | `ZeusCore/FacePresence/FaceMatch.swift`; feature print call in `FaceVision.swift` | Feature print as `[Float]`, normalize, average, both-measures match (centroid and nearest sample), threshold from genuine samples | Cosine on ArcFace, debug UI, manual calibration |
| `FaceEnrollmentStore.swift`, `SecureFaceStore.swift` | `ZeusCore/FacePresence/FaceVault.swift` (pure seal and records), `Zeus/FacePresence/FaceVaultStore.swift` (file and key) | Identity with samples and `isEnabled`, decode tolerant of a missing flag, never overwrite an unreadable store, delete the file when empty | Session key shared with the password, Touch ID gate, pose names |
| `CameraManager.swift`, `CameraDeviceCatalog.swift` | `Zeus/FacePresence/FaceCamera.swift` | Session on its own queue, BGRA output, late frames dropped, downscale before Vision, built-in front camera first | Highest resolution format, preview layer, per-display camera choice, error prose |
| `LockMonitor.swift` | `FacePresenceController.swift` observers | The signal set, notifications treated as hints, the session dictionary read as the authority | Event counters for unlock timing |
| `SessionAutoLocker.swift` | `FacePresenceMachine` (pure) | Compare timestamps, never count ticks; evaluate again on wake | Idle limit on a password session |

`NOTICES.md` and `Resources/NOTICES.txt` get one entry each, "Glance: face presence", naming the source, the pinned
commit, the files above, what Zeus did not take (ArcFace model and embedder, password, keystroke and unlock code), and
the full MIT text. This is the only notice added.

## State machine

One pure reducer, `FacePresenceMachine` in `Sources/ZeusCore/FacePresence/FacePresenceMachine.swift`: a Sendable
value with `state`, `switchOn`, `lockAfter` and `mutating func handle(_ event: Event) -> [Effect]`. No clock inside:
time arrives in events as `uptime` (seconds of `ProcessInfo.systemUptime`, monotonic, so a wall clock change cannot
shorten a countdown). The controller holds one value, applies effects, and reconciles the camera with the derived
`wantsCamera`, so no path can forget to stop it.

States: `off`, `needsCameraConsent`, `enrolling(token)`, `watching(since)`, `present(lastSeen)`, `away(since)`,
`paused(Reason)` with reasons `launch`, `screenLocked`, `asleep`, `lockedByZeus`, `noFace`, `zeusCapture`, and
`unavailable(Reason)` with reasons `camera`, `lock`, `vault`.

Derived: `wantsCamera` is true only for `enrolling`, `watching`, `present`, `away`. `wantsTicks` (a 1 s timer) is true
only for `watching`, `present`, `away`. `presence` is `.present` for `present`, `.absent` for `away`, `.unknown`
otherwise; this is the only value other features may read.

Events: `launch(storedOn)`, `switchOn(camera, enabledFaces, canLock)`, `switchOff`, `consentAnswered(granted,
enabledFaces)`, `enroll`, `enrollmentEnded(token, saved, enabledFaces)`, `facesChanged(enabledFaces)`,
`setLockAfter(seconds)`, `cameraFailed`, `cameraReturned`, `observed(verdict, uptime)` with verdict `owner` or
`notOwner`, `tick(uptime)`, `screenLocked`, `screenUnlocked(uptime, sessionLocked)`, `willSleep`,
`didWake(uptime, sessionLocked)`, `zeusCapture(active, uptime)`, `lockFinished(ok)`.

Effects: `askCameraConsent`, `openCameraSettings`, `beginEnrollment(token)`, `cancelEnrollment(token)`, `lockNow`.

Constants (pure, named, tested): `absentGrace = 3` s, `stallLimit = 10` s, `lockAfter` choices 30, 60, 120, 300, 600 s,
unknown label falls back to 120.

| From | Event | To | Effects |
| --- | --- | --- | --- |
| any | `launch(storedOn: true)` | `paused(.launch)` | none (the camera never opens at launch) |
| any | `launch(storedOn: false)` | `off` | none |
| `off` | `switchOn`, `canLock` false | `unavailable(.lock)` | none |
| `off` | `switchOn`, camera not determined | `needsCameraConsent` | `askCameraConsent` |
| `off` | `switchOn`, camera denied or restricted | `needsCameraConsent` | `openCameraSettings` |
| `off` | `switchOn`, authorized, `enabledFaces == 0` | `enrolling(t)` | `beginEnrollment(t)` |
| `off` | `switchOn`, authorized, faces | `watching(now)` | none |
| `needsCameraConsent` | `consentAnswered(true, faces)` | as the two rows above | as above |
| `needsCameraConsent` | `consentAnswered(false)` | `needsCameraConsent` | none |
| any but `off` | `switchOff` | `off` | `cancelEnrollment` when enrolling |
| `watching`, `present`, `away` | `enroll` | `enrolling(t)` | `beginEnrollment(t)` |
| `enrolling(t)` | `enrollmentEnded(t, _, faces > 0)` | `watching(now)` | none |
| `enrolling(t)` | `enrollmentEnded(t, _, 0)` | `paused(.noFace)` | none |
| `enrolling(t)` | `enrollmentEnded(other token)` | unchanged | none (stale) |
| `watching`, `present`, `away` | `facesChanged(0)` | `paused(.noFace)` | none |
| `paused(.noFace)` | `facesChanged(n > 0)` | `watching(now)` | none |
| `watching(s)` | `observed(owner, u)` | `present(u)` | none |
| `watching(s)` | `observed(notOwner, u)` | `away(s)` | none |
| `watching(s)` | `tick(u)`, `u - s >= stallLimit`, no frame yet | `unavailable(.camera)` | none |
| `present(l)` | `observed(owner, u)` | `present(u)` | none |
| `present(l)` | `observed(notOwner, u)` or `tick(u)`, `u - l >= absentGrace` | `away(l)` | none |
| `present(l)` | `observed(notOwner, u)`, `u - l < absentGrace` | unchanged | none |
| `away(s)` | `observed(owner, u)` | `present(u)` | none |
| `away(s)` | `tick(u)` or `observed`, `u - s >= lockAfter` | `paused(.lockedByZeus)` | `lockNow` (once) |
| `paused(.lockedByZeus)` | `lockFinished(false)` | `unavailable(.lock)` | none (no retry) |
| on states, `paused`, `enrolling` | `screenLocked` | `paused(.screenLocked)`, or keeps `lockedByZeus` | `cancelEnrollment` when enrolling |
| on states, `paused`, `enrolling` | `willSleep` | `paused(.asleep)` | `cancelEnrollment` when enrolling |
| `paused(.launch / .screenLocked / .asleep / .lockedByZeus)` | `screenUnlocked(u, sessionLocked: false)` or `didWake(u, false)` | `watching(u)`, or `paused(.noFace)` with no face | none |
| any | `screenUnlocked` or `didWake` with `sessionLocked` true or unknown | unchanged | none |
| on states, `enrolling` | `zeusCapture(true)` | `paused(.zeusCapture)` | `cancelEnrollment` when enrolling |
| `paused(.zeusCapture)` | `zeusCapture(false, u)` | `watching(u)` | none |
| `watching`, `present`, `away`, `enrolling` | `cameraFailed` | `unavailable(.camera)` | `cancelEnrollment` when enrolling |
| `unavailable(.camera)` | `cameraReturned` or `screenUnlocked(u, false)` | `watching(u)` | none |
| `unavailable` | `switchOn` (after `switchOff`) | as from `off` | as from `off` |
| `off` | anything but `switchOn`, `launch`, `setLockAfter` | `off` | none |

`setLockAfter` changes only the stored value; a running countdown keeps its `since` and reads the new limit on the next
tick. An `observed` event in any state without `wantsCamera` is dropped (a frame that raced a stop). Countdown shown in
`away(s)` is `lockAfter - (now - s)`, clamped at zero.

## Per-frame verdict

`FacePresenceVerdict.decide` (pure, `FaceMatch.swift`) turns one analyzed frame into `owner` or `notOwner`:

- No face, or no face wider than the width floor: `notOwner`.
- The dominant face (continuity first, then largest) is embedded; it matches when its distance to an enabled face's
  centroid and to its nearest sample are both within that face's threshold, and the face's Vision revision equals the
  current one. A switched-off face, a face from another revision, an empty face: never a match.
- A spoof cue latched in the rolling window (device bezel or gloss glare counted in 3 of the last 6 analyzed frames,
  `SpoofCues.Window`) turns any match into `notOwner`. Deny cues only ever push toward absent.

Sampling (`PresenceSampler`, pure): at most one frame analyzed every 0.5 s, one analysis in flight, frames in between
dropped in the camera delegate before any conversion. Camera at 640 by 480, built-in front camera first.

Enrollment (`EnrollmentPlan`, pure): 10 accepted samples within 30 s; a sample needs one dominant face, a 5-point
alignment, capture quality at least 0.4, no spoof cue, and to differ from the previous accepted sample by a minimum
distance so ten copies of one frame do not count. The face's threshold is `max(floor, min(ceiling, p90 of the
pairwise sample distances times 1.5))`; `floor`, `ceiling` and the factor start at values the builder records in the
test and are tuned only by owner check 3. Fewer than 10 samples in 30 s saves nothing.

## Tickets, in order

Every ticket: tests first, shown failing on the base (the build fails on the missing names); then the code; the
adapted-file header line; its REG rows appended to `qa/regressions.json` with feature `F14`; a separate review.
Builders run `swift build --build-tests` and `swift test --filter <suites>` on a Mac. No test opens a camera, touches
TCC, the real Keychain or the network.

### FP-1. Event-free lock call, lint, notices, feature row
- Files: `Sources/Zeus/Intent/FastActions.swift` (add `ScreenLock.lockWithoutEvents()` and `canLockWithoutEvents`;
  `lock()` unchanged), `qa/closed-loop/tests/test_source_lint.py`, `NOTICES.md`, `Resources/NOTICES.txt`,
  `qa/feature-map.json` (new `F14` "Face presence locks when the owner is away": `F14.1` native, `F14.2`
  `missing-F14-device` with no cases).
- Tests first: `test_face_presence_never_posts_events_or_touches_passwords` (in `Sources/*/FacePresence/**` and the
  card: no `CGEvent`, `post(tap`, `IOHIDPost`, `AXUIElementPostKeyboardEvent`, `keystroke`, `password`,
  `kSecClassInternetPassword`, `LAContext`, `SACLockScreenImmediate`, `ScreenLock.lock()`, `URLSession`,
  `CGImageDestination`, `NSBitmapImageRep`, `pngData`, `ArcFace`); `test_face_presence_locks_only_through_the_event_free_call`;
  `test_face_presence_lint_detects_its_failure_shapes`.
- Adapts: nothing (Zeus code).

### FP-2. Landmark math and face selection
- Files: new `Sources/ZeusCore/FacePresence/LandmarkMath.swift`, `FaceSelection.swift`; tests
  `Tests/ZeusCoreTests/LandmarkMathTests.swift`, `FaceSelectionTests.swift`.
- Tests first: `similarityTransformMapsTheTemplateOntoItself`, `similarityTransformRecoversRotationScaleAndShift`,
  `degeneratePointsGiveNoTransform`, `eyeCenterPrefersThePupil`, `imageSpaceFlipMatchesVision`,
  `paddedCropStaysInsideTheImage`, `bystanderBelowTheWidthFloorIsIgnored`, `continuityBeatsALargerNewFace`.
- Adapts: `LandmarkGeometry.swift`, `FaceDetector.swift` (rect math), `FaceRecognitionPipeline.swift` (selection).

### FP-3. Spoof cues
- Files: new `Sources/ZeusCore/FacePresence/SpoofCues.swift`; `Tests/ZeusCoreTests/SpoofCuesTests.swift`.
- Tests first: `zeroConfidenceNeverCounts`, `glareNeedsConcentrationNotJustBrightness`, `smallCropLowersGlareConfidence`,
  `deviceOverlapCountsAtItsLevel`, `threeOfSixLatchesAndAgingOutClears`, `cuesNeverReportLiveness`.
- Adapts: `LivenessCues.swift` (deny half), `GlareCue.swift`, `LivenessFeatures.swift` (frame fields),
  `DeviceBezelDetector.swift` (overlap rule).

### FP-4. Face match, verdict, enrollment plan
- Files: new `Sources/ZeusCore/FacePresence/FaceMatch.swift`, `EnrollmentPlan.swift`, `PresenceSampler.swift`; tests
  `FaceMatchTests.swift`, `EnrollmentPlanTests.swift`, `PresenceSamplerTests.swift`.
- Tests first: `averageNormalizesEachSampleFirst`, `matchNeedsCentroidAndNearestSample`, `aSwitchedOffFaceNeverMatches`,
  `samplesFromAnotherRevisionNeverMatch`, `aSpoofCueTurnsAMatchIntoNotOwner`, `noFaceIsNotOwner`,
  `thresholdComesFromTheSamplesAndIsClamped`, `nineSamplesSaveNothing`, `duplicateFramesDoNotCount`,
  `lowQualityAndTwoPointSamplesAreRefused`, `oneAnalysisInFlightAndHalfSecondSpacing`.
- Adapts: `FaceEmbedder.swift` (vector math), `FaceRecognitionPipeline.swift` (score, best match),
  `FaceLabController.swift` (identity idea, threshold from genuine samples).

### FP-5. Face vault
- Files: new `Sources/ZeusCore/FacePresence/FaceVault.swift` (records, `seal(_:key:)`, `open(_:key:)` with CryptoKit
  `AES.GCM`), `Sources/Zeus/FacePresence/FaceVaultStore.swift` (file `~/Library/Application Support/Zeus/face-presence.enc`,
  mode 600; key: 32 random bytes, base64, `KeychainStore` account `face.presence.vaultKey`); tests
  `Tests/ZeusCoreTests/FaceVaultTests.swift`, `Tests/ZeusAppTests/FaceVaultStoreTests.swift` (temp directory,
  `MemoryKeychain`).
- Tests first: `sealOpenRoundTrip`, `sealedFileHoldsNoPlaintextEmbedding`, `aWrongKeyFailsToOpen`,
  `aMissingEnabledFlagDecodesAsEnabled`, `anUnreadableVaultIsNeverOverwritten`, `deletingTheLastFaceRemovesFileAndKey`,
  `aMissingKeyWithAFileIsUnreadableNotEmpty`, `recordsHoldNoImageField`.
- Adapts: `SecureFaceStore.swift`, `FaceEnrollmentStore.swift` (embeddings only).

### FP-6. Presence machine and status
- Files: new `Sources/ZeusCore/FacePresence/FacePresenceMachine.swift`, `FacePresenceStatus.swift` (word, symbol,
  accessibility text, countdown text); tests `FacePresenceMachineTests.swift`, `FacePresenceStatusTests.swift`.
- Tests first: every row of the table, by name, including `launchWithTheSwitchOnKeepsTheCameraOff`,
  `lockingTheScreenStopsTheCameraFromEveryOnState`, `sleepStopsTheCameraAndWakeWhileLockedKeepsItOff`,
  `switchingOffStopsTheCameraFromEveryState`, `awayLocksExactlyOnceWhenTheTimeRunsOut`,
  `aMissShorterThanTheGraceKeepsPresent`, `aFailedLockGoesUnavailableAndNeverRetries`,
  `lockingDuringEnrollmentSavesNothing`, `aCameraThatSendsNoFramesGoesUnavailable`, `aStaleEnrollmentEndIsIgnored`,
  `anUnknownSessionStateOnUnlockStartsNothing`, `wantsCameraIsTrueOnlyInFourStates`, `countdownTextUsesMinutesAndSeconds`.
- Adapts: `SessionAutoLocker.swift` (timestamps over ticks, wake), `LockMonitor.swift` (event semantics).

### FP-7. Camera and Vision adapters
- Files: new `Sources/Zeus/FacePresence/FaceCamera.swift` (a `FaceFrameSource` protocol; the AVFoundation type owns an
  `AVCaptureSession` on its own queue, its delegate is a nonisolated final class that hands only Sendable values
  across, frames dropped by `PresenceSampler` before conversion, `start`, `stop`, device lost and interruption
  reported), `FaceVision.swift` (detect, align, feature print with its revision, glare and bezel extraction; all
  synchronous and nonisolated, called from one detached task); tests `Tests/ZeusAppTests/FaceVisionTests.swift`.
- Tests first: `aBlankImageHasNoFace`, `alignedCropIs112Square` (synthetic landmarks), `glareExtractorFindsOneBlob`
  (generated image), `featurePrintRevisionIsRecorded`, `noImageLeavesTheAnalyzer` (the analyzer result type carries
  only numbers).
- Adapts: `CameraManager.swift`, `CameraDeviceCatalog.swift`, `FaceDetector.swift`, `FaceAligner.swift`,
  `LivenessFeatures.swift`, `GlareCueExtractor.swift`, `DeviceBezelDetector.swift`, `FaceEmbedder.swift` (feature print).

### FP-8. Controller and launch wiring
- Files: new `Sources/Zeus/FacePresence/FacePresenceController.swift` (main actor, `@Observable`, holds the machine,
  reconciles the camera with `wantsCamera`, a 1 s timer only while `wantsTicks`, observers as listed above, the
  authoritative lock read from `CGSessionCopyCurrentDictionary`, unknown treated as locked, `presence` published
  read-only, logs carry state names and counts only); `StartupPolicy.swift` (`facePresence` service, not in
  `qaAllowed`); `AppDelegate.swift` (one `if on(.facePresence)` line after the wake word); `PrompterRecorder.swift`
  (two calls: `zeusCapture(true)` before start, `false` in `tearDown`); `Resources/Info.plist` camera string: "ZEUS
  uses the camera while you read from the teleprompter, only when you press Record, and for Face presence, only after
  you turn it on, to lock your Mac when you step away. No image is saved."; tests
  `Tests/ZeusAppTests/FacePresenceControllerTests.swift` (fake frame source, fake locker, fake lock reader, fake clock).
- Tests first: `launchNeverStartsTheCamera`, `switchOnAsksForConsentThroughPermissions`,
  `anUnlockNoticeWhileTheSessionIsLockedStartsNothing`, `theLockerIsCalledOnceAndOnlyTheEventFreeCall`,
  `teleprompterRecordingPausesAndResumes`, `aFrameAfterStopIsDropped`, `presenceIsReadOnlyForOtherFeatures`.
- Adapts: `LockMonitor.swift`, `SessionAutoLocker.swift`.

### FP-9. Settings rows and card
- Files: `scripts/gen-settings-catalog.py` (rows below; `face.presence` added to the `validate_table` opt-in tuple),
  regenerated `SettingsCatalog.swift` and inventory, `SettingsStore.swift` (`face.presence` in `neverEnabledByImport`),
  new `Sources/Zeus/Settings/GSFacePresenceCard.swift`, one line in `PrivacyPage`; tests in
  `Tests/ZeusAppTests/SettingsCatalogTests.swift` and `Tests/ZeusAppTests/FacePresenceCardTests.swift`.
- Tests first: `faceSwitchIsNeverTurnedOnByImport`, `exportHoldsNoFaceData`, `unknownLockAfterFallsBackToTwoMinutes`,
  `enrollIsDisabledOutsideWatchingPresentAndAway`, `statusRowNamesTheCountdownForVoiceOver`; the existing
  `test_every_settings_card_and_page_is_placed_on_a_page` and `scripts/check-settings-catalog.sh` pass.
- Adapts: nothing (Zeus UI).

| Id | Section, group | Kind | Choices | Default | State |
| --- | --- | --- | --- | --- | --- |
| `face.presence` | privacy, Face presence | toggle | | false | live |
| `face.lockAfter` | privacy, Face presence | choice | 30 seconds, 1 minute, 2 minutes, 5 minutes, 10 minutes | 2 minutes | live |
| `face.status` | privacy, Face presence | status | | | custom |

## Privacy

- The camera runs only in `enrolling`, `watching`, `present`, `away`. Launch, an import, a restored state or another
  feature cannot reach those states; only the owner's switch, the owner's Enroll tap and an unlock after the owner
  switched it on can.
- macOS shows its camera indicator whenever Zeus holds the camera; nothing hides or shortens it. No Zeus window is
  added, so `ZeusWindowSharing` needs no change; if a face preview is ever proposed it is a new owner decision and
  uses `ZeusWindowSharing.apply(... .zeusStandard)`.
- Frames live in memory for one analysis and are released; no image, crop or thumbnail is written, logged, shown or
  sent. Embeddings stay sealed on disk, are never logged, exported with settings, put in diagnostics, sent to a model,
  voice, chat or agent context, or sent over the network (lint, FP-1).
- Meeting mode's camera detection (still a TODO in the catalog) must exclude Zeus's own camera use when it is built.
- Deleting a face removes its samples at once; deleting the last face removes the file and the Keychain key.

## Security

- What a spoof can do: a photo, a screen or a video of the owner can at most keep Zeus from auto-locking. It can never
  unlock the Mac, because this feature has no unlock path, holds no password and posts no events. The device bezel
  and gloss glare cues make the common spoofs count as absent, but they are not a proof of life.
- A wrong match (someone similar, or a weak feature print) has the same ceiling: the Mac stays unlocked while that
  person is at it. Glance's own notes say the Vision feature print separates people less well than a dedicated face
  model; that is why identity here only ever withholds a lock. A missed match locks the Mac while the owner is there;
  the owner unlocks the usual way. Face presence is a convenience, not a replacement for the system's own auto-lock.
- Lock and unlock notifications can be posted by any process of the same user. They are hints: a forged "locked"
  only pauses the camera; a forged "unlocked" starts nothing unless the session dictionary reports unlocked.
- The lock goes only through `SACLockScreenImmediate`. If it is missing the feature is `unavailable(.lock)`; it never
  falls back to posting Control-Command-Q.
- The vault key is 256 bits from `SymmetricKey`, kept through `KeychainStore`; the file is AES-GCM sealed and
  authenticated, so an edited file fails to open and is treated as unreadable, never as empty.

## Regression ids

| REG | Guard |
| --- | --- |
| REG-600 | `test_face_presence_never_posts_events_or_touches_passwords` |
| REG-601 | `test_face_presence_lint_detects_its_failure_shapes` |
| REG-602 | `test_face_presence_locks_only_through_the_event_free_call` |
| REG-603 | `FacePresenceMachineTests.launchWithTheSwitchOnKeepsTheCameraOff` |
| REG-604 | `SettingsCatalogTests.faceSwitchIsNeverTurnedOnByImport` |
| REG-605 | `FacePresenceMachineTests.lockingTheScreenStopsTheCameraFromEveryOnState` |
| REG-606 | `FacePresenceMachineTests.sleepStopsTheCameraAndWakeWhileLockedKeepsItOff` |
| REG-607 | `FacePresenceMachineTests.switchingOffStopsTheCameraFromEveryState` |
| REG-608 | `FacePresenceMachineTests.awayLocksExactlyOnceWhenTheTimeRunsOut` |
| REG-609 | `FacePresenceMachineTests.aMissShorterThanTheGraceKeepsPresent` |
| REG-610 | `FaceMatchTests.aSpoofCueTurnsAMatchIntoNotOwner` |
| REG-611 | `FacePresenceMachineTests.aFailedLockGoesUnavailableAndNeverRetries` |
| REG-612 | `FacePresenceControllerTests.anUnlockNoticeWhileTheSessionIsLockedStartsNothing` |
| REG-613 | `FaceVaultTests.sealedFileHoldsNoPlaintextEmbedding` |
| REG-614 | `FaceVaultStoreTests.anUnreadableVaultIsNeverOverwritten` |
| REG-615 | `FaceMatchTests.aSwitchedOffFaceNeverMatches` |
| REG-616 | `FaceMatchTests.samplesFromAnotherRevisionNeverMatch` |
| REG-617 | `SettingsCatalogTests.exportHoldsNoFaceData` |
| REG-618 | `FacePresenceMachineTests.lockingDuringEnrollmentSavesNothing` |
| REG-619 | `FacePresenceMachineTests.aCameraThatSendsNoFramesGoesUnavailable` |

Core suites use check `native-ZeusCoreTests`; the ZeusAppTests suites get a native check defined the way the existing
per-suite native checks are. Lint rows use `closed-loop-selftests`.

## Repo hazards that apply

- Swift 6: the capture delegate is a nonisolated final class (as `ScribeMicActivity.swift` keeps Core Audio blocks out
  of the main actor); observers use `queue: .main` plus `MainActor.assumeIsolated`; detached Vision work captures
  Sendable values only (`CGImage` is passed in, numbers come back). No semaphore or group waits (blocking lint). TCC
  only through `PermissionsModel` (`test_tcc_completion_handlers_only_in_nonisolated_helper`).
- Keychain reads only through `KeychainStore` (`test_keychain_is_read_only_through_the_keychain_module`). The em dash
  lint covers new strings. Settings files are regenerated, never hand-merged. Sandboxes cannot compile Swift: budget a
  Mac build per ticket.

## Only a person at the Mac can check

1. Switch on with Camera never asked: the macOS prompt appears once, from the switch, and the camera indicator turns
   on only after it is answered. Relaunch Zeus with the switch on: no indicator until the next unlock.
2. Enroll one face in normal light; status reads Present within a second or two of looking at the screen.
3. Calibration: with two or three other people (or the owner with and without glasses), note Present or Away for each
   and the logged distances; tune `floor`, `ceiling` and the factor in FP-4's test so others read Away and the owner
   reads Present in daylight and lamp light.
4. Walk away for each "Lock after" choice: the Mac locks once, at the chosen time, through the system lock screen;
   unlocking with password, Touch ID and Watch works as before and Zeus never fills or submits anything.
5. Lock with Control-Command-Q, close the lid, let the display sleep, switch user: the camera indicator goes off each
   time, and comes back only after unlocking.
6. Hold up a phone showing the owner's photo, then a printed photo: note whether it reads Away; whatever happens, the
   locked Mac stays locked.
7. Start a teleprompter recording: face presence shows Paused and the recording works; it resumes afterwards.
8. Import a settings file with `face.presence` true on a Mac where it is off: it stays off.
9. Idle CPU and energy with the switch on and the owner present (`scripts/check-perf-budget.sh`).
10. VoiceOver reads the card in order, the countdown is announced as text, and the card is readable in light and dark.

## Out of scope, waiting on an owner decision

- Removing the `CGEvent` fallback from `ScreenLock.lock()` for the voice "lock" command (this plan leaves it as is).
- Confirm cues (blink, depth and pose, flat vs 3D) as a periodic proof of life before crediting presence: harder to
  hold the Mac awake with a photo, but it would lock owners who sit still. Needs measurements from check 3 and 6.
- Any consumer of `presence` (for example pausing a capture when the owner leaves). Each consumer is read-only and
  can never turn the camera on, unlock, or relax another feature's gate.
- Renaming faces, a camera picker, a live preview.
