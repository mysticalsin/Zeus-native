# Zeus bug ledger

Mapped on `codex/integration-20261111` at `2722dcb7497d5415fbc1fcb1f65c49629966a281`, plus the open `zeus-bot/*` heads named below. This branch changes docs and red repros only. Nothing here is wired into `Package.swift` or CI.

## What this VM ran

Host: Ubuntu 24.04, Swift 6.2.1 (`swift-6.2.1-RELEASE`), x86_64. Evidence directory: `/tmp/zeus-development-NEW`.

| Command | Exit | Tests |
| --- | --- | --- |
| `swift build` | 1 | 0 run. Stopped in dependencies and `ZeusObjCGuard`: `mach/mach.h` missing, `cmath` missing, `Foundation/Foundation.h` missing. macOS-only toolchain, not a product defect. |
| `swift build --target ZeusCore` | 1 | 0 run. First diagnostic is `Sources/ZeusCore/AgentFollowUps.swift:1` `no such module 'Darwin'` (892 repeats of that diagnostic). macOS-only. |
| `swift test` | 1 | 0 run, 0 failed, 0 skipped. Same compile stop as `swift build`. |
| `./tools/check.sh development --output /tmp/zeus-development-NEW` | 1 | Gate `result.json` totals **1118 tests / 12 suites**, counted only on checks the runner marked passed. Status `failed`. |

Passed development checks (test count is the runner's):

| Check | Tests | Result |
| --- | ---: | --- |
| closed-loop-selftests | 463 | passed (`Ran 463 tests` / `OK`) |
| portable-polyglot | 66 | passed |
| portable-regressions | 76 | passed |
| portable-presentation | 33 | passed |
| portable-recordly-geometry | 31 | passed |
| portable-wiki-relationships | 26 | passed |
| portable-buddy | 20 | passed |
| portable-dictation-insertion | 17 | passed |
| portable-keychain | 9 | passed |
| portable-explanation | 176 | passed |
| portable-pointing | 185 | passed |
| release-mocks | 16 | passed |

Failed development checks, from the suite logs (the runner stores `tests: 0` when xUnit is missing):

| Check | Log | Notes |
| --- | --- | --- |
| portable-scribe | `450 tests in 26 suites failed with 1 issue` | 449 `✔ Test` lines, 1 failing test. That test passed when rerun alone. |
| portable-socket-safety | `59 tests in 4 suites failed with 56 issues` | 17 distinct tests failed, 43 recorded a pass. |
| portable-wiki-export | signal 11 after 15 `✔ Test` lines | No suite summary. Isolated replay of the health-word pattern did not crash. |
| portable-equaliser | compile error | `EqualiserDSP.swift:1` `import Darwin`. |
| portable-bridge-transport | compile error | `zeus-bridge/main.swift:146` calls `PeerSigning.captureOwnIdentity()`, which exists only inside `#if canImport(Darwin)`. |

Native fixture rows are `not-run` in development mode. That is the runner's split, not a skip count inside a suite. No Swift Testing summary in the passed logs reported a skipped test.

PR heads inspected read-only, SHAs match the open pulls: #33 `6b65a7a5`, #39 `4fe1e8ed`, #40 `267614ae`, #41 `cf307002`, #42 `08e09710`, #43 `a82cb9c0`, #44 `2ceeeacd`, #45 `f70ea17f`, #46 `f71176af`, #47 `5b85d610`, #48 `1ba23ae6`, #49 `10bf928d`, #50 `eb977a9b`, #51 `709f8b07`, #52 `762d5e47`, #53 `30253774`.

Journeys reviewed: top bar gestures, Murmur / Right Command, Right Option talk, Scribe manual start, glass settings and the 12 section slots, face presence, companion turn and orb, voice providers, Sparkle-style updates, license, permissions. Rows below are the defects with a file citation. Journeys with no row were read and did not yield a defect that met the evidence bar.

## Ledger

| ID | Severity | Area | Branch / PR | File:line | Repro or failing test | Evidence | Suggested fix scope | Owning PR |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| ZB-026 | P0 | Top bar music | integration `2722dcb7` | `Sources/Zeus/TopBar/HomeWidgetViews.swift:86-87`; `Sources/Zeus/TopBar/MusicPlayerFeed.swift:127-138` | Home Play calls `musicCommand(.playPause)`. `MusicPlayerFeed.send` returns false unless that player is already running, and the comment says a tap never launches one. The command closure is a no-op until `NowPlayingHub.attach` (`NowPlayingHub.swift:73`, default `TopBarModel.swift:234`). Device playback was not run on this VM. | PROVEN | Make Play start playback, or show a recoverable error when the player is not running. Owner branch `zeus-bot/media-playback-control`. | `zeus-bot/media-playback-control` |
| ZB-001 | P0 | Face approval | #48 `1ba23ae66127` `zeus-bot/settings-faceid` | `Sources/ZeusCore/Settings/Sections/FaceID/FaceVerificationMachine.swift:210-224` | `tests/bug-repros/FaceLockoutBypass.sh` exits 1. After 5 failures the machine is `.lockedOut` with grant nil; `fallbackResult(succeeded: true)` for the action already open sets phase `.idle`, writes a local-auth grant, and zeroes `failures`. | PROVEN | Reject `fallbackResult` while `lockActive` or phase is `.lockedOut`. Keep the open action from approving during lockout. The existing test uses a different action, so it stays locked. | #48 |
| ZB-002 | P1 | Weather | #42 `08e09710f41b` `zeus-bot/settings-weather` | `Sources/ZeusCore/Settings/Sections/Weather/WeatherTemperatureUnit.swift:23` and `:31` | `tests/bug-repros/WeatherTemperatureOverflow.sh` exits 1. `degrees(celsius: 1e20)` traps: `Double value cannot be converted to Int because the result would be greater than Int.max` (signal 132). Same `Int(value.rounded())` on wind. | PROVEN | Use `Int(exactly:)` and return nil when the rounded value is out of range. Finite external forecast numbers must not trap. | #42 |
| ZB-003 | P1 | Top bar | #42 `08e09710f41b` | `Sources/Zeus/Settings/GlassShell/Sections/WeatherSettingsSection.swift:54-74` and `Sources/ZeusCore/Settings/Sections/Weather/TopBarGestureRouter.swift:14-20` | `tests/bug-repros/TopBarGesturesUnwired.sh` exits 1. The only `TopBarPointerSample` built under `Sources/Zeus` is `.trackpad` at line 74. Click, hold, and right-swipe are never sent. On integration, `NotchController.openOnClick` (`Sources/Zeus/Notch/NotchController.swift:470-479`) is a single click; `mouseDragged` (`:521-537`) is a file drag. | PROVEN | Feed down, up, hold, settle, and swipe samples from the real top bar, or stop describing those routes on the settings preview. | #42 |
| ZB-004 | P1 | IPC | integration `2722dcb7` | `Sources/ZeusCore/PeerCredentials.swift:98-114` | `tests/bug-repros/LinuxPeerIdentify.sh` exits 1 (`identify=nil` on a connected `socketpair`). Development `portable-socket-safety`: 59 tests, 56 issues, 17 tests failed, including `theKernelReportsThisProcessForAConnectedPair` and `aServerAcceptsTheOwnerUnderTheDefaultPolicy`. | PROVEN | On non-Darwin, read `SO_PEERCRED` (uid and pid). `decide` already denies a nil peer, so every accepted connection is refused wherever Darwin is unavailable. | new-PR |
| ZB-005 | P1 | Updates | #49 `10bf928d56f6` `zeus-bot/settings-autoupdate` | `Sources/Zeus/Settings/GlassShell/Sections/AutoUpdate/SignedUpdateBridge.swift:195` | Static. `accepts` returns true when `item.signingValidationStatus != .failed`. Any status other than failed, including an unchecked item, passes, and the rest of the function only requires a non-empty signature string (`:203`). | macOS-ONLY | Compare to the valid status. A present signature string is not a validation result. Needs a Mac with the updater types to execute. | #49 |
| ZB-006 | P1 | Updates | #49 `10bf928d56f6` | `Sources/Zeus/Settings/GlassShell/Sections/AutoUpdate/SignedUpdateBridge.swift:124-128` | Static. `sparkleReadyToInstall` always posts `verifyFinished(.valid)`. `UpdateSession.perform` ignores `.verify` (`UpdatesSessionModel.swift:155`). | macOS-ONLY | Post `.valid` only after reading the item's validation status. Needs the updater callback on a Mac to execute. | #49 |
| ZB-007 | P1 | Voice providers | #53 `30253774620e` `zeus-bot/voice-providers` | `Sources/ZeusCore/Providers/ProviderHTTP.swift:66-81` and `:155-157` | Static. `send` uses `URLSession.data` with no redirect delegate. `stream` cancels every redirect (`completionHandler(nil)`). A custom `URLProtocol` that returned 302 as a finished response was not followed (status stayed 302), so this VM did not execute a real HTTP redirect. `X-Goog-Api-Key` and `xi-api-key` are custom headers and are not covered by the session's Authorization stripping. | LIKELY | Give `send` the same redirect refusal as `stream`, or allow only an HTTPS redirect to the same host and drop credential headers. | #53 |
| ZB-008 | P2 | Updates | integration `2722dcb7` | `Sources/ZeusCore/Updates/UpdateAvailability.swift:15-22` | `tests/bug-repros/VersionPrereleaseParse.sh` exits 1. `ZeusVersion(parsing: "2.0.0-rc1")` is `2.0.0`. `Int($0) ?? 0` turns the rejected token into patch 0. `FeedUpdateFetcher.offer` uses this parser (`:173`). #49 adds a stricter `UpdateVersions.release` and does not replace this one. | PROVEN | Reject a component that is not entirely numeric, and reject leftover pre-release text. | new-PR |
| ZB-009 | P2 | Bridge | integration `2722dcb7` | `Sources/zeus-bridge/main.swift:146` and `Sources/ZeusCore/PeerSigning.swift:15` and `:49` | Development `portable-bridge-transport` fails to compile: `type 'PeerSigning' has no member 'captureOwnIdentity'`. The method is inside `#if canImport(Darwin)`. The call in `main.swift` is not. | PROVEN | Guard the call the same way, or give the non-Darwin branch a no-op. This is a Linux gate break; the Mac build still sees the method. | new-PR |
| ZB-010 | P2 | Gate | integration `2722dcb7` | `Sources/ZeusCore/Audio/EqualiserDSP.swift:1` and `qa/portable-core/prepare.py:143` | Development `portable-equaliser` fails before any test: `no such module 'Darwin'`. `prepare.py` says this group runs on an Apple platform only, and `qa/feature-map.json` still lists it as `kind: portable`, which development mode requires. | PROVEN | Mark the equaliser check so development does not require it on Linux, or split the pure rules from the Darwin filter. The Darwin import itself is macOS-only, not a product defect. | new-PR |
| ZB-011 | P2 | Scribe | integration `2722dcb7` | `Tests/ZeusCoreTests/ScribeAutoStartOptInTests.swift:58-62` | Full `portable-scribe` run: `aStaleStampWithAskMeIsRemovedAtLaunch` expected nil and observed `1970-01-01 00:16:40 +0000` (the stamp the test wrote, 1000). `swift test --filter aStaleStampWithAskMeIsRemovedAtLaunch` on the same package then passed. `migrate` does call `reconcile` for `.ask` (`ScribeAutoStartOptIn.swift:40-41`). | LIKELY | Reproduce under the parallel scribe package. If it only fails there, stop the suite sharing `UserDefaults` across threads. Not a deterministic opt-in logic failure on a single run. | new-PR |
| ZB-012 | P2 | Wiki export | integration `2722dcb7` | `Sources/ZeusCore/Wiki/SensitiveInfoScanner.swift:158` and `:231` | `portable-wiki-export` died with signal 11. The crashing thread is `NSRegularExpression.init` from `SensitiveInfoScanner.regex` via `wordList`. A 32-thread replay of the health-word pattern alone survived. | LIKELY | Serialize pattern compilation, or cache one expression per pattern. Re-run the wiki-export package and keep the crash report. | new-PR |
| ZB-013 | P2 | Updates | #49 `10bf928d56f6` | `Sources/ZeusCore/Settings/Sections/AutoUpdate/UpdateSession.swift:302-304` and `SignedUpdateBridge.swift:87-89` | Static. `verifyFinished` is ignored unless the state is already `.verifying`. The bridge posts `downloadFinished` and `verifyFinished(.valid)` as two unstructured tasks. If verify is applied first, the later download step stays in `.verifying` and `.verify` is a no-op. Not executed as a reorder on this VM. | LIKELY | Apply both results in one event, or queue them in order on the session actor. | #49 |
| ZB-014 | P3 | Companion | #51 `709f8b077cb5` `zeus-bot/companion-turn-machine` | `Sources/ZeusCore/Companion/CompanionTurnMachine.swift:10` | Static. `CompanionSystemClock.now` is `Date().timeIntervalSinceReferenceDate`. `exceededDeepSpokenCeiling` (`:148-152`) subtracts that from `phaseEnteredAt`. A forward wall-clock jump makes the ceiling look exceeded. Face presence documents the opposite choice (`FacePresenceMachine.swift:31-34`). | LIKELY | Pass a monotonic clock. The manual clock already covers tests. | #51 |
| ZB-015 | P3 | Top bar approvals | integration `2722dcb7` | `Sources/Zeus/Notch/NotchController.swift:352-355` | Static. The timeout `Task` is not stored. `finish` is idempotent (`:319-324`), so a late timeout does not resume twice. The task still holds the continuation until the full timeout after the person has answered. | macOS-ONLY | Keep the task and cancel it inside `finish`. Needs the AppKit approval card to execute. | new-PR |
| ZB-016 | P1 | Voice providers | #53 `30253774620e` | `Sources/Zeus/Voice/Speaker.swift:119-123` and `:201-205`; `Sources/Zeus/Voice/PluginVoiceBridge.swift:97-100` | Static. After a provider returns `.spoken`, `speakLine` returns at once. The sentence pump waits only while `chain.isPlaying` or `systemRendering`. Provider audio is an `AVAudioPlayer` outside that chain, so the next sentence can start while the previous one is still playing. `isSpeaking` (`Speaker.swift:91`) also omits that player. | macOS-ONLY | Track provider playback in the pump and in `isSpeaking`, and do not start the next line until it ends. Needs the Mac playback path to execute. | #53 |
| ZB-017 | P1 | Murmur / top bar | integration `2722dcb7` | `Sources/Zeus/App/AppDelegate.swift:174-176`; `Sources/Zeus/TopBar/TopBarModel.swift:366-370` | Static. `toggleDictation` calls `finish()` only in `.listening`, and `begin()` only when `isDictating` is false. `isDictating` is true for `.transcribing` and `.rewriting`, so the button and its accessibility action do nothing during those phases. The visible title at `TopBarViews.swift:1951` says "Typing" while the VoiceOver label at `:1968-1969` still says "Start dictation". | LIKELY | Route a press during transcribe or rewrite to `cancel()`. Match the accessibility label to the visible phase. | new-PR |
| ZB-018 | P2 | Top bar | integration `2722dcb7` | `Sources/ZeusCore/TopBar/NotchLights.swift:231-243`; `Sources/Zeus/TopBar/TopBarServices.swift:192-198` | `tests/bug-repros/ShiftPeekOnce.sh` exits 1. `fire` sets `revealed` and never clears it. `shift(down: false)` only clears `downAt`. `Sources/Zeus` has no `shiftGate.release()` call, so a second lone Shift hold cannot arm the crest. | PROVEN | Call `shiftGate.release()` when Shift goes up, and fade from that release. | new-PR |
| ZB-019 | P2 | Top bar | integration `2722dcb7` | `Sources/ZeusCore/TopBar/NotchLights.swift:246-250` | `tests/bug-repros/TabHoldUnwired.sh` exits 1. `TabHoldGate` is tested in `Tests/ZeusCoreTests/NotchLightsTests.swift` and has no reference under `Sources/Zeus`. | PROVEN | Connect Tab-down, modifiers, and release to `TabHoldGate` the way Shift is connected, or drop the unused gate. | new-PR |
| ZB-020 | P2 | Updates | #49 `10bf928d56f6` | `Sources/Zeus/Settings/GlassShell/Sections/AutoUpdate/UpdatesSessionModel.swift:49-54` and `:72-74` | Static. `appear()` calls `checkNow()` whenever automatic checks are on. `checkNow` applies `.checkRequested`. From `.downloading`, `UpdateSession.requestCheck` (`UpdateSession.swift:345-346`) emits `.cancelNetwork`, and `perform` calls `SignedUpdateBridge.cancel()` (`UpdatesSessionModel.swift:134-136`). Reopening the card during a download aborts it. | LIKELY | Do not start a new check from `appear()` while a download, verify, or install is in progress. | #49 |
| ZB-021 | P2 | Settings | #39 `4fe1e8edb158` `zeus-bot/settings-general` | `Sources/Zeus/Settings/GlassShell/Sections/GeneralSettingsSection.swift:243-251` | Static. Reset walks `SettingsCatalog.all` only. `general.backgroundBlur` is a `GeneralSectionSlot` contribution (`GeneralSectionSlot.swift:5`) and is not in `SettingsCatalog.swift` on that commit. | LIKELY | Include the section's own key contributions in the reset, or say on the card which keys stay. | #39 |
| ZB-022 | P2 | Companion orb | #52 `762d5e474965` | `Sources/ZeusCore/Companion/OrbSimulation.swift:445-456` | Static. Each spawn appends `electronSpawnTimes` and `electronSpawnSpeeds`. `electrons` is replaced with the ones still travelling (`:450-456`). The two metadata arrays are cleared only in `init` (`:247-248`) and are never trimmed. | LIKELY | Drop metadata for electrons that have finished, or stop keeping a parallel log. | #52 |
| ZB-023 | P2 | Voice providers | #53 `30253774620e` | `Sources/Zeus/Voice/PluginVoiceBridge.swift:21-40` | Static. Each WAV playback appends a started `AVAudioEngine` to `engines` and writes a temp file. Nothing stops the engine, removes it, or deletes the file. | macOS-ONLY | Stop and drop the engine when the file finishes, and remove the temp file. Needs AVFoundation on a Mac to execute. | #53 |
| ZB-024 | P2 | License | integration `2722dcb7` | `Sources/Zeus/App/LicenseManager.swift:163-165` and `:181-183`; `:260-265` | Static. Activation writes `license.activation` before `license.key`. A failed key write returns an error and leaves the proof in place. On a server refusal, a failed `credentials.remove("license.key")` keeps the key; `license.activationRejected` is only a `UserDefaults` flag (`LicenseEngine.swift:53-54`). | macOS-ONLY | Write the key and the proof together, or roll back the proof when the key write fails. Keep the refusal flag with the key, not only in defaults. Needs Keychain to execute. | new-PR |
| ZB-025 | P2 | License | integration `2722dcb7` | `Sources/ZeusCore/License/LicenseEngine.swift:69-72` | Static. `isRevoked` returns false when the stored list is missing or `SignedBlob.decode` fails. A revoked key then evaluates as licensed until a later fetch writes a list that decodes. | LIKELY | Treat an undecodable list as unknown and keep the last good revocation result, or fail closed for a key that already has a revocation record. | new-PR |

## Counts

| Severity | PROVEN | LIKELY | macOS-ONLY | Total |
| --- | ---: | ---: | ---: | ---: |
| P0 | 2 | 0 | 0 | 2 |
| P1 | 3 | 2 | 3 | 8 |
| P2 | 5 | 7 | 2 | 14 |
| P3 | 0 | 1 | 1 | 2 |
| Total | 10 | 10 | 6 | 26 |

ZB-010 is PROVEN as a gate failure. The Darwin import it trips on is not, by itself, a product defect.

## How to run a red repro

From the repository root, with Swift 6.2 on `PATH` and the named commits fetched:

```sh
tests/bug-repros/FaceLockoutBypass.sh
tests/bug-repros/WeatherTemperatureOverflow.sh
tests/bug-repros/TopBarGesturesUnwired.sh
tests/bug-repros/LinuxPeerIdentify.sh
tests/bug-repros/VersionPrereleaseParse.sh
tests/bug-repros/ShiftPeekOnce.sh
tests/bug-repros/TabHoldUnwired.sh
```

Each exits 1 while its bug is present. They are not part of `swift test`.
