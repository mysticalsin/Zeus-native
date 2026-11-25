# Implementation Plan: Settings surface

**Branch**: `005-settings-surface` | **Date**: 2026-11-20 | **Inventory**: [inventory.md](inventory.md)

**Input**: Tony, 2026-11-20. Keep every setting Zeus has on `codex/integration-20261111` (`2722dcb`). Add the sections in inventory.md. Redraw the settings chrome in Zeus's own liquid-glass language: translucent material, depth, soft highlights, and motion that follows Reduce Motion. Clean-room. The closed-source reference is not named, and none of its code or assets is copied.

**Base for the series**: `codex/integration-20261111`. Each PR targets that branch. This document is the only commit on `zeus-bot/settings-inventory`.

## Summary

PR A lands first. It adds a shared glass shell and design tokens and re-hosts every existing setting with the same id, type, and default. One test enumerates every key in inventory.md section 2 and fails if a key is missing or its shown section cannot be opened. After PR A, one PR per target section adds only the settings inventory.md lists for that section. A section whose settings are UNSPECIFIED adds the section and no new key.

## Technical Context

**Language/Version**: Swift 6

**Primary Dependencies**: The settings files named in inventory.md. The updater dependency approved for R-022 is added only in the Auto-update PR, with the notices already required by `specs/004-notch-parity/spec.md:128`. No other dependency is added.

**Storage**: Existing `UserDefaults` keys and the Keychain items already used for license and voice. New Wave 2 settings default off and fail closed (`spec.md:80`, `spec.md:169`).

**Testing**: Swift Testing, red first. The key test is named per PR below. Linux can compile the portable key list. A Mac runs the window walk. `checklist.md` is not in this commit.

**Target Platform**: macOS 14.2

**Project Type**: Native macOS app

**Constraints**: No private API and no new permission except R-015, R-016, R-017, R-018, R-019, R-020, R-022, and R-023, and only behind a setting that is off by default and fails closed (`spec.md:80`). R-014 stays unimplemented (`spec.md:132`). Reduce Motion comes from `Motion.read()` (`Sources/Zeus/App/Preferences.swift:84-97`). Reduce Transparency already has a solid fallback in `Sources/Zeus/Recordly/RecordlyGlass.swift:21-27`. Face approval, Settings, and music transport stay local (`spec.md:149-157`).

## Constitution Check

- **I. Simplicity**: One section per PR. Existing keys stay. Held rows say "not available yet" (`spec.md:166`). Pass, as a requirement.
- **II. Red-first**: Each PR starts with the test named below, failing on `2722dcb`. Pass, as a requirement. This commit runs none of them.
- **III. Clean-room**: Prior-art notices stay in `specs/004-notch-parity/spec.md:134-145` and `THIRD_PARTY_NOTICES`. This plan does not copy those projects. Pass.
- **IV. Privacy**: Wave 2 settings stay off until the owner turns them on. An import cannot turn them on. Pass, as a requirement.
- **V. Motion and accessibility**: New motion uses `MotionTokens` (`Sources/ZeusCore/TopBar/MotionTokens.swift:15-38`) and `Motion.spring`, which returns nil under Reduce Motion (`Preferences.swift:117-118`). Pass, as a requirement.
- **VI. Local without a model**: The shell, the section list, and the key test do not call a model or the network. Pass.

## Project Structure

```text
specs/005-settings-surface/
├── inventory.md
└── plan.md
```

Code, when a later PR starts, uses the owned files below. No file is owned by two PRs in this series.

## PR A — Glass shell

**Comes first.** Re-hosts every existing setting. Changes no id, type, default, or control behavior. The chrome around those controls becomes the glass shell.

**Red test**: `everyExistingSettingsKeyStaysPresentAndReachable` in `Tests/ZeusAppTests/ExistingSettingsKeyReachabilityTests.swift`.

The test's key list is the 212 `SettingsCatalog.all` ids (`Sources/Zeus/App/SettingsCatalog.swift:6-217`) plus every outside-catalog key in inventory.md section 2.3. It fails while any id is absent. For a section in `SettingsNavigation.Section.shown` (`Sources/Zeus/App/SettingsView.swift:15-17`) it also fails while that section cannot be selected and the id's row is not in the selected page. Interview, iPhone, and Intelligence stay present and stay out of the sidebar, which is the reachability they have today (`SettingsView.swift:14-16`).

**Owns**:

- `Sources/Zeus/Settings/GlassShell/GlassSettingsTokens.swift`
- `Sources/Zeus/Settings/GlassShell/GlassSettingsChrome.swift`
- `Sources/Zeus/Settings/GlassShell/GlassSettingsHost.swift`
- `Sources/Zeus/Settings/GlassShell/GlassSectionManifest.swift`
- `Sources/Zeus/Settings/GlassShell/GlassSettingsWindow.swift`
- `Tests/ZeusAppTests/ExistingSettingsKeyReachabilityTests.swift`

`GlassSettingsTokens` holds the material (translucent fill, depth, soft highlight) and reads `MotionTokens` for timing. It does not edit `Sources/Zeus/App/GlassTheme.swift` or `Sources/Zeus/Settings/GlanceSettingsStyle.swift`. The host presents the existing pages. `GlassSectionManifest.swift` lists today's sections only. Later PRs append one line, in the merge order below, and own none of this file.

**Does not edit**: `GlanceSettingsPages.swift`, `GlanceSettingsStyle.swift`, `SettingsCatalog.swift`, `VoiceSettings.swift`, `Sources/ZeusCore/Voice/*`, `Dictation*`, `InsertTarget*`, `Onboarding*`, `NativeMessageIO.swift`, `NativeHost*`, Scribe tests, `qa/feature-map.json`.

## One PR per section

Each PR's red test is written first and fails on the PR A tree. The PR owns the two files in its row and appends one id to `GlassSectionManifest.swift`. It adds a key only when inventory.md gives that key a source line. UNSPECIFIED means the section appears and the test fails if the PR introduces a key.

| PR | Section | Owns | Red test |
| --- | --- | --- | --- |
| B | General | `Sources/Zeus/Settings/Sections/GeneralSettingsSection.swift`, `Tests/ZeusAppTests/GeneralSettingsSectionTests.swift` | `generalKeepsItsKeysAndTheLightRowStaysAStubUntilSpecified` |
| C | Media | `Sources/Zeus/Settings/Sections/MediaSettingsSection.swift`, `Tests/ZeusAppTests/MediaSettingsSectionTests.swift` | `mediaShowsTheNamedContractRowsAndHeldRowsSayNotAvailableYet` |
| D | License | `Sources/Zeus/Settings/Sections/LicenseSettingsSection.swift`, `Tests/ZeusAppTests/LicenseSettingsSectionTests.swift` | `licenseSectionStillReachesTheExistingLicenseRow` |
| E | Weather | `Sources/Zeus/Settings/Sections/WeatherSettingsSection.swift`, `Tests/ZeusAppTests/WeatherSettingsSectionTests.swift` | `weatherSectionAddsNoKey` |
| F | Sensory | `Sources/Zeus/Settings/Sections/SensorySettingsSection.swift`, `Tests/ZeusAppTests/SensorySettingsSectionTests.swift` | `sensorySectionAddsNoKey` |
| G | Portal | `Sources/Zeus/Settings/Sections/PortalSettingsSection.swift`, `Tests/ZeusAppTests/PortalSettingsSectionTests.swift` | `portalSectionAddsNoKey` |
| H | Battery | `Sources/Zeus/Settings/Sections/BatterySettingsSection.swift`, `Tests/ZeusAppTests/BatterySettingsSectionTests.swift` | `missingBatteryKeysHideAndUnknownIsNotZero` |
| I | Accessory | `Sources/Zeus/Settings/Sections/AccessorySettingsSection.swift`, `Tests/ZeusAppTests/AccessorySettingsSectionTests.swift` | `speakerNamesDoNotBrowseUntilLocalNetworkIsOn` |
| J | Focus | `Sources/Zeus/Settings/Sections/FocusSettingsSection.swift`, `Tests/ZeusAppTests/FocusSettingsSectionTests.swift` | `focusNameUsesThePublicFilterUnlessTheStoreFileIsOptedIn` |
| K | Lock Screen | `Sources/Zeus/Settings/Sections/LockScreenSettingsSection.swift`, `Tests/ZeusAppTests/LockScreenSettingsSectionTests.swift` | `missingLockScreenSymbolStaysHidden` |
| L | Face ID | `Sources/Zeus/Settings/Sections/FaceIDSettingsSection.swift`, `Tests/ZeusAppTests/FaceIDSettingsSectionTests.swift` | `faceApprovalSettingIsOffAndTheKillSwitchStopsTheCamera` |
| M | Auto-update | `Sources/Zeus/Settings/Sections/AutoUpdateSettingsSection.swift`, `Tests/ZeusAppTests/AutoUpdateSettingsSectionTests.swift` | `anUpdateWithoutAValidSignatureDoesNotInstall` |

H, I, J, K, L, and M default the new control off and fail closed. H owns the single R-015/R-016 setting, because the contract describes one setting (`spec.md:44`). I does not add a second key for listening mode. M is the only PR that adds the updater dependency, and that dependency is its own commit inside M, with no private key and no publish (`spec.md:128`).

K also owns the second red test `unlockDoesNotSwallowTheNextClick` from `specs/004-notch-parity/tasks.md:68`. L also owns `faceUnlockWithNetworkAndLLMStubbedToThrowDoesNotCallEither` (`tasks.md:55`). Those tests live in the test file L or K already owns.

R-020, R-007, and R-024 have no target section in inventory.md. No PR in this series builds them. R-014 and R-025 are held rows on Media (`spec.md:132`, `spec.md:166`).

## Collisions with open PRs

Read on 2026-11-20 from the open pull requests. A settings PR that edits a file in this table collides. The owned files above are outside the table.

| PR | Head | Files it changes | Settings series |
| --- | --- | --- | --- |
| #22 | `zeus-bot/settings-plain` | `Sources/Zeus/Settings/GlanceSettingsPages.swift`, `Sources/Zeus/Settings/GlanceSettingsStyle.swift`, `qa/closed-loop/tests/test_settings_copy_lint.py` | None of this series edits those files. #22 is copy only (inventory.md section 2.4). Merge #22 before anyone later edits the page copy. |
| #21 | `zeus-bot/murmur-mic-first` | `Sources/Zeus/Dictation/DictationController.swift`, `Sources/ZeusCore/Dictation/DictationFocusRule.swift`, `Sources/ZeusCore/Dictation/InsertTargetDecision.swift`, `Sources/ZeusCore/Sound/DictationCue.swift`, `Tests/ZeusAppTests/DictationBeginOrderTests.swift`, `Tests/ZeusCoreTests/DictationCueRuleTests.swift`, `Tests/ZeusCoreTests/DictationFocusRuleTests.swift`, `Tests/ZeusCoreTests/InsertTargetDecisionTests.swift`, `specs/murmur-mic-first/plan-debate.md`, `specs/murmur-mic-first/plan.md` | Dictation keys stay on the existing Dictation page. No series PR owns these files. |
| #25 | `zeus-bot/scribe-userdefaults-flake` | `Tests/ZeusCoreTests/ScribeAutoStartOptInTests.swift`, `Tests/ZeusCoreTests/ScribeAutoStartTests.swift` | `scribe.autoStart` stays in the catalog. No series PR edits these tests. |
| #30 | `zeus-bot/local-voice-contract` | `Sources/ZeusCore/Voice/DuplexVoiceBackend.swift`, `Sources/ZeusCore/Voice/LocalVoiceFlags.swift`, `Sources/ZeusCore/Voice/PersistedVoiceSettings.swift`, `Tests/ZeusCoreTests/LocalVoiceBackendContractTests.swift`, `qa/feature-map.json`, `qa/portable-core/prepare.py` | The diff does not contain `Sources/Zeus/Voice/VoiceSettings.swift`. The series still leaves `Sources/ZeusCore/Voice/` and `VoiceSettings.swift` untouched, and it does not edit `qa/feature-map.json` while #30 is open. |
| #31 | `zeus-bot/nativehost-eof` | `Sources/ZeusCore/NativeMessageIO.swift`, `Tests/ZeusCoreTests/NativeMessageIOTests.swift` | The diff has no `NativeHost*` file. No series PR edits `NativeMessageIO.swift` or a `NativeHost*` file. |
| #32 | `zeus-bot/onboarding-escape-minimize` | `Sources/Zeus/Onboarding/OnboardingFlow.swift`, `Sources/ZeusCore/Onboarding/OnboardingPresentation.swift`, `Tests/ZeusAppTests/OnboardingIsolationTests.swift`, `Tests/ZeusCoreTests/OnboardingPresentationTests.swift` | R-023's onboarding sentences (`spec.md:115`) go in `FaceIDSettingsSection.swift`, which L owns. L does not edit `Onboarding*`. |

`zeus-bot/settings-permissions` has no open PR. On `e4ea25d` it also edits `GlanceSettingsPages.swift` and adds `Sources/Zeus/Settings/PermissionDeskView.swift`, `Sources/ZeusCore/App/PermissionDesk.swift`, and `specs/settings-permissions/`. A later permissions PR collides with #22 on `GlanceSettingsPages.swift`. This series does not edit those files. The current permission rows stay the ten `perm.*` catalog ids.

## Merge order

1. #22, #21, #25, #30, #31, and #32 can merge in any order relative to each other. Their files do not overlap this series.
2. PR A into `codex/integration-20261111`.
3. Then B, C, D, E, F, G. These six only re-home or add an empty section. They merge one at a time so each appends its own manifest line.
4. Then H, I, J, K. Each is off by default. H before I, because I must not grow a second earbud key.
5. Then L. Face ID stays off the onboarding files #32 owns.
6. Then M. The updater dependency lands only here, after the shell and the other sections.

`qa/feature-map.json` stays with #30 until that PR merges. This series does not append a row there.

## What can be reused

From `origin/zeus-bot/notch-parity` (`dfd1179`), docs only:

- The contract text and the prior-art notes in `specs/004-notch-parity/spec.md`.
- The red-test names in `specs/004-notch-parity/tasks.md:67-72` for H, I, J, K, and M.
- The face tests in `tasks.md:48-55` for L.
- `qa/face-approval-live.md` stays Tony's live list. L does not fill it.

From `origin/zeus-bot/canopy-parity` (`2c44319`), public types only:

- `PlaybackCollapse` in `Sources/ZeusCore/TopBar/MediaIslandFeatures.swift:189-201`. Its id is `music.collapseOnPause` and it is a bool. R-005 asks for instant, delay, or never (`spec.md:34`). The Media PR may reuse the Reduce Motion guard at line 201. It does not treat the bool as the finished control. The three-way key is UNSPECIFIED.
- `OutputDeviceIcon` in the same file, lines 206-224, for R-008's public icon map.
- `LyricWordTiming` in `Sources/ZeusCore/Lyrics/LyricWords.swift:14`, for R-003 and R-012 as a parser of times already in the file.

From the same branch, do not reuse. The notch spec says private paths on `2c44319` are not reused (`spec.md:28`):

- `Sources/Zeus/TopBar/EarbudOverlay.swift`
- `Sources/Zeus/TopBar/FocusNameController.swift` and `Sources/ZeusCore/TopBar/FocusNameStore.swift`
- `Sources/Zeus/TopBar/LockScreenPlayerController.swift`
- `scripts/now-playing-media.c` (R-014)

Already on `2722dcb`, and re-hosted by PR A rather than rewritten:

- `SettingsCatalog.all`, `SettingsStore`, and the existing section pages.
- `Glass` in `Sources/Zeus/App/GlassTheme.swift:11-39` and the glass frame in `RecordlyGlass.swift:10-27`.
- Drawn-notch keys `notch.shapeWithoutNotch`, `notch.drawnWidth`, `notch.drawnHeight`, `notch.drawnOffset` (`SettingsCatalog.swift:41-44`), which D3 and D4 already placed on Appearance.
- Face presence keys `face.presence`, `face.lockAfter`, `face.status` (`SettingsCatalog.swift:143-145`). L keeps those ids and adds no second key until one is specified.
- Update keys `about.autoUpdate`, `about.updateFeedURL`, `about.checkNow` (`SettingsCatalog.swift:17-19`). M shows them in the Auto-update section with the same types and defaults. `about.autoUpdate` stays `false`.

## Complexity Tracking

The private-API allowance is the exception named in `spec.md:80`. H, J, and K are the PRs that may use it, each behind its own off switch. M may add the approved updater dependency and may not add a private API. L may use the camera entitlement the app already has and may not add one (`spec.md:113`).
