# ZeusCore testability plan

Slice 0 is this document. It names later pull requests. It does not move code, and it does not change the package, the toolchain, or CI.

Base: `codex/integration-20261111` at `2722dcb`.
Line numbers below are from that commit. A slice marked `after #N` rebases onto the merged result of that pull request and re-reads the lines before it writes a test.

## Why

The Mac job runs `swift test` for `ZeusCoreTests` and an allowlisted `ZeusAppTests` suite, one runner at a time. Linux development checks compile the portable groups in `qa/portable-core/prepare.py`. They copy listed `ZeusCore` files into a small package. They do not compile the `Zeus` app target, so they cannot compile `ZeusAppTests`.

`DrawingScene` is the other gap called out for this work. `Sources/ZeusCore/Present/DrawingScene.swift:1` imports `CoreGraphics`. Linux has no such module, so that file stays out of the portable groups. The presentation group copies only the `MathLayout` declaration (`qa/portable-core/prepare.py:234`).

A behaviour that still lives in `Sources/Zeus`, or in a `ZeusCore` file that imports an Apple-only module, is checked on the Mac job. This plan moves the decision into a Foundation-only type in `ZeusCore`, with a table test, and leaves the system call in the app. Product behaviour stays as it is.

## Rules for every later slice

- One small pull request. The file sets below are disjoint, so the slices that are not waiting on an open pull request can proceed side by side.
- The first commit adds a red `ZeusCoreTests` table. The table names the current states, events, and effects. The following commit adds the value type and points the existing caller at it. The effects stay in the same order.
- A new file imports `Foundation` only. `Glibc` or `Darwin` appears only inside an existing file that already branches that way.
- No edit to `Package.swift`, `.github/workflows`, the Swift toolchain, or an SDK setting.
- No edit to `qa/feature-map.json`, `qa/regressions.json`, or `qa/portable-core/prepare.py` until the registration slice. Those files belong to open pull requests. The Mac job already runs every `ZeusCoreTests` suite, so the new tables run there as soon as they exist. Linux runs them when registration lists them.
- Do not hand-edit `Sources/Zeus/App/SettingsCatalog.swift`. `scripts/gen-settings-catalog.py` generates it.
- Leave a reducer that is already explicit where it is. The gaps below sit beside those reducers.

Already explicit, and not a slice here: `OnboardingProgress`, `DictationFlow`, `DictationCueRule`, `UpdateRefresh`, `UpdateBadgeLogic`, `FacePresenceMachine`, `FaceLockAfter`, `VoiceKeyMachine`, `TalkKeyPair`, `ShortcutRecorderState`, `ScribeSessionMachine`, `BrowserPollState`.

## Open pull requests

`git ls-remote origin 'refs/pull/*/head'` still lists heads for closed pull requests. The open set on 2026-11-20, read with `gh pr view`, is below. `#25` targets `main`. Every other open pull request targets `codex/integration-20261111`.

Showcase assets shared by `#11`, `#14`, `#15`, `#16`, and `#17`: `README.md`, `docs/SHOWCASE.md`, and `docs/media/` (banner, gifs, social preview, stills). Those paths are omitted from the per-request lists.

| PR | Head | Changed files that a slice must stay off |
| --- | --- | --- |
| #9 | `zeus-bot/spec-kit-setup` | `.cursor/skills/speckit-*`, `.specify/**`, `specs/untangle-notch/proposal.md` |
| #11 | `zeus-bot/retro-fix` | `Sources/Zeus/Pointing/PointingHotkeyMonitor.swift`, `Sources/Zeus/TopBar/TopBarViews.swift`, `Sources/ZeusCore/Pointing/PointingKeyGesture.swift`, `Sources/ZeusCore/TopBar/NotchClosedBodyLayout.swift`, `Sources/ZeusCore/VoiceKeyMachine.swift`, `Tests/ZeusCoreTests/NotchClosedBodyLayoutTests.swift`, `Tests/ZeusCoreTests/VoiceKeyWalkTests.swift`, `qa/feature-map.json`, `scripts/typecheck-voice-key-walk.sh` |
| #13 | `zeus-bot/ipc-hardening` | `Sources/Zeus/App/DebugForward.swift`, `Sources/Zeus/Chrome/ChromeBridge.swift`, `Sources/ZeusCore/PeerCredentials.swift`, `Sources/ZeusCore/PeerSigning.swift`, `Sources/ZeusCore/UnixSocket.swift`, `Sources/ZeusCore/ZeusPaths.swift`, `Sources/zeus-cli/main.swift`, `Sources/zeus-hook/main.swift`, `Tests/ZeusCoreTests/BridgePendingRepliesTests.swift`, `Tests/ZeusCoreTests/NativeHostProcessTests.swift`, `Tests/ZeusCoreTests/PeerBinaryRuleTests.swift`, `Tests/ZeusCoreTests/PeerCredentialsTests.swift`, `Tests/ZeusCoreTests/UnixSocketSafetyTests.swift`, `Tests/ZeusCoreTests/ZeusTagParserTests.swift`, `qa/closed-loop/tests/test_socket_direction.py`, `qa/release-scripts/test_release_scripts.py`, `scripts/bundle.sh` |
| #14 | `zeus-bot/approval-queue` | `Sources/Zeus/Agents/AgentCardsUI.swift`, `Sources/Zeus/Agents/AgentEventServer.swift`, `Sources/Zeus/App/AppDelegate.swift`, `Sources/Zeus/App/PermissionSweepRunner.swift`, `Sources/Zeus/App/Preferences.swift`, `Sources/Zeus/App/SnapshotRenderer.swift`, `Sources/Zeus/App/SystemNotificationService.swift`, `Sources/Zeus/App/VoiceTurnController.swift`, `Sources/Zeus/App/ZeusActivation.swift`, `Sources/Zeus/App/main.swift`, `Sources/Zeus/Calendar/LocalCalendarReader.swift`, `Sources/Zeus/Notch/NotchController.swift`, `Sources/Zeus/Notch/NotchModel.swift`, `Sources/Zeus/Notch/NotchView.swift`, `Sources/Zeus/Onboarding/OnboardingDependencies.swift`, `Sources/Zeus/Pointing/PointingHotkeyMonitor.swift`, `Sources/Zeus/TopBar/TopBarViews.swift`, `Sources/Zeus/Voice/HotkeyMonitor.swift`, `Sources/Zeus/Voice/TalkCuePlayer.swift`, `Sources/ZeusCore/AgentHubRules.swift`, `Sources/ZeusCore/ApprovalCard.swift`, `Sources/ZeusCore/ApprovalQueue.swift`, `Sources/ZeusCore/Calendar/LocalCalendar.swift`, `Sources/ZeusCore/ClientInputPolicy.swift`, `Sources/ZeusCore/Permissions/PermissionSweep.swift`, `Sources/ZeusCore/Pointing/PointingKeyGesture.swift`, `Sources/ZeusCore/Scribe/ScribeAutoStart.swift`, `Sources/ZeusCore/Scribe/ScribePopupLifecycle.swift`, `Sources/ZeusCore/TopBar/NotchClosedBodyLayout.swift`, `Sources/ZeusCore/Voice/TalkHold.swift`, `Sources/ZeusCore/VoiceKeyMachine.swift`, matching tests under `Tests/ZeusAppTests/` (`ApprovalCardSnapshotTests`, `ApprovalHighPathTests`, `KokoroWorkerSessionTests`, `PermissionSweepGuideTests`, `PermissionSweepStartTests`) and `Tests/ZeusCoreTests/` (`ApprovalCardTests`, `ApprovalQueueTests`, `LocalCalendarTests`, `NotchClosedBodyLayoutTests`, `PermissionSweepTests`, `ScribeAutoStartTests`, `ScribeMeetingStartOutcomeTests`, `TalkHoldTests`, `VoiceKeyWalkTests`), `docs/STATE-MACHINES.md`, `qa/closed-loop/tests/test_contracts.py`, `qa/closed-loop/tests/test_source_lint.py`, `qa/feature-map.json`, `qa/portable-core/prepare.py`, `qa/regressions.json`, `specs/approval-queue/**`, `specs/local-calendar/**` |
| #15 | `zeus-bot/talk-shortcut-allow-all` | `Sources/Zeus/App/AppDelegate.swift`, `Sources/Zeus/App/PermissionSweepRunner.swift`, `Sources/Zeus/App/Preferences.swift`, `Sources/Zeus/App/VoiceTurnController.swift`, `Sources/Zeus/App/ZeusActivation.swift`, `Sources/Zeus/App/main.swift`, `Sources/Zeus/Onboarding/OnboardingDependencies.swift`, `Sources/Zeus/Voice/HotkeyMonitor.swift`, `Sources/Zeus/Voice/TalkCuePlayer.swift`, `Sources/ZeusCore/Permissions/PermissionSweep.swift`, `Sources/ZeusCore/Scribe/ScribeAutoStart.swift`, `Sources/ZeusCore/Scribe/ScribePopupLifecycle.swift`, `Sources/ZeusCore/Voice/TalkHold.swift`, `Tests/ZeusAppTests/KokoroWorkerSessionTests.swift`, `Tests/ZeusAppTests/PermissionSweepGuideTests.swift`, `Tests/ZeusAppTests/PermissionSweepStartTests.swift`, `Tests/ZeusCoreTests/PermissionSweepTests.swift`, `Tests/ZeusCoreTests/ScribeAutoStartTests.swift`, `Tests/ZeusCoreTests/ScribeMeetingStartOutcomeTests.swift`, `Tests/ZeusCoreTests/TalkHoldTests.swift`, `Tests/ZeusCoreTests/VoiceKeyWalkTests.swift`, `docs/STATE-MACHINES.md`, `qa/closed-loop/tests/test_contracts.py`, `qa/closed-loop/tests/test_source_lint.py`, `qa/portable-core/prepare.py`, `qa/regressions.json`, `specs/talk-shortcut-scribe-expiry/**` |
| #16 | `zeus-bot/core-tests-hang` | `Tests/ZeusAppTests/MicrophoneListCacheTests.swift` |
| #17 | `zeus-bot/explain-001-spec` | `.cursor/skills/speckit-*`, `.specify/**`, `THIRD_PARTY_NOTICES`, `Tests/ZeusCoreTests/VoiceKeyWalkTests.swift`, `specs/001-explain-toggle/**`, `specs/002-shared-mic/**`, `specs/003-approval-sync/**`, `specs/untangle-notch/proposal.md` |
| #21 | `zeus-bot/murmur-mic-first` | `Sources/Zeus/Dictation/DictationController.swift`, `Sources/ZeusCore/Dictation/DictationFocusRule.swift`, `Sources/ZeusCore/Dictation/InsertTargetDecision.swift`, `Sources/ZeusCore/Sound/DictationCue.swift`, `Tests/ZeusAppTests/DictationBeginOrderTests.swift`, `Tests/ZeusCoreTests/DictationCueRuleTests.swift`, `Tests/ZeusCoreTests/DictationFocusRuleTests.swift`, `Tests/ZeusCoreTests/InsertTargetDecisionTests.swift`, `specs/murmur-mic-first/**` |
| #25 | `zeus-bot/scribe-userdefaults-flake` (base `main`) | `Tests/ZeusCoreTests/ScribeAutoStartOptInTests.swift`, `Tests/ZeusCoreTests/ScribeAutoStartTests.swift` |
| #27 | `zeus-bot/native-discovery` | `qa/closed-loop/native_evidence.py`, `qa/closed-loop/tests/test_native_app_host.py`, `qa/closed-loop/tests/test_native_evidence.py`, `qa/closed-loop/trusted_ax.py` |
| #29 | `zeus-bot/placedmark-redeclaration` | `Sources/Zeus/Mac/MarkOverlay.swift`, `Sources/ZeusCore/Pointing/MarkLayout.swift`, `qa/closed-loop/contracts.py`, `qa/closed-loop/gate.py`, `qa/closed-loop/run.py`, `qa/closed-loop/tests/test_placed_mark.py`, `qa/feature-map.json`, `qa/regressions.json` |
| #30 | `zeus-bot/local-voice-contract` | `Sources/ZeusCore/Voice/DuplexVoiceBackend.swift`, `Sources/ZeusCore/Voice/LocalVoiceFlags.swift`, `Sources/ZeusCore/Voice/PersistedVoiceSettings.swift`, `Sources/ZeusCore/Voice/VoiceSessionState.swift`, `Tests/ZeusCoreTests/LocalVoiceBackendContractTests.swift`, `qa/feature-map.json`, `qa/portable-core/prepare.py` |
| #31 | `zeus-bot/nativehost-eof` | `Sources/ZeusCore/NativeMessageIO.swift`, `Tests/ZeusCoreTests/NativeMessageIOTests.swift` |
| #32 | `zeus-bot/onboarding-escape-minimize` | `Sources/Zeus/Onboarding/OnboardingFlow.swift`, `Sources/ZeusCore/Onboarding/OnboardingPresentation.swift`, `Tests/ZeusAppTests/OnboardingIsolationTests.swift`, `Tests/ZeusCoreTests/OnboardingPresentationTests.swift` |
| #33 | `zeus-bot/glass-settings-shell` | `Sources/Zeus/Settings/GlanceSettingsWindow.swift`, `Sources/Zeus/Settings/GlassSettingsChrome.swift`, `Sources/Zeus/Settings/GlassShell/**`, `Sources/ZeusCore/Settings/GlassSettingsShell.swift`, `Sources/ZeusCore/Settings/Sections/**`, `Tests/ZeusCoreTests/ExistingSettingsKeyReachabilityTests.swift`, `Tests/ZeusCoreTests/Sections/**`, `qa/glass-settings-shell/check.swift` |

`specs/006-zeuscore-testability/` is a new directory. It does not overlap those spec paths.

`#32` already adds `OnboardingPresentation` with phases `expanded` and `minimized` (`escape`, `minimizeControl`, `reopen`). The onboarding slice in this plan does not edit that file. It adds the window-poll decision beside it.

`#29` gives the screen mark in `MarkLayout.swift` its own type. `DrawingScene.swift:177` has a different `PlacedMark` (a drawn mark and its unit box). The drawing slice keeps that name and does not edit `MarkLayout.swift`.

## Inventory

Each row is a decision, an order, a state machine, a parser, a geometry rule, or a settings map. The target is a new Foundation file unless the row says the logic already has a home.

### 1. Drawing mark geometry

- Where: `Sources/ZeusCore/Present/DrawingScene.swift:1` (`import CoreGraphics`), `:56` (`overlay` returns `CGPoint`), `:177` (`PlacedMark.box` is `CGRect`), `:184` (`DrawingLayout.place`), `:210` (`overlaps`), `:221` (`segmentHits`), `:245` (`bounds`).
- Target: `Sources/ZeusCore/Present/UnitBox.swift`.
- Seam: `UnitBox`, a value type of four `Double`s, with the union, inset, and overlap operations those functions use today. `DrawingScene` keeps the `CoreGraphics` import and builds each `CGRect` from a `UnitBox`, so Mac layout stays on the same numbers.
- Tests: new `Tests/ZeusCoreTests/UnitBoxTests.swift`. `Tests/ZeusCoreTests/DrawingSceneTests.swift` stays on the Mac suite (`:37` builds a `DisplayMap` with `CGRect`).
- Risk: medium. A label nudge that differs by a fraction of a unit moves a drawn label. The Mac `DrawingSceneTests` remain the check that the adapter matches.

### 2. Ring tolerance

- Where: `Sources/ZeusCore/Present/CoordinateMapper.swift:1` imports `CoreGraphics`. The tolerance itself is two thresholds and a scale rule at `:30` (`PresentTolerance`). `ScreenCoordinateMapper.ringPixelTolerance` reads it at `:164`.
- Target: `Sources/ZeusCore/Present/PresentTolerance.swift`. The mapper file keeps the import and calls the moved enum.
- Seam: the existing `PresentTolerance` enum, moved verbatim. `ringPixels` returns 48 when `scale >= 2` or `pixelWidth >= 3840`, and 24 otherwise (`:34`).
- Tests: new `Tests/ZeusCoreTests/PresentToleranceTests.swift` with those two rows, plus `ringPoints` dividing by a positive scale and treating a non-positive scale as 1 (`:40`).
- Risk: low. Call sites keep the same type name inside the same module.

### 3. Dictation preview decisions

- Where: `Sources/ZeusCore/Dictation/DictationPreview.swift:1` imports `CoreGraphics`. The key map is `:21` (`DictationPreviewKey.action`). The focus wait is `:40` (`FrontmostHandoff.waitUntilFrontmost`). The trimmed result is `:54` (`DictationPreviewResult.finalText`). The frame math at `:10` (`DictationPreviewLayout.frame`) stays in this file because it is `CGRect` placement.
- Target: `Sources/ZeusCore/Dictation/DictationPreviewRules.swift` for the three enums. The layout enum stays with the import.
- Seam: `DictationPreviewKey.action(keyCode:shift:command:)`. Return and Enter insert; Shift-Return with Command up edits; Escape cancels; every other code edits (`:30`).
- Tests: new `Tests/ZeusCoreTests/DictationPreviewRulesTests.swift`. App tests that drive the card stay in `ZeusAppTests`.
- Risk: low. The function moves with the same switch.

### 4. Shortcut recorder listening count

- Where: `Sources/Zeus/Settings/GSShortcutRecorder.swift:14` (`listening`), `:27` (increment and pause on the first listener), `:57` (decrement and resume on the last). `ShortcutRecorderState` in `Sources/ZeusCore/Shortcut.swift:423` already decides which chord was captured.
- Target: `Sources/ZeusCore/ShortcutListening.swift`.
- Seam: `ShortcutListening` value type. States: `idle`, `listening(count)`. Events: `begin`, `end`. Effects: `pauseHotkeys`, `resumeHotkeys`. `begin` while `listening` increments and emits nothing. `end` at 1 emits `resumeHotkeys`. `end` at 0 stays `idle`.
- Tests: new `Tests/ZeusCoreTests/ShortcutListeningTests.swift`. `Tests/ZeusAppTests/ShortcutRecorderModelTests.swift` keeps the AppKit monitor cases.
- Risk: low. A wrong resume hands global hot keys back while a second recorder is still listening.

### 5. Talk-chord registration

- Where: `Sources/Zeus/Voice/TalkChordHotkey.swift:96` (`desired`, `paused`, `listening`, `attempted`, `isRegistered`), `:110` (`sync`), `:117` (`setPaused`), `:123` (`apply`).
- Target: `Sources/ZeusCore/Voice/TalkChordRegistration.swift`.
- Seam: `TalkChordRegistration` value type. States: `clear`, `holding(chord)`, `refused(chord)`. Events: `sync(chord, listening)`, `pause`, `resume`. Effect: `register(chord)` or `unregister`. A paused or non-listening sync wants no chord (`:124`). A chord equal to the last attempt, already registered, is a no-op (`:125`). A refused chord is asked again on the next sync (`:101`).
- Tests: new `Tests/ZeusCoreTests/TalkChordRegistrationTests.swift`. `Tests/ZeusAppTests/TalkChordHotkeyTests.swift` keeps the registrar fake that stands in for the system hot-key call.
- Risk: medium. A stuck registration swallows a typed Space, and a dropped registration lets another shortcut take the chord.

### 6. Face presence frame gate

- Where: `Sources/Zeus/FacePresence/FacePresenceController.swift:70` (`visionFailureLimit` is 5), `:80` (`cameraRun`), `:81` (`cameraRunning`), `:86` (`visionFailures`), `:194` (`cameraEvent` drops a stale run), `:239` (`reconcile` bumps the run and resets the failure count when the camera turns on), `:273` (`process` drops a frame from another run), `:286` (the fifth failure emits `cameraFailed`), `:289` (a good frame resets the count), `:307` (an enrollment offer ignores a stale token), `:344` (`nextFaceName`).
- The presence machine is already `Sources/ZeusCore/FacePresence/FacePresenceMachine.swift:54`. It stays on the Mac-only face-presence portable group because the landmark files import `CoreGraphics` and the vault imports `CryptoKit` (`qa/portable-core/prepare.py:166`, `qa/feature-map.json:874`). This slice does not move those files.
- Target: `Sources/ZeusCore/FacePresence/FaceFrameGate.swift`.
- Seam: `FaceFrameGate` value type. States: `stopped`, `running(generation, failures)`. Events: `setCamera(on)`, `frame(generation)`, `visionFailed`, `visionOk`, `cameraSignal(generation)`. A frame or signal whose generation is not current emits nothing and does not add a failure. The fifth `visionFailed` emits `failCamera` once. `visionOk` sets failures to 0. `setCamera(true)` advances the generation and clears failures. `FaceNameSequence.next(taken:)` is the "Face N" walk at `:344`. `EnrollmentOfferGate` is the token check at `:307`: states `idle` and `offering(token)`; an offer for another token is ignored.
- Tests: new `Tests/ZeusCoreTests/FaceFrameGateTests.swift`, one row per event from both states, including a stale generation. `Tests/ZeusAppTests/FacePresenceControllerTests.swift` stays. It owns the fake camera and vault.
- Risk: medium. Counting a stale frame can mark a healthy camera failed, which feeds the lock path. The stale-generation rows are the guard.
- Settings map, already in core: `face.presence` and `face.lockAfter` are catalog rows at `Sources/Zeus/App/SettingsCatalog.swift:143`. Seconds for a label are `FaceLockAfter.seconds(forLabel:)` at `Sources/ZeusCore/FacePresence/FacePresenceMachine.swift:22`. `#33` adds a glass section for this card. This slice does not edit those glass files.

### 7. Auto-update notice, poll, and open

- Where: `Sources/Zeus/App/UpdateCoordinator.swift:16` (`pollTask` beside `refreshState`), `:28` (`startPolling` cancels the previous task, then refreshes and sleeps 3600), `:38` (`refreshBadge` reads `about.autoUpdate` outside the reducer), `:63` (`fetch` writes the badge, then `:137` `maybePresentHUD`), `:118` (`performUpdate` opens the offer link when `UpdateFeedPolicy.isSecure` says so).
- `UpdateRefresh` (`Sources/ZeusCore/Updates/UpdateRefresh.swift:8`) already keeps a single live fetch token. `UpdateHUDPresentation` (`Sources/ZeusCore/Updates/UpdateAvailability.swift:72`) and `UpdateBadgeLogic` (`:84`) already decide the badge and the "shown" key. The coordinator still runs those three steps as separate statements.
- Target: `Sources/ZeusCore/Updates/UpdateNotice.swift`.
- Seam: `UpdateAnnouncement` value type. States: `hidden`, `due(version)`, `shown(version)`. Events: `badgeHidden`, `badgeAvailable(version, shownKey)`, `didPresent(version)`. A hidden badge goes to `hidden` and presents nothing. An available badge whose version equals `shownKey` stays `shown` and presents nothing. A different version goes to `due` and emits `present`. `didPresent` goes to `shown`. A second `present` for the same version emits nothing. `UpdatePoll` value type. States: `idle`, `armed`. Event `start` from either state returns `armed` and emits `replaceTimer`, matching the cancel-then-schedule at `:29`. `UpdateOpen` is the secure-link choice at `:121`, returning the offer URL or the existing fallback string. The coordinator still performs the open.
- Tests: new `Tests/ZeusCoreTests/UpdateNoticeTests.swift`. Feed and dismissal tests that already live in `ZeusCoreTests` stay put.
- Risk: low. A missed guard shows the notice twice, or hides an offer the badge still shows. The table pairs each badge state with the shown key.
- Settings map: `about.autoUpdate` is `Sources/Zeus/App/SettingsCatalog.swift:17`. The feed URL rule is already `UpdateFeedPolicy.feedURL` in `UpdateAvailability.swift:131`. `#33` adds the glass auto-update section. This slice does not edit it.

### 8. Scribe manual start order

- Where: `Sources/Zeus/Scribe/ScribeController.swift:568` (`start`). The active-phase guard returns at `:569` before any field changes. The clear runs at `:574` through `:616`. Streams open at `:618`. The transcriber and router are built at `:636`. `run` applies `start` at `:659`. The provider starts at `:673` only when that apply succeeded. A refused apply leaves the cleared fields and does not start the provider (`:659`).
- `ScribeSessionMachine` stays the session reducer. This type is the ordered checklist around one manual `start`.
- Target: `Sources/ZeusCore/Scribe/ScribeManualStart.swift`.
- Seam: `ScribeManualStart` value type. States: `idle`, `clearing`, `wired`, `accepted`, `refused`. Events: `request(active:)`, `fieldsCleared`, `wired`, `machineApplied(Bool)`. `request(active: true)` stays `idle` and emits `refuse`. `request(active: false)` goes to `clearing` and emits `yieldCapture`, then `clearFields`, then `openStreams`. `wired` emits `applyStart`. `machineApplied(true)` emits `startProvider`. `machineApplied(false)` goes to `refused` and emits nothing further. The table locks clear-before-apply, which is the current order.
- Tests: new `Tests/ZeusCoreTests/ScribeManualStartTests.swift`. `Tests/ZeusAppTests/ScribeLifecycleScenarioTests.swift` stays with the real controller. Do not edit `ScribeAutoStartTests.swift` (`#14`, `#15`, `#25`).
- Risk: high. Starting the provider before the machine accepts, or clearing after a refused start, changes a recording. The test is a single ordered list of effect names.

Same file, deferred until this slice has merged (a second pull request may then take `ScribeController.swift`): `ScribeWordText` at `:190`, `ScribeCancelTombstones` at `:213`, and the level fall at `:1191`. They are pure and small. They are not in this slice, so the start diff stays the checklist.

### 9. Tiling preset bits

- Where: `Sources/Zeus/Tiling/TilingKeyClash.swift:6` (`ShortcutPreset.tilingShortcut`) turns a Carbon modifier mask into `ShortcutModifiers`. The clash rule itself is already `TileBaseConflicts` in `ZeusCore`. `Keys.live` at `:62` is the app reading settings into that rule.
- Target: `Sources/ZeusCore/Tiling/TilePresetBits.swift`.
- Seam: `TilePresetBits.shortcut(keyCode:mask:)` taking the numeric mask. The app extension passes the Carbon constants in and keeps the same `Shortcut`.
- Tests: new `Tests/ZeusCoreTests/TilePresetBitsTests.swift`, one row per modifier bit and the empty-key nil. `Tests/ZeusAppTests/TilingKeyClashTests.swift` keeps the "every global key is listed" check.
- Risk: low. A dropped bit would let tiling bind a key the talk monitor already owns. The rows are the four modifier bits.

### 10. Onboarding presentation and window polling

`after #32`. `#32` owns `OnboardingFlow.swift`, `OnboardingPresentation.swift`, and `OnboardingIsolationTests.swift`.

- Where, presentation finish: `Sources/Zeus/Onboarding/OnboardingFlow.swift:124` (`completedThisPresentation`), `:143` (`beginPresentation`), `:160` (`windowClosed`), `:164` (`skipStep`), `:179` (`complete` accepts only the sounds step, once). Progress itself is `OnboardingProgress`. The one-shot flag is a second bit beside it.
- Where, step motion: `:42` (`OnboardingTransition` durations), `:212` (`go` cancels `transitionTask` and then animates). The `Animation` values stay in the app. The durations are numbers and can move with the poll type.
- Where, wake: `:233` (`playWake`: asleep, then waking, then awake, each step bailing to awake when the step changed or motion is reduced).
- Where, poll policy: `:390` (`OnboardingPollingPolicy.shouldPoll`), `:399` (`OnboardingPollingLifecycle.setVisible` ignores a repeated value), `:495` (`synchronizePolling` passes presented, visible, miniaturized, app-hidden, occluded).
- Where, poll publish: `Sources/Zeus/Onboarding/OnboardingServices.swift:15` (`access` maps each capability to allowed, denied, or not granted), `:124` (`probeDisk` sets `diskProbeStale` and runs once more), `:146` (`startPolling` is a single task), `:158` (`stopPolling` bumps `refreshGeneration` so a late notification read cannot publish).
- Target: `Sources/ZeusCore/Onboarding/OnboardingWindowPoll.swift`. Do not edit `OnboardingPresentation.swift`.
- Seam: three value types.
  - `OnboardingFinishGate`. States: `open`, `finished`. Events: `begin`, `complete(onSoundsStep:)`. `begin` returns to `open`. `complete` on the sounds step from `open` emits `finish` and goes to `finished`. Any other `complete` emits nothing.
  - `OnboardingWake`. States: `asleep`, `waking`, `awake`. Events: `start(welcome:reduceMotion:)`, `advance`, `leaveWelcome`. A reduced or non-welcome start goes straight to `awake`.
  - `OnboardingWindowPoll`. States: `stopped`, `polling`. Event: `report(presented:windowVisible:miniaturized:appHidden:occluded:)`. Polling is the conjunction at `:392`. A report that does not change the state emits nothing (`:406`). Entering `polling` emits `startPolling`. Leaving emits `stopPolling`.
  - `OnboardingProbeGate`. States: `idle`, `running`, `runningStale`. A probe requested while `running` goes to `runningStale` and emits nothing (`:125`). Completion from `runningStale` emits `probeAgain` (`:138`).
  - `OnboardingAccessMap.decide(capability:status:)` is the switch at `:15`, with the system status passed in as a value.
- Tests that move: the `shouldPoll` rows in `Tests/ZeusAppTests/OnboardingIsolationTests.swift:156` and the lifecycle start/stop counts at `:170` move to `Tests/ZeusCoreTests/OnboardingWindowPollTests.swift`. The window-controller cases stay in the app test.
- Risk: medium. Polling while the guide is hidden refreshes permission state in the background. Stopping a poll that should run leaves a grant invisible until the guide is reopened. The five booleans are the whole table.

### 11. Native message connection

`after #31`. `#31` owns `NativeMessageIO.swift` and `NativeMessageIOTests.swift`. `#13` owns the socket and peer files. This slice edits `NativeMessageIO.swift` only among those, plus a new file and a new test. It does not edit `NativeMessageIOTests.swift` or the `#13` files.

- Where: `Sources/ZeusCore/NativeMessageIO.swift:46` (output `terminal`, `finishing`, `frames`, `bytes`), `:66` (`enqueue` admission), `:98` (`finish` flushes accepted frames and then closes), `:117` (`stop` is first-writer-wins). Input `State` at `:178` (`end`, `started`, `suspended`), `:194` (a second `start` returns false), `:224` (a second `stop` is ignored), `:241` (`readAvailable` suspends around `consume` and resumes on `EAGAIN`).
- Target: `Sources/ZeusCore/NativeMessageLink.swift`. The descriptor, the poll loop, and the `Darwin` / `Glibc` reads stay in `NativeMessageIO.swift`.
- Seam: `NativeMessageOutputLink` value type. States: `open(frames, bytes)`, `finishing(frames, bytes)`, `closed(failure)`. Events: `enqueue(byteCount)`, `writeFinished(byteCount)`, `finish`, `stop(failure)`. Guards, matching the current returns: a frame shorter than 4 bytes or larger than the host limit is `tooLarge` and does not queue (`:67`); `closed` or `finishing` returns `closed` (`:70`); over 32 frames or over 8 MiB queued returns `full` (`:71`); `finish` from `open` goes to `finishing` and returns true; a second `finish` returns false (`:100`); the first `stop` closes, a later `stop` is ignored (`:119`). `writeFinished` decrements the counters (`:91`).
- Seam: `NativeMessageInputLink` value type. States: `idle`, `reading(suspended)`, `ended(end)`. Events: `start`, `stop`, `readable`, `yielded`, `again`, `eof`, `failed`. A second `start` returns false (`:198`). `stop` after `ended` is ignored (`:226`). `yielded` goes to `reading(suspended: true)` (`:257`). `again` clears suspended (`:253`).
- Tests: new `Tests/ZeusCoreTests/NativeMessageLinkTests.swift`, one row per admission and per end. The pipe tests stay in `NativeMessageIOTests`.
- Risk: high. A wrong full or closed guard drops a frame, or writes after the descriptor has closed. The table uses the constants at `:39` and `:67`.

### 12. Dictation begin order

`after #21`. `#21` owns `DictationController.swift` and adds `Tests/ZeusAppTests/DictationBeginOrderTests.swift`. It also adds `DictationFocusRule.swift`, `InsertTargetDecision.swift`, and `DictationCue.swift`. This slice edits the controller and moves that app test. It does not edit the other three files.

- Where, on this base, before `#21`: `Sources/Zeus/Dictation/DictationController.swift:569` (`begin`). The order today is: refuse unless `flow.canStartJob` (`:570`); yield the previous capture (`:571`); resolve access, language, and the engine, and prewarm (`:573`); refuse without a microphone, or without on-device recognition and without a local engine (`:585`); prepare a missing local model (`:595`); configure the recognizer, the mode, the selection, the hints, and the stream (`:598`); play the cue and then open the microphone (`:623`, `DictationCueRule.beginCapture`); on throw, invalidate and `startFailed` (`:630`); on success, `micOpened`, pause media, and the Escape monitor when trusted (`:640`).
- `#21` changes this order so listening starts as the key goes down. The red table for the slice is the order `#21` lands, read from the merged `begin()` and from `DictationBeginOrderTests`, transcribed as effect names. This plan does not invent a third order.
- Target: `Sources/ZeusCore/Dictation/DictationBeginOrder.swift`.
- Seam: `DictationBeginOrder` value type. States: `idle`, `checked`, `armed`, `opening`, `listening(turn)`, `refused(reason)`. Each event is one step of the landed sequence. An event that skips a step leaves the state and emits nothing. The cue-then-open pair stays a single effect list so the cue cannot move to the other side of the microphone open without a failing row.
- Tests: move `Tests/ZeusAppTests/DictationBeginOrderTests.swift` to `Tests/ZeusCoreTests/DictationBeginOrderTests.swift`. One app test remains that the controller sends the steps in that order.
- Risk: high. This is the microphone path. The slice copies the landed sequence. It does not reorder it.
- Same file, deferred until this slice has merged: `DictationFinishFlow` at `:161` and `DictationInjectCompletion` at `:225`. Both are already structs driven by closures. A follow-up can move them once it is the only editor of `DictationController.swift`.

### 13. Hold Right Option to talk

`after #14` and `after #15`. Both own `Sources/Zeus/Voice/HotkeyMonitor.swift`. Do not edit `VoiceKeyMachine.swift` (`#11`, `#14`), `VoiceKeyWalkTests.swift` (`#11`, `#14`, `#15`, `#17`), or `TalkHold.swift` (`#14`, `#15`). `TalkKeyPair` stays the arbiter. This slice is the adapter bit that still sits outside it.

- Where: `Sources/Zeus/Voice/HotkeyMonitor.swift:125` (`launcherSpaceSeen`), `:127` (`ownerTurn`), `:202` (a chord key the monitors missed is inserted before the flags event), `:236` (`lookForALauncherSpace` sets the flag when the second key owns the turn and Space is down), `:272` (`secondConfig` is a hold with the typing confirm and no chord), `:296` (the `start` effect), `:299` (records `ownerTurn`), `:300` (clears the flag), `:302` (the `send` effect), `:306` (a second-key send with the flag set, or with Space still down, calls `onCancel` and skips `onRelease`).
- The settings map that chooses the key is already `VoiceKey.secondTalkKey`, read at `Sources/Zeus/Voice/TalkChordHotkey.swift:33` (`SecondTalkRouting.current`). The catalog row is `voice.secondTalkKey` at `Sources/Zeus/App/SettingsCatalog.swift:178`. This slice does not move that reader. `TalkChordHotkey.swift` belongs to slice 5.
- Target: `Sources/ZeusCore/Voice/SecondKeyRelease.swift`.
- Seam: `SecondKeyRelease` value type. States: `clear`, `spaceSeen`. Events: `look(ownerIsSecond:spaceDown:)`, `started`, `send(spaceStillDown:)`. `look` while the second key owns the turn and Space is down goes to `spaceSeen`. `started` returns to `clear`. `send` from `spaceSeen`, or with Space still down, emits `cancel`. Otherwise it emits `send`. A `look` while the primary key owns the turn leaves the state.
- Tests: new `Tests/ZeusCoreTests/SecondKeyReleaseTests.swift`. The walk suites stay where they are.
- Risk: medium. A `send` that should cancel will deliver a launcher press as speech. A `cancel` that should send drops the utterance. The table is the four combinations of the flag and the live Space bit.

Same file, deferred until this slice has merged: `KeyAccessNotice.cue` at `:62` and `ShortcutModifiers.init` from device flags at `:6`. `KeyListenAccess` at `:30` is a waiter list with a 3 second timer. It is a small machine (empty, waiting) and moves in that follow-up, because this slice is the only editor of `HotkeyMonitor.swift` until it merges.

### 14. Further Mac-only geometry, recorded and not sliced yet

These files hold pure geometry behind an Apple import. They are not in the ordered slices. A later pass gives each its own Foundation box, one file per pull request, after any open pull request that already edits it.

| File | Line | What is pure | Why it waits |
| --- | --- | --- | --- |
| `Sources/ZeusCore/Onboarding/OnboardingChromeLayout.swift` | `:3` | Row pitch and centres (`:26`, `:31`) are numbers stored as `CGFloat` | Several onboarding views read the constants. A `Double` twin is a later slice of this one file. |
| `Sources/ZeusCore/FacePresence/LandmarkMath.swift` | `:2` | Landmark geometry | Darwin-only group. Screen-lock math. |
| `Sources/ZeusCore/FacePresence/FaceSelection.swift` | `:2` | Face picking | Same group. |
| `Sources/ZeusCore/FacePresence/SpoofCues.swift` | `:2` | Spoof scoring | Same group. |
| `Sources/ZeusCore/Fling/FlingGeometry.swift` | `:1` | Where a flicked file lands | `CoreGraphics`. Fling pairing stays on the Mac job. |
| `Sources/ZeusCore/Fling/FlingFlick.swift` | `:1` | Flick gesture | Same. |
| `Sources/ZeusCore/TopBar/NotchClosedBodyLayout.swift` | `:1` | Closed-notch boxes | `after #11` and `after #14`. |
| `Sources/ZeusCore/AgentHubRules.swift` | `:1` | Hub layout numbers | `after #14`. |
| `Sources/ZeusCore/Avatar/MascotRasterScale.swift` | `:1` | Raster scale | Imports `SwiftUI` as well as `CoreGraphics`. |
| `Sources/Zeus/Avatar/MascotMotion.swift` | `:12` | Pose cycle (`:35`) is a table of poses and holds | The file imports `SwiftUI`. A later slice moves `cycle(for:)` only. |

`Sources/ZeusCore/Audio/Spectrum.swift:1` imports `Accelerate`, `Sources/ZeusCore/TopBar/NotificationMirror.swift:2` imports `SQLite3`, `Sources/ZeusCore/License/LicenseKeys.swift:4` imports `IOKit`, and the Fling and face-vault files import `CryptoKit`. Those stay on the Mac job. A protocol in front of them would be a new implementation, which this plan does not ask for.

### 15. App logic already backed by a core type

Recorded so a later slice does not extract it again.

| Where | Line | Home |
| --- | --- | --- |
| `Sources/Zeus/Scribe/ScribeJoinApps.swift` | `:24` | Preferred-app order is `ScribeJoinApps` in core. The resolver sorts the system list. |
| `Sources/Zeus/Brain/CLILocator.swift` | `:14` | Tool names and search directories. A later slice can move the two arrays. The filesystem probe stays in the app. |
| `Sources/Zeus/Chrome/BrowserMediaFeed.swift` | `:213` | The poll decisions are `BrowserPollState` in `Sources/ZeusCore/TopBar/BrowserPollMachine.swift:12`. |
| `Sources/Zeus/Scribe/MeetingSpeakerSources.swift` | `:111` | `pollInterval` is 0.7 s and `poll` returns nil when the interval has not elapsed (`:135`). A one-function due check can move later. The window walk stays in the app. |
| `Sources/Zeus/Onboarding/OnboardingDependencies.swift` | `:19` | `OnboardingMotionPolicy.reduced` is `system` or the fixture override. `after #14` and `after #15`, which own this file. |

## Ordered slices

Slice 0 is this file. Slices 1 through 9 touch no file in the open-pull-request table. Slices 10 through 13 wait. Slice 14 runs last and is the one that edits the shared QA files.

| Slice | Wait | Files | Red test first |
| --- | --- | --- | --- |
| 1. Unit boxes for drawn marks | | `Sources/ZeusCore/Present/UnitBox.swift`, `Sources/ZeusCore/Present/DrawingScene.swift`, `Tests/ZeusCoreTests/UnitBoxTests.swift` | Bounds, overlap, and the eight-step label nudge |
| 2. Ring tolerance | | `Sources/ZeusCore/Present/PresentTolerance.swift`, `Sources/ZeusCore/Present/CoordinateMapper.swift`, `Tests/ZeusCoreTests/PresentToleranceTests.swift` | 24 px, 48 px, and the scale fallback |
| 3. Dictation preview rules | | `Sources/ZeusCore/Dictation/DictationPreviewRules.swift`, `Sources/ZeusCore/Dictation/DictationPreview.swift`, `Tests/ZeusCoreTests/DictationPreviewRulesTests.swift` | Key action, handoff attempts, empty trim |
| 4. Recorder listening count | | `Sources/ZeusCore/ShortcutListening.swift`, `Sources/Zeus/Settings/GSShortcutRecorder.swift`, `Tests/ZeusCoreTests/ShortcutListeningTests.swift` | First begin pauses, second begin does not resume, last end resumes |
| 5. Talk-chord registration | | `Sources/ZeusCore/Voice/TalkChordRegistration.swift`, `Sources/Zeus/Voice/TalkChordHotkey.swift`, `Tests/ZeusCoreTests/TalkChordRegistrationTests.swift` | Pause clears, a refusal is retried, a held chord is idempotent |
| 6. Face frame gate | | `Sources/ZeusCore/FacePresence/FaceFrameGate.swift`, `Sources/Zeus/FacePresence/FacePresenceController.swift`, `Tests/ZeusCoreTests/FaceFrameGateTests.swift` | Stale generation, five failures, name sequence, enrollment token |
| 7. Auto-update notice | | `Sources/ZeusCore/Updates/UpdateNotice.swift`, `Sources/Zeus/App/UpdateCoordinator.swift`, `Tests/ZeusCoreTests/UpdateNoticeTests.swift` | Badge plus shown-key, poll replace, secure open |
| 8. Scribe manual start | | `Sources/ZeusCore/Scribe/ScribeManualStart.swift`, `Sources/Zeus/Scribe/ScribeController.swift`, `Tests/ZeusCoreTests/ScribeManualStartTests.swift` | Active refuse, then clear, wire, apply, provider |
| 9. Tiling preset bits | | `Sources/ZeusCore/Tiling/TilePresetBits.swift`, `Sources/Zeus/Tiling/TilingKeyClash.swift`, `Tests/ZeusCoreTests/TilePresetBitsTests.swift` | Each modifier bit and a missing key code |
| 10. Onboarding window poll | `after #32` | `Sources/ZeusCore/Onboarding/OnboardingWindowPoll.swift`, `Sources/Zeus/Onboarding/OnboardingFlow.swift`, `Sources/Zeus/Onboarding/OnboardingServices.swift`, `Tests/ZeusCoreTests/OnboardingWindowPollTests.swift`, `Tests/ZeusAppTests/OnboardingIsolationTests.swift` | The five visibility booleans, finish-once, probe stale |
| 11. Native message link | `after #31` | `Sources/ZeusCore/NativeMessageLink.swift`, `Sources/ZeusCore/NativeMessageIO.swift`, `Tests/ZeusCoreTests/NativeMessageLinkTests.swift` | tooLarge, full, closed, second start, second stop |
| 12. Dictation begin order | `after #21` | `Sources/ZeusCore/Dictation/DictationBeginOrder.swift`, `Sources/Zeus/Dictation/DictationController.swift`, `Tests/ZeusAppTests/DictationBeginOrderTests.swift`, `Tests/ZeusCoreTests/DictationBeginOrderTests.swift` | The effect list `#21` lands, including cue then microphone |
| 13. Second-key release | `after #14`, `after #15` | `Sources/ZeusCore/Voice/SecondKeyRelease.swift`, `Sources/Zeus/Voice/HotkeyMonitor.swift`, `Tests/ZeusCoreTests/SecondKeyReleaseTests.swift` | Space seen cancels, Space up sends, primary owner leaves the flag |
| 14. Register the portable group | `after #11`, `after #14`, `after #15`, `after #29`, `after #30` | `qa/portable-core/prepare.py`, `qa/feature-map.json`, `qa/regressions.json` | No product test. The group lists the new Foundation files and their new tests, and the feature map gains one portable check for that group. `qa/closed-loop/tests/test_contracts.py` is edited only when an existing assertion names the group set. |

Slice 14 is what makes the new tables run on Linux. Until it merges, the Mac `ZeusCoreTests` run is the proof. Slice 14 changes no product behaviour, no `Package.swift`, and no workflow.
