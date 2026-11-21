# Sweep 11 — packaging, bundle integrity, and stress

Read-only hunt of `codex/integration-20261111` at `2722dcb7497d5415fbc1fcb1f65c49629966a281` and the open `zeus-bot/*` heads fetched from origin. The bug ledger on `zeus-bot/bug-ledger` (PR #54) at `255e52aba94234e2b194fd81b2cf4b93e628cc93` was read first. This branch adds two documents and changes no build, CI, or Package.swift file.

The Mac app was not signed or launched here. The host is Linux, so `codesign`, `PlistBuddy`, and a macOS Swift SDK were not available. Line citations below are from the named commit. The runnable Mac procedure is `qa/sweeps/stress-matrix.md`.

## Counts

| | |
| --- | ---: |
| Findings | 13 |
| P0 | 0 |
| P1 | 3 |
| P2 | 10 |
| P3 | 0 |
| Duplicate of a ledger row | 1 (S11-06, ZB-008) |
| New | 12 |
| Stress rows | 8 |

## What holds

On integration `2722dcb7497d5415fbc1fcb1f65c49629966a281`:

- Bundle id `app.zeus.mac` (`Resources/Info.plist:8`). Minimum system `14.2` (`Resources/Info.plist:21-22`) matches `Package.swift:5`.
- `LSUIElement` is true (`Resources/Info.plist:23-24`). The process is also described as menu-bar-only at `Sources/Zeus/App/main.swift:104`.
- Usage strings are present for the microphone, system audio, camera, speech recognition, local network, calendars, location when in use, Focus, and reminders (`Resources/Info.plist:27-50`). Bonjour lists `_zeus-fling._tcp` (`Resources/Info.plist:37-40`), the same type as `Sources/ZeusFling/FlingEndpoint.swift:109`.
- The entitlements file grants the camera, audio input, and Apple Events (`Resources/Zeus.entitlements:7-14`). Sandbox is explicitly off (`Resources/Zeus.entitlements:5-6`).
- `scripts/bundle.sh:75-79` signs every helper and the app with the hardened runtime. An ad-hoc or local identity omits the secure timestamp (`scripts/bundle.sh:32-33`). `RELEASE=1` refuses a missing or ad-hoc identity (`scripts/bundle.sh:16-18`). `scripts/verify-release-signature.sh:6-16` checks Developer ID, team id, timestamp, and the runtime flag on the app and `Contents/Helpers`.
- `scripts/package.sh:37` puts a symlink inside the disk image. It does not copy the app into `/Applications`. `scripts/install.sh` is the command that writes an installed copy, and its default destination is `/Applications/Zeus.app` (`scripts/install.sh:7-8`).
- `LICENSES/jarvis2.0-LICENSE` is absent on this commit, so an integration bundle cannot contain it.

Heads read for packaging diffs, with no extra finding: `zeus-bot/ipc-hardening` `f11b2a4277e4ab7e6d477a6d5fa3c117c71684e0` sets each helper's codesign identifier to its filename. `zeus-bot/canopy-parity` `2c4431915d8ef9d2c4fc62594ac36fe37b3bcb87` drops `_zeus-fling._tcp` from the plist together with the fling sources, so those two lists still match. The resource binary that head adds is S11-12.

## Ledger check

| Ledger | On the current head | This sweep |
| --- | --- | --- |
| ZB-005, ZB-006 | `zeus-bot/settings-autoupdate` `4ada39309d863dcc63b35241f3d77392d4ff2fcb`. `UpdateVerification.allows` accepts only `.valid` (`Sources/ZeusCore/Settings/Sections/AutoUpdate/UpdateSession.swift:150-152`). `SignedUpdateBridge.accepts` uses that (`Sources/Zeus/Settings/GlassShell/Sections/AutoUpdate/SignedUpdateBridge.swift:193-196`). `sparkleReadyToInstall` posts the stored trust (`SignedUpdateBridge.swift:125-127`). | Not refiled. |
| ZB-020 | The same head. `startsCheckOnAppear` stays false while downloading, verifying, or installing (`UpdateSession.swift:299-306`). | The download path is guarded. The ready-to-install path is S11-05. |
| ZB-008 | Still on integration. `ZeusVersion.init(parsing:)` turns a non-numeric token into 0 (`Sources/ZeusCore/Updates/UpdateAvailability.swift:15-22`). | S11-06, duplicate of ZB-008. Owner remains #60. |
| ZB-024, ZB-025 | License keychain and revocation. | Outside this lens. |

## Findings

| ID | Severity | Area | Duplicate | Branch / SHA | File:line |
| --- | --- | --- | --- | --- | --- |
| S11-01 | P1 | Privacy | | integration `2722dcb7497d5415fbc1fcb1f65c49629966a281` | `Resources/Zeus.entitlements:5-14`; `scripts/bundle.sh:78`; `Sources/Zeus/Onboarding/OnboardingServices.swift:196`; `Sources/Zeus/Proactive/ProactiveController.swift:81` and `:141`; `Sources/Zeus/App/PermissionsModel.swift:90-92` |
| S11-02 | P2 | Privacy | | integration `2722dcb7497d5415fbc1fcb1f65c49629966a281` | `Resources/Info.plist:27-50`; `Sources/Zeus/Screen/ScreenCapture.swift:10`; `Sources/Zeus/Polyglot/PolyglotAudio.swift:96`; `Sources/Zeus/App/PermissionsModel.swift:208` |
| S11-03 | P2 | Packaging | | integration `2722dcb7497d5415fbc1fcb1f65c49629966a281` | `scripts/bundle.sh:44-46` |
| S11-04 | P1 | Updates | | `zeus-bot/settings-autoupdate` `4ada39309d863dcc63b35241f3d77392d4ff2fcb` (PR #49) | `Package.swift:24` and `:38`; `Sources/ZeusCore/Settings/Sections/AutoUpdate/UpdateSession.swift:40-41` and `:69-78`; `scripts/bundle.sh:43`; `NOTICES.md:6-18` |
| S11-05 | P2 | Updates | | same head as S11-04 | `Sources/ZeusCore/Settings/Sections/AutoUpdate/UpdateSession.swift:299-306` and `:387-390` |
| S11-06 | P2 | Updates | duplicate of ZB-008 | integration `2722dcb7497d5415fbc1fcb1f65c49629966a281` | `Sources/ZeusCore/Updates/UpdateAvailability.swift:15-22` and `:173` |
| S11-07 | P2 | Packaging | | integration `2722dcb7497d5415fbc1fcb1f65c49629966a281` | `Resources/Info.plist:17-20`; `scripts/bundle.sh:43`; `Sources/Zeus/App/UpdateCoordinator.swift:23`; `Sources/Zeus/Settings/GSAboutPage.swift:22-24` |
| S11-08 | P2 | Packaging | | integration `2722dcb7497d5415fbc1fcb1f65c49629966a281` | `scripts/bundle.sh:30-33` and `:59-64`; `scripts/install.sh:8`; `.gitignore:6` |
| S11-09 | P2 | QA | | integration `2722dcb7497d5415fbc1fcb1f65c49629966a281` | `scripts/pointing-selftest.sh:8` and `:33`; `scripts/voice-selftest.sh:33` and `:39`; `scripts/trusted-ax-journey.sh:16`; `scripts/human-qa.sh:18`; `scripts/silent-eval.sh:4` and `:10`; `scripts/check-perf-budget.sh:11`; `scripts/call-ax-probe.swift:347`; `qa/closed-loop/trusted_ax.py:176`; `Sources/Zeus/Voice/KokoroWorker.swift:16-19` |
| S11-10 | P2 | Licensing | | integration `2722dcb7497d5415fbc1fcb1f65c49629966a281` | `scripts/bundle.sh:44-46`; `Sources/Zeus/Settings/GSAboutPage.swift:33`; `NOTICES.md:15` and `:52`; `Resources/NOTICES.txt:15` and `:65` |
| S11-11 | P1 | Licensing | | `zeus-bot/companion-persona-orb` `665b9167303f9596d5222b77a663e36f780d60d7` (PR #52) and `zeus-bot/topbar-idle-black` `69f74b2f03ee5bba1259794012e76ffba334327f` (PR #85) | `LICENSES/jarvis2.0-LICENSE:5-12`; `scripts/bundle.sh:46`; `Resources/NOTICES.txt:817-818` |
| S11-12 | P2 | Signing | | `zeus-bot/canopy-parity` `2c4431915d8ef9d2c4fc62594ac36fe37b3bcb87` (PR #73) | `scripts/bundle.sh:49` and `:81-82` and `:95`; `scripts/verify-release-signature.sh:6` |
| S11-13 | P2 | Notifications | | integration `2722dcb7497d5415fbc1fcb1f65c49629966a281`; `zeus-bot/approval-queue` `c4662bf52d8b19030bc7da401171afcb0bf62b96` (PR #14); `zeus-bot/hub-04-decision` `7c000d3a8d5882593e3a1bf34afd98ae4b3be2f6` (PR #70) | `Sources/ZeusCore/Alerts/AlertStack.swift:49` and `:77-93`; `Sources/Zeus/App/SystemNotificationService.swift:212-221`; `Sources/Zeus/Notch/NotchController.swift:313-315` on integration; `Sources/Zeus/Notch/NotchController.swift:317` and `:343` on #14; `Sources/ZeusCore/AgentHub/HubDecision.swift:111` on #70 |

### S11-01 — calendar and location have no hardened-runtime entitlement

`scripts/bundle.sh:78` signs the app with `--options runtime` for every identity, including ad-hoc. The entitlements that travel with that signature are sandbox off, camera, audio input, network client, and Apple Events. Calendar and reminder calls use `EKEventStore.requestFullAccessToEvents` and `requestFullAccessToReminders`. Location onboarding calls `CLLocationManager.requestWhenInUseAuthorization`. No open `zeus-bot` head adds `com.apple.security.personal-information.calendars` or `com.apple.security.personal-information.location`. A hardened build can receive the usage-string prompt and still be refused by the runtime. Owning area: Privacy.

### S11-02 — screen capture has no usage string

Screen capture is preflighted and requested (`CGPreflightScreenCaptureAccess`, `CGRequestScreenCaptureAccess`, `SCStream`). `Resources/Info.plist` has no `NSScreenCaptureUsageDescription`. A search of every open `zeus-bot` head found the same absence. The prompt itself was not executed on this host. Owning area: Privacy.

### S11-03 — no privacy manifest is copied into the bundle

No `PrivacyInfo.xcprivacy` exists on integration or on any open `zeus-bot` head. `scripts/bundle.sh:44-46` copies the icon, logos, menu-bar images, and `NOTICES.txt`. Notarization was not submitted from this host. Owning area: Packaging.

### S11-04 — Sparkle 2 is linked, and its feed keys are not in the bundle

PR #49 links Sparkle 2 at exact pin 2.10.1 (`Package.swift:24` and `:38`). Configuration is read from the host Info.plist keys `SUFeedURL` and `SUPublicEDKey` (`UpdateSession.swift:40-41`). A configured updater requires an HTTPS feed and a public key that decodes to 32 bytes (`UpdateSession.swift:69-78`). A longer value is ignored. The Info.plist on that head is unchanged from integration, and `scripts/bundle.sh:43` only adds `ZeusBuildStamp`. Nothing in that head's scripts copies the framework or its XPC services into `Contents/Frameworks`. `NOTICES.md:17-18` says the public key is read from the host plist and that nothing is published from the tree. No key bytes are in the repository, and none are printed here. The attribution added in `NOTICES.md:6-18` is not in `Resources/NOTICES.txt`, which is the file the bundle copies. Owning area: Updates.

### S11-05 — a ready update is discarded when the card appears

On the same head, appearing during a download, a verify, or an install does not start a check. Appearing while the state is ready to install falls through to the default and `requestCheck` emits `discardStagedUpdate` plus a new fetch (`UpdateSession.swift:387-390`). ZB-020's download path is guarded on this sha, so this row is the remaining path. Owning area: Updates.

### S11-06 — duplicate of ZB-008

`ZeusVersion(parsing:)` keeps the first three dot-separated pieces and replaces a piece that is not an integer with 0. `FeedUpdateFetcher.offer` uses that parser for the version in the feed JSON (`UpdateAvailability.swift:173`). The integration feed documents that it carries no signature (`UpdateAvailability.swift:119-121`) and that the download link is opened in the browser. PR #60 remains the owner. Owning area: Updates.

### S11-07 — the shipped version stays 0.1.0 (1)

`CFBundleShortVersionString` is `0.1.0` and `CFBundleVersion` is `1`. The bundle script adds `ZeusBuildStamp` as a timestamp and the process id. About (`GSAboutPage.swift:22-24`) and the update coordinator (`UpdateCoordinator.swift:23`) read the short version. On PR #49, `UpdatesSessionModel` also takes the current release from `CFBundleShortVersionString`. A newer binary still compares as `0.1.0`. Owning area: Packaging.

### S11-08 — an ad-hoc Desktop build is a hand procedure

`SIGN_IDENTITY=- scripts/bundle.sh` signs ad hoc, with the hardened runtime and no timestamp, and writes `build/Zeus.app`. That command does not write `/Applications`. Copying the result with `ditto` to `~/Desktop/Zeus-latest-<sha8>.app` is the path that keeps the installed copy untouched. No script in the repository names that Desktop path. `scripts/install.sh` with no arguments installs to `/Applications/Zeus.app` and must stay unused for this build.

Two gaps sit in front of a clean run. `extension/dist` is gitignored (`.gitignore:6`) and is not in the tree. When `npm` is absent, `scripts/bundle.sh:59-61` skips the extension build and `scripts/bundle.sh:64` still copies `extension/dist`, so the script exits before signing. The signed app keeps bundle id `app.zeus.mac` and version `0.1.0`, so Launch Services and the privacy grants are shared with any other Zeus of that id, and the filename's sha is only on the folder name.

This host did not run the procedure. The commands, and the checks after them, are the preamble of `qa/sweeps/stress-matrix.md`. Owning area: Packaging.

### S11-09 — QA entry points assume one home directory layout

These paths are baked in, and a Desktop build from S11-08 will not be found by them:

- `scripts/pointing-selftest.sh:33` and `scripts/voice-selftest.sh:33` take the newest app under `~/AI-Brain-build/zeus-qa-*/app*/Zeus.app`.
- `scripts/voice-selftest.sh:39`, `scripts/human-qa.sh:18`, `scripts/trusted-ax-journey.sh:16`, `scripts/call-ax-probe.swift:347`, and `qa/closed-loop/trusted_ax.py:176` write or build under `~/AI-Brain-build`.
- `scripts/silent-eval.sh:4` and `:10` default to `~/dev/zeus-wt/glance-clone-proof`.
- `scripts/check-perf-budget.sh:11` looks for a process whose path contains `zeus-wt/topbar/build/Zeus.app`. The one-hour idle row in the stress matrix has to pass `PID` explicitly.
- `Sources/Zeus/Voice/KokoroWorker.swift:16-19` looks for the model and the Python executable under `~/AI-Brain-build/jarvis-laya-backend` before the managed folder at `KokoroWorker.swift:78-80`.

Owning area: QA.

### S11-10 — About ships a notices file that lags the repo notices

`scripts/bundle.sh` copies `Resources/NOTICES.txt`. About reads that resource (`GSAboutPage.swift:33`). `NOTICES.md:15` starts the speech-to-text section and `NOTICES.md:52` starts the text-to-speech section. `Resources/NOTICES.txt:15` is still the brand-mark section, and Kokoro is one line at `Resources/NOTICES.txt:65`. The Apache and MIT texts for the compiled-in packages are present later in the shipped file (`Resources/NOTICES.txt:138`). The speech and voice sections the repo file added are not what About shows. Owning area: Licensing.

### S11-11 — the ported license grant is personal and non-commercial, and two heads copy it into the app

`LICENSES/jarvis2.0-LICENSE` on PR #52 and PR #85 is the same blob. Lines 5-12 limit the grant to personal, educational, and non-commercial use, and say commercial use needs a separate license. No key material is in the file. `scripts/bundle.sh:46` on both heads copies that file into `Contents/Resources`. `Resources/NOTICES.txt:817-818` on both heads says the same text ships in the bundle. Integration does not contain the file. Owning area: Licensing.

### S11-12 — the release check skips the extra resource binary

PR #73 compiles `Contents/Resources/zeus-now-playing` (`scripts/bundle.sh:49`) and signs it with the hardened runtime (`scripts/bundle.sh:81-82`) before the outer signature. `scripts/verify-release-signature.sh:6` still walks the app and `Contents/Helpers` only. The local-identity cdhash list on that head (`scripts/bundle.sh:95`) also walks helpers only. A release can pass the script while that resource binary lacks a Developer ID, a timestamp, or the runtime flag. `codesign --verify --deep --strict` still runs on the outer bundle (`scripts/bundle.sh:85`). Owning area: Signing.

### S11-13 — the queues a 1,000-item run would fill have no cap, except the notification mirror

`AlertStack.maxVisible` is 3. `AlertStack.post` inserts every distinct item and never drops one (`AlertStack.swift:77-93`). Outgoing banners use a fresh identifier unless the payload sets a replacement (`SystemNotificationService.swift:212-221`). On integration, approval requests serialize on one card and wait (`NotchController.swift:313-315`). On PR #14, `pendingApprovals` is appended with no limit (`NotchController.swift:317` and `:343`). On PR #70, `HubDecision` appends to `waiting` with no limit (`HubDecision.swift:111`). The incoming notification mirror reads at most 40 rows (`Sources/Zeus/TopBar/TodayController.swift:237`, calling `NotificationMirror.recent` whose default limit is 30 at `Sources/ZeusCore/TopBar/NotificationMirror.swift:40`). The stress row ST-03 measures these bounds. Owning area: Notifications.

## Ad-hoc build, short answer

On a Mac, `SIGN_IDENTITY=- scripts/bundle.sh` followed by `ditto` to `~/Desktop/Zeus-latest-<sha8>.app` produces an ad-hoc, hardened-runtime app and does not touch `/Applications`, provided `npm` can build the extension or `extension/dist` is already present. This host did not produce that app. The filename sha is not written into `CFBundleShortVersionString` or `CFBundleVersion`.
