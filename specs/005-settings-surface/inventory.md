# Settings surface inventory

**Feature Branch**: `005-settings-surface`

**Created**: 2026-11-20

**Status**: Draft

**Input**: Tony, 2026-11-20. Zeus keeps every setting it has on `codex/integration-20261111` and gains the sections below. The settings chrome is redrawn in Zeus's own liquid-glass language (translucent material, depth, soft highlights, motion that follows Reduce Motion). Clean-room: the closed-source reference is not named, and none of its code or assets is copied.

**Read at**:

- Current settings: `origin/codex/integration-20261111` at `2722dcb`. Line numbers for Zeus files are from that tree.
- Contracts: `origin/zeus-bot/notch-parity` at `dfd1179`, `specs/004-notch-parity/spec.md` (R-001 to R-025, prior art) and `tasks.md`.
- Decisions: the D-labels that exist on that branch, listed below. D8 and D9 are not in the branch.
- Earlier public work: `origin/zeus-bot/canopy-parity` at `2c44319`.
- Open copy PR: #22, `origin/zeus-bot/settings-plain` at `ff33ee3`.
- Permission branch (no open PR): `origin/zeus-bot/settings-permissions` at `e4ea25d`.

A setting is listed under a target section only when an R-contract or a D-decision names it. Anything else the section might need is **UNSPECIFIED**. This inventory does not invent a key, a type, or a default.

## How a task is done

A plan item is done only when the red test named in `plan.md` has been run and the result is recorded. This commit runs none of them.

## 1. Target sections

Tony's sections, in the order he named: Media, General, Portal, Sensory, Battery, Focus, Weather, Lock Screen, Face ID, Accessory, License, Auto-update.

`spec.md:74` asks for one place per feature, plain labels, and sensible defaults. `spec.md:166` (FR-004) asks for one plain row per contract, and a held row that says "not available yet". Where the contract names the row's words and does not name the key, the words are recorded and the key, type, and default are UNSPECIFIED.

### Decisions D0 to D9

| Id | Where it is | What it decides for settings |
| --- | --- | --- |
| D0 | `docs/NOTCH-DRAWN-NOTCH-PLAN.md:17` and `:174` | One closed-shape value. No new setting. Same pixels. |
| D1 | same file `:18` and `:225` | Drawn-shape limits and calibration. No settings card. |
| D2 | same file `:19` and `:284` | Drawn shape on a notchless display. No new key. |
| D3 | same file `:20`, `:337`, and the key table `:494-496` | Card "Displays without a notch": Shape, Width, Height. `notch.displays` stays on General (`:499`). |
| D4 | same file `:21`, `:376`, and `:497` | Position slider for the drawn shape. |
| D5 | `docs/NOTCH-OUTPUT-PLAN.md:547` and `:72` | Service discovery is still an owner choice. Three options are written there. No setting is selected. |
| D6 | `docs/MEETING-START-PLAN.md:173` | Reduce Transparency on the meeting card. Not a settings-section decision. |
| D7 | `docs/MEETING-START-PLAN.md:176` | One status line on the meeting card. Not a settings-section decision. |
| D8 | Not on `origin/zeus-bot/notch-parity` as a decision id | The system-source plan's owner item 8 (`docs/NOTCH-SYSTEM-SOURCE-PLAN.md:533`) is a different list, and R-014 holds that route (`spec.md:43`, `spec.md:132`). |
| D9 | Not on `origin/zeus-bot/notch-parity` as a decision id | The system-source plan's owner item 9 (`docs/NOTCH-SYSTEM-SOURCE-PLAN.md:534`) is the same other list. |

Prior art for the contracts is `spec.md:134-145`. It names licences and projects. It names no settings key.

### Media

| What the contract requires | Source | Key, type, default |
| --- | --- | --- |
| Shuffle and repeat. Repeat-one stays hidden for the player that has no such mode. No script without Automation consent. A script older than 3 s is abandoned. | `spec.md:30`, `spec.md:167` | UNSPECIFIED |
| Lyrics ladder and the distinct failure state. A failure is not cached as a miss. The wait honours Retry-After and adds jitter. | `spec.md:31`, `spec.md:168` | UNSPECIFIED as a Media key. The current lyrics switch is `privacy.lyrics` (section 2). |
| Word-by-word highlight, a whole-line fallback setting, and a macOS 14 fallback. | `spec.md:32` | `lyrics.wordByWord` is the named key (`spec.md:32`, catalog line 57). The whole-line fallback key, type, and default are UNSPECIFIED. The macOS 14 fallback is behavior, not a named key. |
| Keep the display awake only while music plays, inside the existing battery and heat rules. | `spec.md:33` | UNSPECIFIED as a Media key. The current switch is `keepAwake.whileMusic` on General (catalog line 12). |
| Open-on-click. Collapse on pause: instant, delay, or never. | `spec.md:34` | The three collapse words are specified. The key, which choice is the default, and the open-on-click key are UNSPECIFIED. |
| Several readers, one active, with pinning. The system-wide reader stays out. | `spec.md:39` | UNSPECIFIED. Current related key: `music.follow` (catalog line 81). |
| Browser media through the extension Zeus already ships: play, pause, seek. | `spec.md:40` | UNSPECIFIED as a new key. Current key: `music.browserMedia` (catalog line 141), default `false`. |
| Exact word times when the file already has them. | `spec.md:41` | No setting. A parser only. |
| Per-app EQ and volume on the public tap. Exclude Zeus and call apps. Rebuild on device change. No orphan mute. A denial banner. No new entitlement. | `spec.md:42` | UNSPECIFIED as a new key. Current key: `audio.equaliser` (catalog line 105), default `false`. |
| System-wide now playing. Held. The row says "not available yet". The private framework is not used. | `spec.md:43`, `spec.md:132`, `spec.md:166` | The row text is specified. The key is UNSPECIFIED. |
| Animated artwork. Held. The row says "not available yet". | `spec.md:53`, `spec.md:132` | The row text is specified. The key is UNSPECIFIED. |

Output-device icons (R-008, `spec.md:37`) are a list and a public icon map, not a named settings key. UNSPECIFIED as a Media setting. D5 (`NOTCH-OUTPUT-PLAN.md:547`) does not choose a discovery setting.

### General

| What the contract or decision requires | Source | Key, type, default |
| --- | --- | --- |
| Light appearance for Settings. | `spec.md:49` (R-021) | UNSPECIFIED as a new key. The current row is `general.windowTheme` (catalog line 8): choice System / Light / Dark, default `Dark`, state stub. The live light palette is UNSPECIFIED. |
| `notch.displays` stays on General. The pill sentence is removed. The control is unchanged. | D3, `docs/NOTCH-DRAWN-NOTCH-PLAN.md:499` | Current key `notch.displays` (catalog line 9): choice, default `Built-in display`. Wave 1 also says every connected display gets a bar (`spec.md:63-67`). How that interacts with the stored default is UNSPECIFIED. |
| One plain row for setup inside the notch. Held. The row says "not available yet". | `spec.md:52`, `spec.md:132`, `spec.md:166` (R-024) | The section for this row is UNSPECIFIED. The row text is specified. The key is UNSPECIFIED. |

D0, D1, and D2 add no General setting. Drawn-notch Shape, Width, Height, and Position stay on Appearance (D3 and D4, catalog lines 41-44). They are existing settings, re-hosted, not new General keys.

### Portal

No R-contract and no D0-D9 decision names a Portal setting. **UNSPECIFIED.**

The license portal program exists (`portal/README.md` on `dfd1179`). `license.server` is stored by `Sources/Zeus/App/LicenseManager.swift` and read from `Sources/Zeus/App/SettingsLicensePane.swift`. Neither file is an R-contract or a D-decision, so this inventory does not turn that URL into a Portal setting.

### Sensory

No R-contract and no D0-D9 decision names a Sensory setting. **UNSPECIFIED.**

Reduce Motion is the system setting the shell follows (`Sources/Zeus/App/Preferences.swift:76-82`). It is not a Zeus Sensory key.

### Battery

| What the contract requires | Source | Key, type, default |
| --- | --- | --- |
| Earbud battery and listening mode. One setting, off by default, fails closed. Probe the battery keys and the listening-mode property. Hide a control the device does not have. Unknown rather than 0. Read back after every set. Fail closed if the symbol is missing. Bluetooth usage string and prompt only while the setting is on. | `spec.md:44`, `spec.md:80`, `spec.md:123`, `tasks.md:67` | The contract describes one setting for R-015 and R-016. The key and the title are UNSPECIFIED. Default: off (`spec.md:80`). Splitting battery and listening mode across Battery and Accessory is UNSPECIFIED. |

R-004's battery and heat rules (`spec.md:33`) constrain the music awake hold. They do not name a Battery key. The current floor is `keepAwake.batteryFloor` (section 2.3), which stays an existing key.

### Focus

| What the contract requires | Source | Key, type, default |
| --- | --- | --- |
| Focus name. Public Focus filter first. The store file is a second path, only if Tony opts in, with a plain-label fallback. Off by default. Off shows nothing and reads nothing. | `spec.md:45`, `spec.md:80`, `spec.md:125`, `tasks.md:69` | The feature key and the opt-in key are UNSPECIFIED. Both default off. |

D6 and D7 do not add a Focus setting.

### Weather

No R-contract and no D0-D9 decision names a Weather setting. **UNSPECIFIED.**

Existing weather controls stay where they are (section 2): `home.variant.weather`, `lights.rain`, `topBar.weatherCity`, `topBar.celsius`, `perm.location`.

### Lock Screen

| What the contract requires | Source | Key, type, default |
| --- | --- | --- |
| Own setting, off by default, fails closed. If the symbol does not load, the card is not shown. A new window for each lock. After unlock, clicks are not swallowed. The setting includes "read-only, no controls". | `spec.md:46`, `spec.md:80`, `spec.md:124`, `tasks.md:68` | The key is UNSPECIFIED. Default: off. The read-only choice is specified. Its key and default are UNSPECIFIED. |

`docs/NOTCH-LOCK-SCREEN-PLAN.md:507-525` lists choices the owner still owes (track details, placement, a clock row, and others). Those are not D0-D9 and they are not decided, so they are not settings in this inventory.

### Face ID

The section title is Tony's. `spec.md:115` requires the product to say that macOS has no Face ID and that an app cannot unlock the Mac login screen by itself.

| What the contract requires | Source | Key, type, default |
| --- | --- | --- |
| Camera face verification for a Zeus approval, with Touch ID or `LocalAuthentication` as the fallback. On-device only. | `spec.md:51`, `spec.md:82-86`, `spec.md:170` | The approval key is UNSPECIFIED. Wave 2 default is off (`spec.md:80`). |
| One switch stops the camera and refuses face approval. | `spec.md:111` | Whether this switch is a new key or the existing `face.presence` switch is UNSPECIFIED. |
| Optional camera presence: lock when away, wake when back. Default off. A plain explanation of the camera permission. | `spec.md:115` | Current keys, already off: `face.presence` (catalog line 143, default `false`) and `face.lockAfter` (catalog line 144, default `2 minutes`). The contract does not name the durations. |
| Enrolment stores only an encrypted template. Liveness is required. Camera permission denied, low light, too far, covered, and timeout each have a sentence and the fallback. After N failures the check locks. N is set in the red test. | `spec.md:103-113` | These are behaviors. No additional settings key is named. |
| The fuller unlock, if built, stores the login password only in the Keychain behind biometric or user-presence access control. | `spec.md:115` | UNSPECIFIED. "If built" names no key. |

Camera permission already exists (`spec.md:51`, `spec.md:113`). No new entitlement.

### Accessory

| What the contract requires | Source | Key, type, default |
| --- | --- | --- |
| Speaker names. Own setting, off. Off does not browse. Local Network usage string for this contract only. | `spec.md:47`, `spec.md:80`, `spec.md:126`, `tasks.md:70` (R-019) | The key is UNSPECIFIED. Default: off. |
| Listening mode. | `spec.md:44` (R-016) | Not a second key. It is the same setting as Battery's R-015/R-016 row. Which section shows it is UNSPECIFIED. |

D5 does not select a discovery setting (`docs/NOTCH-OUTPUT-PLAN.md:547`).

### License

No R-contract and no D0-D9 decision names a new License setting. **UNSPECIFIED.**

The section already exists. Its one catalog row is `license` (catalog line 160).

### Auto-update

Triggered when Tony pushes an update (Tony, 2026-11-20). The contract is R-022.

| What the contract requires | Source | Key, type, default |
| --- | --- | --- |
| Signed one-click updater. The approved dependency for this contract only. EdDSA signatures. Rollback and downgrade guards. Feed URL and key generation stay placeholders. No private key in git. Nothing is published. | `spec.md:50`, `spec.md:128`, `tasks.md:72` | New keys beyond the three current update rows are UNSPECIFIED. An update channel control is UNSPECIFIED. |
| Current rows that already exist and must remain | catalog lines 17-19 | `about.autoUpdate`, toggle, default `false`. `about.updateFeedURL`, text, default empty. `about.checkNow`, action, default empty, state stub. |

## 2. Current settings on `2722dcb`

### 2.1 Sidebar

`SettingsNavigation.Section` is `Sources/Zeus/App/SettingsView.swift:11`. Titles are lines 19-48. `shown` (lines 15-17) omits Interview, iPhone, and Intelligence.

| Section id | Title | Line |
| --- | --- | --- |
| general | General | 21 |
| appearance | Appearance | 22 |
| notifications | Notifications | 37 |
| sounds | Sounds | 38 |
| voice | Voice | 31 |
| dictation | Dictation | 32 |
| shortcuts | Shortcut | 39 |
| topBar | Top Bar | 23 |
| todo | To-do | 24 |
| memory | Memory | 25 |
| teleprompter | Prompter | 26 |
| agents | Agents | 27 |
| stickies | Stickies | 28 |
| routines | Routines | 29 |
| keepAwake | Keep awake | 30 |
| integrations | Integrations | 33 |
| assistant | Assistant | 43 |
| intelligence | Intelligence | 44 |
| permissions | Permissions | 34 |
| privacy | Privacy | 35 |
| interview | Interview | 40 |
| iPhone | iPhone | 41 |
| diagnostics | Diagnostics | 42 |
| license | License | 45 |
| about | About | 36 |
| tiling | Tiling | 46 |
| shelf | Shelf | 47 |

The permission rows on this commit are the ten `perm.*` catalog ids (lines 128-137). `PermissionDesk.swift` is not in this tree. It is added on `zeus-bot/settings-permissions` (`e4ea25d`), which has no open PR. That branch's spec (`specs/settings-permissions/spec.md:48-49`) says Settings > Permissions shows one row per capability and the Calendars row reads only when it is tapped.

### 2.2 Catalog

`SettingsCatalog.all` is generated (`Sources/Zeus/App/SettingsCatalog.swift:1-4`). 212 options. `kind` is the control type. `defaultValue` is the default. An empty default is an action or a status with no stored value.

| Line | Id | Section | Group | Title | Type | Default | State |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 6 | `general.language` | general | Your defaults | Language | choice | `System language` | stub |
| 7 | `general.windowTheme` | general | Your defaults | Window appearance | choice | `Dark` | stub |
| 8 | `general.defaultAgent` | general | Your defaults | Default agent for new chats | choice | `Claude Code` | live |
| 9 | `notch.displays` | general | Your defaults | Show the notch on | choice | `Built-in display` | live |
| 10 | `general.launchAtLogin` | general | Day to day | Launch at login | toggle | `true` | live |
| 11 | `general.keepAwake` | general | Day to day | Keep the Mac awake while agents work | toggle | `false` | live |
| 12 | `keepAwake.whileMusic` | general | Day to day | Keep the display awake while music plays | toggle | `false` | live |
| 13 | `general.welcomeBack` | general | Day to day | Welcome back recap | toggle | `true` | live |
| 14 | `general.meetingMode` | general | Day to day | Meeting mode | toggle | `true` | live |
| 15 | `general.showInScreenSharing` | general | Day to day | Show in screen sharing | toggle | `false` | live |
| 16 | `general.runSetup` | general | Guided setup | Run setup again | action | `` | custom |
| 17 | `about.autoUpdate` | general | Updates | Check for updates automatically | toggle | `false` | live |
| 18 | `about.updateFeedURL` | general | Updates | Update feed URL | text | `` | live |
| 19 | `about.checkNow` | general | Updates | Check for updates | action | `` | stub |
| 20 | `appearance.cardStyle` | appearance | Find your look | Card style | choice | `Liquid Glass` | live |
| 21 | `appearance.homeStyle` | appearance | Find your look | Home style | choice | `Device` | live |
| 22 | `appearance.physicalFinish` | appearance | Find your look | Customize Physical | choice | `Same all` | live |
| 23 | `home.widget.1` | appearance | Home | Home slot 1 | choice | `Music` | live |
| 24 | `home.widget.2` | appearance | Home | Home slot 2 | choice | `Focus` | live |
| 25 | `home.widget.3` | appearance | Home | Home slot 3 | choice | `Weather` | live |
| 26 | `home.widget.4` | appearance | Home | Home slot 4 | choice | `Calendar` | live |
| 27 | `home.variant.clock` | appearance | Home | Clock style | choice | `Analog` | live |
| 28 | `home.variant.music` | appearance | Home | Music style | choice | `Art` | live |
| 29 | `home.variant.weather` | appearance | Home | Weather style | choice | `Summary` | live |
| 30 | `home.variant.calendar` | appearance | Home | Calendar style | choice | `Next event` | live |
| 31 | `home.backdrop` | appearance | Home | Home backdrop | choice | `None` | live |
| 32 | `home.worldClock.zones` | appearance | Home | World clock cities | text | `Europe/London, America/New_York, Asia/Tokyo` | live |
| 33 | `home.countdown.title` | appearance | Home | Countdown title | text | `` | live |
| 34 | `home.countdown.date` | appearance | Home | Countdown date | text | `` | live |
| 35 | `appearance.runningCard` | appearance | Agent cards | Running card | choice | `Wave` | live |
| 36 | `avatar.alwaysInNotch` | appearance | Agents | Agent status icon | toggle | `true` | custom |
| 37 | `notch.autoHide` | appearance | Notch behavior | Hide the notch automatically | toggle | `true` | live |
| 38 | `notch.closeDelay` | appearance | Notch behavior | Delay before closing | choice | `0.5 s` | live |
| 39 | `notch.openDelay` | appearance | Notch behavior | Hover delay | choice | `Normal` | live |
| 40 | `notch.openTrigger` | appearance | Notch behavior | Open the notch on | choice | `Hover` | live |
| 41 | `notch.shapeWithoutNotch` | appearance | Displays without a notch | Shape | choice | `Pill` | live |
| 42 | `notch.drawnWidth` | appearance | Displays without a notch | Width | slider | `185` | live |
| 43 | `notch.drawnHeight` | appearance | Displays without a notch | Height | slider | `32` | live |
| 44 | `notch.drawnOffset` | appearance | Displays without a notch | Position | slider | `0` | live |
| 45 | `presence.nearCursor` | appearance | Notch behavior | Show Zeus next to cursor | toggle | `true` | live |
| 46 | `halo.style` | appearance | Halo | Halo style | choice | `classic` | custom |
| 47 | `halo.entrance` | appearance | Halo | Halo entrance | choice | `sweep` | custom |
| 48 | `halo.intensity` | appearance | Halo | Entrance intensity | slider | `100` | live |
| 49 | `halo.speed` | appearance | Halo | Entrance speed | slider | `100` | live |
| 50 | `halo.wallpaper` | appearance | Halo | Match the halo colour to the wallpaper | toggle | `true` | live |
| 51 | `halo.armWidth` | appearance | Halo | Halo arm width | choice | `Medium` | live |
| 52 | `halo.thickness` | appearance | Halo | Light thickness | slider | `100` | live |
| 53 | `notch.background` | appearance | Halo | Island background | choice | `Black` | live |
| 54 | `halo.edgeWave` | appearance | Halo | Light wave to the screen edges | toggle | `true` | live |
| 55 | `topBar.musicWings` | appearance | Everyday lights | Light wave while music plays | toggle | `true` | custom |
| 56 | `lights.musicProgress` | appearance | Everyday lights | Progress outline on the music preview | toggle | `true` | live |
| 57 | `lyrics.wordByWord` | appearance | Everyday lights | Light lyrics word by word | toggle | `true` | live |
| 58 | `lights.liveSpectrum` | appearance | Everyday lights | React to real sound | toggle | `false` | live |
| 59 | `waves.style` | appearance | Everyday lights | Waves style | choice | `Bars` | live |
| 60 | `waves.sensitivity` | appearance | Everyday lights | Waves sensitivity | slider | `100` | live |
| 61 | `lights.copy` | appearance | Everyday lights | Light sweep on copy | toggle | `true` | live |
| 62 | `lights.shelf` | appearance | Everyday lights | Intake light when files land | toggle | `true` | live |
| 63 | `lights.capsLock` | appearance | Everyday lights | Case-key lights | toggle | `true` | live |
| 64 | `lights.shortcutPeeks` | appearance | Everyday lights | Shortcut peeks | toggle | `false` | live |
| 65 | `lights.battery` | appearance | Everyday lights | Green gauge when plugged in | toggle | `true` | live |
| 66 | `lights.hud.volume` | appearance | Everyday lights | Volume HUD in the notch | toggle | `true` | live |
| 67 | `lights.hud.brightness` | appearance | Everyday lights | Brightness HUD in the notch | toggle | `true` | live |
| 68 | `lights.hud.keyboard` | appearance | Everyday lights | Keyboard backlight HUD | toggle | `true` | live |
| 69 | `lights.hud.mute` | appearance | Everyday lights | Mute pulse in the notch | toggle | `true` | live |
| 70 | `lights.hud.replaceSystem` | appearance | Everyday lights | Replace macOS volume and brightness HUD | toggle | `true` | live |
| 71 | `lights.hud.screenEdge` | appearance | Everyday lights | Screen-edge glow on volume, brightness and keyboard-backlight HUDs | toggle | `true` | live |
| 72 | `wake.ignoreMicConflicts` | appearance | Everyday lights | Ignore mic conflicts | toggle | `false` | stub |
| 73 | `lights.rain` | appearance | Everyday lights | Incoming rain alert | toggle | `true` | live |
| 74 | `lights.timer` | appearance | Everyday lights | Timer light gauge | toggle | `true` | live |
| 75 | `lights.micGlow` | appearance | Everyday lights | Purple glow while the mic listens | toggle | `true` | live |
| 76 | `lights.reminderGlow` | appearance | Everyday lights | Glow when a reminder is added | toggle | `true` | live |
| 77 | `lights.eventGlow` | appearance | Everyday lights | Glow when an event is added | toggle | `true` | live |
| 78 | `lights.airDrop` | appearance | Everyday lights | Glow when AirDrop arrives | toggle | `false` | live |
| 79 | `lights.fling` | appearance | Everyday lights | Glow when a Fling arrives | toggle | `true` | live |
| 80 | `lights.screenshot` | appearance | Everyday lights | Screenshot cue | toggle | `false` | live |
| 81 | `music.follow` | appearance | Music | Show music from | choice | `Any player` | live |
| 82 | `screen.roundBottomCorners` | appearance | Screen | Round the bottom screen corners | toggle | `false` | live |
| 83 | `screen.cornerRadius` | appearance | Screen | Corner size | choice | `Medium` | live |
| 84 | `notify.approvals` | notifications | Agent notifications | Permission requests | toggle | `true` | custom |
| 85 | `notify.agentDone` | notifications | Agent notifications | Finished tasks | toggle | `true` | custom |
| 86 | `notify.errors` | notifications | Agent notifications | Errors and stuck agents | toggle | `true` | live |
| 87 | `notify.stallMinutes` | notifications | Agent notifications | Call an agent stalled after | choice | `5 min` | live |
| 88 | `notify.system` | notifications | System alerts | Show system notifications | toggle | `false` | live |
| 89 | `notify.mirror` | notifications | Other apps | Show notifications from other apps in the notch | toggle | `false` | custom |
| 90 | `notify.replaceBanners` | notifications | Other apps | Replace system banners | toggle | `false` | live |
| 91 | `notify.dismissApps` | notifications | Other apps | Auto-dismiss apps | text | `` | live |
| 92 | `notify.mutedApps` | notifications | Other apps | Muted apps | text | `` | custom |
| 93 | `notify.peek` | notifications | Other apps | Peek new notifications under the notch | toggle | `true` | live |
| 94 | `notify.peekDetails` | notifications | Other apps | Show details in the peek | toggle | `true` | live |
| 95 | `sound.on` | sounds | Sound feedback | Sound feedback | toggle | `true` | custom |
| 96 | `sound.startStyle` | sounds | Sound categories | Run start sound | choice | `Classic` | live |
| 97 | `sound.approvalStyle` | sounds | Sound categories | Requests sound | choice | `Classic` | live |
| 98 | `sound.answerStyle` | sounds | Sound categories | Your answer sound | choice | `Futuristic 1` | live |
| 99 | `sound.doneStyle` | sounds | Sound categories | Completion chime | choice | `Success` | live |
| 100 | `dictation.sounds` | sounds | Sound categories | Dictation sounds | toggle | `true` | custom |
| 101 | `sound.timer` | sounds | Sound categories | Timer alarms | toggle | `true` | live |
| 102 | `sound.agentStart` | sounds | Sound categories | Chime when an agent starts working | toggle | `false` | live |
| 103 | `sound.runningLoop` | sounds | Sound categories | Ambient loop while an agent works | toggle | `false` | live |
| 104 | `sound.failure` | sounds | Sound categories | Failure sound | toggle | `true` | live |
| 105 | `audio.equaliser` | sounds | Per-app sound | Shape sound per app | toggle | `false` | custom |
| 106 | `voice.answers` | voice | Voice answer | Listen for approval keywords | toggle | `false` | live |
| 107 | `voice.speakReplies` | voice | Voice answer | Speak replies | toggle | `true` | live |
| 108 | `voice.approveWords` | voice | Your keywords | Approve keywords | text | `ok, yes, approve, allow` | live |
| 109 | `voice.denyWords` | voice | Your keywords | Deny keywords | text | `no, deny, stop` | live |
| 110 | `voice.openWords` | voice | Your keywords | Open the app keywords | text | `open, show me` | live |
| 111 | `voice.resetWords` | voice | Your keywords | Reset the default words | action | `` | live |
| 112 | `dictation.enabled` | dictation | Local dictation | Enable local dictation | toggle | `true` | custom |
| 113 | `dictation.model` | dictation | Local dictation | On-device model | status | `` | live |
| 114 | `dictation.key` | dictation | Your shortcut | Dictation shortcut | choice | `` | custom |
| 115 | `dictation.behavior` | dictation | Your shortcut | Shortcut behavior | choice | `Hold to speak` | live |
| 116 | `dictation.language` | dictation | Language and feedback | Dictation language | choice | `Automatic` | live |
| 117 | `dictation.keepDays` | dictation | History | Dictation history | status | `` | custom |
| 118 | `dictation.copyLast` | dictation | History | Copy last dictation | action | `` | live |
| 119 | `dictation.licenses` | dictation | History | Third-party licenses | action | `` | live |
| 120 | `shortcut.openNotch` | shortcuts | Global shortcut | Open the agent picker | choice | `` | custom |
| 121 | `chat.hotkey` | shortcuts | Global shortcut | Open the chat window | choice | `Control-Option-C` | custom |
| 122 | `shortcut.answerKeys` | shortcuts | Answer from the keyboard | Answer permissions from the keyboard | toggle | `true` | live |
| 123 | `integrations.offerClaude` | integrations | Available apps | Offer Claude Code for new chats | toggle | `true` | live |
| 124 | `integrations.offerCodex` | integrations | Available apps | Offer Codex for new chats | toggle | `true` | live |
| 125 | `integrations.claude` | integrations | Connections | Claude Code connection | status | `` | custom |
| 126 | `integrations.codex` | integrations | Connections | Codex connection | status | `` | live |
| 127 | `integrations.antigravity` | integrations | Connections | Antigravity | status | `` | live |
| 128 | `perm.accessibility` | permissions | Access status | Accessibility | status | `` | custom |
| 129 | `perm.location` | permissions | Access status | Location | status | `` | live |
| 130 | `perm.calendar` | permissions | Access status | Calendar | status | `` | live |
| 131 | `perm.reminders` | permissions | Access status | Reminders | status | `` | live |
| 132 | `perm.notifications` | permissions | Access status | Notifications | status | `` | live |
| 133 | `perm.fullDisk` | permissions | Access status | Full Disk Access | status | `` | live |
| 134 | `perm.mic` | permissions | Access status | Mic and speech recognition | status | `` | custom |
| 135 | `perm.screen` | permissions | Access status | Screen and system audio | status | `` | custom |
| 136 | `perm.automation` | permissions | Access status | Media control | status | `` | live |
| 137 | `perm.trustedChats` | permissions | Trusted chats | Trusted chats | status | `` | custom |
| 138 | `privacy.details` | privacy | Notification details | Show project and command details | toggle | `true` | live |
| 139 | `privacy.analytics` | privacy | Usage data | Help improve | status | `` | live |
| 140 | `privacy.lyrics` | privacy | Music metadata | Synced lyrics | toggle | `false` | live |
| 141 | `music.browserMedia` | privacy | Music metadata | Show media playing in Chrome | toggle | `false` | live |
| 142 | `music.browserMediaStatus` | privacy | Music metadata | Chrome extension needs a reload | status | `` | custom |
| 143 | `face.presence` | privacy | Face presence | Face presence | toggle | `false` | live |
| 144 | `face.lockAfter` | privacy | Face presence | Lock after absent for | choice | `2 minutes` | live |
| 145 | `face.status` | privacy | Face presence | Status | status | `` | custom |
| 146 | `privacy.openAccessibility` | privacy | Access | Open Accessibility settings | action | `` | live |
| 147 | `interview.provider` | interview | AI provider | Provider and model | choice | `Claude (local CLI)` | stub |
| 148 | `interview.key` | interview | AI provider | API key | status | `` | stub |
| 149 | `interview.context` | interview | Candidate context | Candidate context | text | `` | stub |
| 150 | `interview.autoSuggest` | interview | Candidate context | Offer a suggestion automatically | toggle | `false` | stub |
| 151 | `interview.systemAudio` | interview | Interviewer's voice | Capture and transcribe system audio | toggle | `false` | stub |
| 152 | `interview.hide` | interview | Screen sharing | Hide from screen sharing | toggle | `false` | custom |
| 153 | `iphone.pair` | iPhone | Pairing | Connect an iPhone | status | `` | custom |
| 154 | `iphone.restart` | iPhone | Local connection | Restart the local connection | action | `` | stub |
| 155 | `diag.socket` | diagnostics | Status | Connection status | status | `` | custom |
| 156 | `diag.agents` | diagnostics | Status | Tracked agents | status | `` | live |
| 157 | `diag.logs` | diagnostics | Logs | Flight recorder: the last 2,000 app events | status | `` | custom |
| 158 | `diag.export` | diagnostics | Logs | Export diagnostics | action | `` | custom |
| 159 | `diag.restart` | diagnostics | Recovery | Restart the daemon | action | `` | live |
| 160 | `license` | license | License | Activate a license, key, buy, trial status | status | `` | custom |
| 161 | `explanation.enabled` | assistant | Visual explanation | Enable visual explanations | toggle | `false` | live |
| 162 | `explanation.shortcut` | assistant | Visual explanation | Spoken request shortcut | choice | `Command-Shift-Space` | live |
| 163 | `pointing.enabled` | assistant | Desktop pointing | Enable desktop pointing | toggle | `true` | live |
| 164 | `pointing.shortcut` | assistant | Desktop pointing | Pointing keys | choice | `Control-Option` | live |
| 165 | `pointing.drawWhileHeld` | assistant | Desktop pointing | Draw while held | toggle | `true` | live |
| 166 | `pointing.sendScreenshot` | assistant | Desktop pointing | Send a screenshot with each question | toggle | `false` | live |
| 167 | `pointing.provider` | assistant | Desktop pointing | Provider | choice | `Auto` | live |
| 168 | `pointing.textEntry` | assistant | Desktop pointing | Double-tap Control to type a question | toggle | `false` | live |
| 169 | `pointing.dictationFnControl` | assistant | Desktop pointing | Use Fn+Control for dictation | toggle | `false` | live |
| 170 | `assistant.provider` | assistant | Account | ChatGPT account, model, reasoning effort, speed | choice | `Claude CLI` | custom |
| 171 | `assistant.model` | assistant | Model | Model | choice | `Claude Code default` | custom |
| 172 | `assistant.doubleCommand` | assistant | Behaviour | Double Command replies, Right Command hold to speak | toggle | `false` | stub |
| 173 | `beamer.autoStart` | integrations | Beamer | Beamer: start when Zeus starts | toggle | `false` | live |
| 174 | `beamer.cue` | integrations | Beamer | Beamer: light the notch when control crosses | toggle | `true` | live |
| 175 | `fastPath.enabled` | voice | Fast path | Fast path | toggle | `true` | live |
| 176 | `voice.heyZeus` | voice | Hey Zeus | Listen for "Hey Zeus" | toggle | `false` | custom |
| 177 | `voice.talkKey` | voice | Talk to Zeus | Talk shortcut | choice | `` | custom |
| 178 | `voice.secondTalkKey` | voice | Talk to Zeus | Second talk key | choice | `Right Option` | custom |
| 179 | `talk.microphone` | voice | Talk to Zeus | Microphone | choice | `Automatic` | custom |
| 180 | `talk.seeScreen` | voice | Talk to Zeus | Let Zeus see my screen when I talk | toggle | `true` | live |
| 181 | `talk.drawOnScreen` | voice | Talk to Zeus | Draw on the screen while Zeus answers | toggle | `false` | live |
| 182 | `voice.personality` | voice | Voice | Personality | choice | `Ultron` | custom |
| 183 | `dictation.engine` | voice | Dictation | Murmure speech engines | choice | `` | custom |
| 184 | `insomnia.lidClosed` | keepAwake | Insomnia | Insomnia | toggle | `false` | custom |
| 185 | `prompter.followPresentation` | teleprompter | Teleprompter | Follow my presentation | toggle | `false` | custom |
| 186 | `prompter.followAdvances` | teleprompter | Teleprompter | Advance slides when I finish their notes | toggle | `false` | custom |
| 187 | `prompterWindow.private` | teleprompter | Teleprompter | Hide the prompter from screen sharing | toggle | `true` | custom |
| 188 | `browserAgent.enabled` | agents | Browser agent | Let Zeus work in Chrome | toggle | `true` | live |
| 189 | `browserAgent.maxSteps` | agents | Browser agent | Most steps per task | choice | `25` | live |
| 190 | `browserAgent.alwaysAsk` | agents | Browser agent | Always ask before | text | `` | live |
| 191 | `browserAgent.backend` | agents | Browser agent | Browser for the agent | choice | `Your Chrome` | live |
| 192 | `browserAgent.allowedDomains` | agents | Browser agent | Allowed sites | text | `` | live |
| 193 | `scribe.autoStart` | agents | Scribe | When a meeting starts | choice | `Ask me` | live |
| 194 | `code.tool` | agents | Coding | Default coding agent | choice | `Claude Code` | custom |
| 195 | `code.terminal` | agents | Coding | Terminal app | choice | `Automatic` | custom |
| 196 | `research.depth` | agents | Research | Research depth | choice | `Quick` | live |
| 197 | `research.folder` | agents | Research | Save reports in | text | `` | live |
| 198 | `models.caps` | agents | Models | Models Zeus uses | status | `` | custom |
| 199 | `privacy.driveAutonomy` | agents | Drive | When Zeus may drive your Mac | choice | `Safe steps alone` | custom |
| 200 | `present.physicalPointer` | agents | Drive | Move the system pointer | toggle | `false` | live |
| 201 | `tiling.enabled` | tiling | Arrange | Arrange my windows from the keyboard | toggle | `false` | live |
| 202 | `tiling.keyBase` | tiling | Arrange | Tiling keys | choice | `Control-Option-Command` | live |
| 203 | `tiling.innerGap` | tiling | Layout | Gap between windows | slider | `8` | live |
| 204 | `tiling.outerGap` | tiling | Layout | Gap to the screen edge | slider | `8` | live |
| 205 | `tiling.splitRatio` | tiling | Layout | Default split | slider | `50` | live |
| 206 | `tiling.focusBorder` | tiling | Focus | Ring the focused window | toggle | `true` | live |
| 207 | `tiling.excludedApps` | tiling | Left out | Apps Zeus never tiles | text | `` | live |
| 208 | `fling.enabled` | shelf | Fling | Send and receive with nearby Macs | toggle | `false` | live |
| 209 | `fling.receiveInBackground` | shelf | Fling | Receive while the notch is closed | toggle | `true` | live |
| 210 | `fling.deviceName` | shelf | Fling | Name shown to nearby Macs | text | `` | live |
| 211 | `fling.visibility` | shelf | Fling | Who can see this Mac | choice | `Everyone nearby` | live |
| 212 | `fling.autoAcceptPaired` | shelf | Fling | Accept from paired Macs without asking | toggle | `true` | live |
| 213 | `fling.saveMode` | shelf | Fling | Where arrivals go | choice | `Downloads/Fling` | live |
| 214 | `fling.papers` | shelf | Fling | Show arrivals as floating papers | toggle | `false` | live |
| 215 | `fling.flickSensitivity` | shelf | Fling | Flick sensitivity | choice | `Normal` | live |
| 216 | `fling.openLinks` | shelf | Fling | Open received links in the browser | toggle | `true` | live |
| 217 | `fling.pairedMacs` | shelf | Fling | Paired Macs | action | `` | custom |

Choice lists and slider ranges sit on the same source line as the row. `kind: .choice` is a menu or segmented control, `.toggle` a switch, `.slider` a ranged slider, `.text` a field, `.action` a button, `.status` a row with no stored default.

### 2.3 Settings stored outside the catalog

These are user-facing values with a type and a default on `2722dcb`. Internal caches (reminder id maps, license revocation stamps, voice pause timestamps, first-audio timings) are not settings and are left out.

| Key | Section / page | Type | Default | Line |
| --- | --- | --- | --- | --- |
| `showCaptions` | Preferences | bool | `true` | `Sources/Zeus/App/Preferences.swift:41` |
| `showMenuBarIcon` | Preferences | bool | `true` | `Preferences.swift:42` |
| `dates.followSystemCalendar` | General | bool | `false` (unset stays Gregorian) | `Sources/ZeusCore/ZeusDates.swift:7-11`, read at `Preferences.swift:43` |
| push-to-talk shortcut | Preferences / Voice | shortcut | loaded by `ShortcutStore.loadTalk` | `Preferences.swift:40` |
| `notify.calendarLead` | Notifications | int | `5` | `Sources/Zeus/App/ExtraPreferences.swift:57` |
| `notify.reminders` | Notifications | bool | `true` | `ExtraPreferences.swift:58` |
| `notify.focus` | Notifications | bool | `true` | `ExtraPreferences.swift:59` |
| `notify.quietSharing` | Notifications | bool | `true` | `ExtraPreferences.swift:60` |
| `sound.volume` | Sounds | int | `60` | `ExtraPreferences.swift:64` |
| `sound.approval` | Sounds | bool | `true` | `ExtraPreferences.swift:65` |
| `sound.done` | Sounds | bool | `true` | `ExtraPreferences.swift:66` |
| `sound.todo` | Sounds | bool | `true` | `ExtraPreferences.swift:67` |
| `sound.voiceStart` | Sounds | bool | `true` | `ExtraPreferences.swift:69` |
| `sound.voiceStop` | Sounds | bool | `true` | `ExtraPreferences.swift:70` |
| `sound.voiceDone` | Sounds | bool | `true` | `ExtraPreferences.swift:71` |
| `sound.voiceError` | Sounds | bool | `true` | `ExtraPreferences.swift:72` |
| `shortcut.quickTodo` | Shortcut | preset | `controlOptionT` | `ExtraPreferences.swift:78-79` |
| `voice.engine` | Voice | engine id | plan in `VoiceSettings.swift:122-123`; not a literal | `VoiceSettings.swift:114` |
| `voice.engine.userSelected` | Voice | bool | `false` (`bool(forKey:)`) | `VoiceSettings.swift:117` |
| `voice.engine.auto` | Voice | bool | computed by `ElevenLabsFailsafe.defaultEngineAuto` | `VoiceSettings.swift:131-133` |
| `voice.ttsProvider` | Voice | provider id | `UltronVoicePlan.defaultProvider` when unset | `VoiceSettings.swift:124-128` |
| `voice.personality` | Voice | choice | `ultron` | `Sources/ZeusCore/Persona/ZeusVoiceLines.swift:8`, `:27-28` |
| `voice.kokoro.voice` | Voice | string | `am_michael` | `VoiceSettings.swift:134`, `Sources/ZeusCore/Voice/UltronCloudVoice.swift:28` |
| `voice.kokoro.speed` | Voice | double | `0.88` | `VoiceSettings.swift:135`, `UltronCloudVoice.swift:29` |
| `voice.elevenlabs.quality` | Voice | choice | `studio` | `Sources/ZeusCore/Voice/VoiceQuality.swift:15`, `:27-28` |
| `voice.openai.voice` | Voice | string | `onyx` | `VoiceSettings.swift:139`, `UltronCloudVoice.swift:8` |
| `voice.gemini.voice` | Voice | string | `Kore` | `VoiceSettings.swift:140`, `Sources/ZeusCore/Voice/VoiceCatalog.swift:41`, `:57-59` |
| `voice.orbStyle` | Voice | choice | `mascot` | `Sources/ZeusCore/Voice/VoiceRingModel.swift:7`, `:18-19` |
| `wake.enabled` | Voice | bool | `false` | `Sources/Zeus/Voice/WakeWordController.swift:16`, `:54`. Catalog id `voice.heyZeus` stores this key (catalog line 176). |
| `dictation.autoSwitch` | Dictation | bool | `false` | `Sources/Zeus/Dictation/DictationController.swift:76` |
| `dictation.restoreClipboard` | Dictation | bool | `true` | `DictationController.swift:77` |
| `dictation.cueStyle` | Dictation | choice | `Crystal` | `DictationController.swift:79`, `Sources/ZeusCore/Sound/DictationCue.swift:15-19` |
| `dictation.cueVolume` | Dictation | int | `70` | `DictationController.swift:80`, `DictationCue.swift:96` |
| `dictation.pauseMedia` | Dictation | bool | `true` | `DictationController.swift:81` |
| `dictation.engineForVoice` | Dictation | bool | `false` | `DictationController.swift:84` |
| `dictation.alwaysType` | Dictation | bool | `false` | `DictationController.swift:85` |
| `dictation.typedApps` | Dictation | string list | `KeystrokeTyping.defaultBundleIDs` | `DictationController.swift:86` |
| `dictation.microphone` | Dictation | string | unset | `DictationController.swift:87` |
| `dictation.preview` | Dictation | bool | `false` | `DictationController.swift:91` |
| `dictation.mode` | Dictation | string | `voice` | `Sources/Zeus/TopBar/TopBarModel.swift:331` |
| `polyglot.enabled` | Polyglot | bool | `true` | `Sources/Zeus/Polyglot/PolyglotSettings.swift:30` |
| `polyglot.source` | Polyglot | choice | `.microphone` | `PolyglotSettings.swift:31` |
| `polyglot.target` | Polyglot | string | `en` | `PolyglotSettings.swift:32` |
| `polyglot.showOriginal` | Polyglot | bool | `true` | `PolyglotSettings.swift:33` |
| `polyglot.size` | Polyglot | choice | `.medium` | `PolyglotSettings.swift:34` |
| `polyglot.hotkey` | Polyglot | shortcut | Control-Option-T (`defaultHotkey`) | `PolyglotSettings.swift:13`, `:35-38` |
| `keepAwake.display` | Keep awake | bool | `false` (`bool(forKey:)`) | `Sources/Zeus/TopBar/KeepAwakeSession.swift:29` |
| `keepAwake.batteryFloor` | Keep awake | int | `10` | `KeepAwakeSession.swift:33` |
| `keepAwake.endWhenHot` | Keep awake | bool | `true` | `KeepAwakeSession.swift:37` |
| `keepAwake.homeMinutes` | Keep awake | int | `30` when read and unset | `KeepAwakeSession.swift:174` |
| `insomnia.lidClosed` | Keep awake | bool | catalog default `false` (line 184); controller fallback `true` when the key is absent | `Sources/Zeus/Insomnia/InsomniaController.swift:70` |
| `insomnia.freeze` | Keep awake | string list | empty | `InsomniaController.swift:71` |
| `insomnia.hotspotSSID` | Keep awake | string | empty | `InsomniaController.swift:72` |
| `insomnia.nudge` | Keep awake | bool | `false` | `InsomniaController.swift:73` |
| `insomnia.nudgeMinutes` | Keep awake | int | `10` | `InsomniaController.swift:74` |
| `insomnia.mute` | Keep awake | bool | `true` | `InsomniaController.swift:75` |
| `insomnia.lowPower` | Keep awake | bool | `true` | `InsomniaController.swift:76` |
| `insomnia.minutes` | Keep awake | int | unset means the controller's indefinite duration | `InsomniaController.swift:77-78` |
| `topBar.tabs` | Top Bar | encoded layout | repaired row in `TopBarModel` init | `TopBarModel.swift:311-322` |
| `topBar.cues` | Top Bar | bool | `true` | `TopBarModel.swift:326` |
| `topBar.weatherCity` | Weather, stored on the top bar | string | empty | `TopBarModel.swift:328` |
| `topBar.celsius` | Weather, stored on the top bar | bool | `true` unless the locale measurement system is US | `TopBarModel.swift:329` |
| `topBar.note` | Top Bar | string | empty | `TopBarModel.swift:330` |
| `prompter.script` | Prompter | string | `TopBarModel.sampleScript` | `TopBarModel.swift:332` |
| `prompter.speed` | Prompter | double | `32` | `TopBarModel.swift:333` |
| `prompter.voice` | Prompter | bool | `true` | `TopBarModel.swift:334` |
| `prompter.size` | Prompter | double | `22` | `TopBarModel.swift:335` |
| `prompter.followPresentation` | Prompter | bool | `false` | `Sources/Zeus/Prompter/PrompterWindow.swift:768`, `Sources/Zeus/App/ZeusSettingsPages.swift:147` |
| `todo.reminders` | To-do | bool | `false` (`bool(forKey:)`) | `Sources/Zeus/TopBar/TodoController.swift:75` |
| `todo.learning` | To-do | bool | `true` when the key is absent | `TodoController.swift:79-81`, `Sources/ZeusCore/SecondBrain/TodoLearning.swift:48` |
| `todo.connection` | Memory | data | unset | `TodoController.swift:73` |
| `todo.vaultBookmark` | Memory | bookmark | unset | `ZeusSettingsPages.swift:90` |
| `proactive.brief` | To-do | bool | `false` (`bool(forKey:)`) | `Sources/Zeus/Proactive/ProactiveController.swift:16`, `:21` |
| `proactive.nudges` | To-do | bool | `false` | `ProactiveController.swift:17`, `:22` |
| `aboutYou.name` | Memory / onboarding | string | the Mac account name when unset | `Sources/Zeus/App/AboutYouOnboarding.swift:28` |
| `present.physicalPointer` | Agents | bool | catalog `false` (line 200) | `Sources/ZeusCore/Present/PhysicalPointerSettings.swift:5` |
| `drive.autonomy` | Agents | choice | catalog default `Safe steps alone` under id `privacy.driveAutonomy` (line 199) | `Sources/Zeus/App/CommandModeSettings.swift:7` |

`RoutinesSettingsView.swift` is the Routines page. A search of that file found no `UserDefaults` key.

### 2.4 What PR #22 changes

PR #22 (`zeus-bot/settings-plain`, head `ff33ee3`, base `main`) is open. Three files:

- `Sources/Zeus/Settings/GlanceSettingsPages.swift` (+49 / -49)
- `Sources/Zeus/Settings/GlanceSettingsStyle.swift` (+21 / -4)
- `qa/closed-loop/tests/test_settings_copy_lint.py` (added, 86 lines)

`SettingsCatalog.swift` is not in the diff. No catalog id is added, removed, or given a new default. The page diff shortens the visible helper (`text:`) to one sentence and moves the rest onto `detail:`. The same ids stay bound, including `general.keepAwake`, `keepAwake.whileMusic`, `general.welcomeBack`, `halo.edgeWave`, `notify.errors`, and `privacy.details`. The command-line helper becomes "Lets the zeus command use the microphone, record, type and click." The PR body says control behavior is unchanged and the 45 s and 20 s timeouts are unchanged.

PR #22's base is `main` (`d6d45dd`), not `2722dcb`. The catalog table above is `2722dcb`.

## 3. Mapping

Status is against `2722dcb`. **exists**: the section is in the sidebar and the contract adds no missing control. **partial**: some of the contract's subject is already a setting, and a named control is still missing or is a stub. **missing**: the section is not in the sidebar.

Private API or a new permission is allowed only for R-015, R-016, R-017, R-018, R-019, R-020, R-022, and R-023, and only behind a setting that is off by default and fails closed (`spec.md:80`). Risk is HIGH for Face ID, for Auto-update and any update channel, and for any private API.

| Target section | Status | Contract and decision | Private API or new permission | Risk |
| --- | --- | --- | --- | --- |
| Media | partial | R-001 to R-005, R-010 to R-014, R-025. D5 is unchosen (`NOTCH-OUTPUT-PLAN.md:547`). | No. R-014 is held and is not built with the private framework (`spec.md:132`). Wave 1 adds no permission (`spec.md:163`). | Not HIGH while R-014 stays held. |
| General | exists | R-021. D3 keeps `notch.displays` here (`NOTCH-DRAWN-NOTCH-PLAN.md:499`). R-024's section is UNSPECIFIED. | No. | Not HIGH. |
| Portal | missing | None. Settings UNSPECIFIED. | No. | Not HIGH. |
| Sensory | missing | None. Settings UNSPECIFIED. | No. | Not HIGH. |
| Battery | partial | R-015 and R-016, one setting. Current charge lights and `keepAwake.batteryFloor` stay as existing keys. | Yes. Bluetooth prompt and the private battery and listening-mode symbols (`spec.md:44`, `spec.md:123`). Off by default, fail closed. | HIGH. Private API. |
| Focus | partial | R-017. Home Focus and the timer light already exist and are not this contract. | Yes, only the store-file opt-in, which can ask for Full Disk Access (`spec.md:45`, `spec.md:125`). The public filter is first. Off reads nothing. | HIGH. The opt-in is in the private-API allowance. |
| Weather | partial | None. Settings for the new section are UNSPECIFIED. Weather widgets and `topBar.weatherCity` already exist. | No. | Not HIGH. |
| Lock Screen | missing | R-018. | Yes. Private window-server space (`spec.md:46`, `spec.md:124`). Off by default. Missing symbol keeps the card hidden. | HIGH. Private API. |
| Face ID | partial | R-023. `face.presence`, `face.lockAfter`, and `face.status` exist (catalog lines 143-145). Approval wiring is not a named key. | The contract is in the allowance list. The spec uses the camera entitlement already in the app and adds no permission (`spec.md:113`). Private API: no. | HIGH. Face ID. |
| Accessory | missing | R-019. R-016 stays the Battery setting until a decision splits it. D5 is unchosen. | Yes, a Local Network usage string (`spec.md:47`, `spec.md:126`). Not a private API. Off does not browse. | Not HIGH. |
| License | exists | None. The `license` row stays. New settings UNSPECIFIED. | No. | Not HIGH. |
| Auto-update | partial | R-022. The three `about.*` update rows exist on General (catalog lines 17-19). `about.autoUpdate` defaults `false`. An update channel is UNSPECIFIED. | The contract is in the allowance list. The spec names the updater dependency, not a private API and not a new permission (`spec.md:50`, `spec.md:128`). | HIGH. Update channel and the updater. |

### Contracts that are not one of the twelve sections

| Contract | What is specified | Status on `2722dcb` | Private API or new permission |
| --- | --- | --- | --- |
| R-006 | Rounded bottom corners, click-through, above full screen (`spec.md:35`). | `screen.roundBottomCorners` and `screen.cornerRadius` exist (catalog lines 82-83). | No. |
| R-007 | Live own-process CPU, memory, thermal, and audio rows, with copy (`spec.md:36`). | No such rows. Section UNSPECIFIED. | No. Public process info only. |
| R-008 | Output list, transport icons, read-back (`spec.md:37`). | The output menu exists, per the contract. Icon key UNSPECIFIED. | No. |
| R-009 | Drawn notch and calibration (`spec.md:38`). D0-D4. | Keys exist (catalog lines 41-44). | No. |
| R-012 | Parser of times already in the file (`spec.md:41`). | No settings key. | No. |
| R-020 | Phone drop. Stage 1 is a QR code and an upload page. Shared Wi-Fi needs a one-time token and TLS, or the listener is local-only. Stage 2 is not built (`spec.md:48`, `spec.md:127`). | Missing. Section UNSPECIFIED. The key is UNSPECIFIED. | Allowed by `spec.md:80`. Private API: no. A new permission is UNSPECIFIED. Off by default if the section is later specified. |
| R-024 | Held row, "not available yet" (`spec.md:52`, `spec.md:132`). | Missing. Section UNSPECIFIED. | No. |

## Assumptions

- `2722dcb` is the settings baseline. `dfd1179` is the contract baseline. `2c44319` is evidence of earlier public types, not a commit to replay (`spec.md:28`).
- "Keep every setting" means every catalog id and every section 2.3 key remains present, with the same type and default, including the stub rows.
- A target section with UNSPECIFIED settings is still one of Tony's sections. It gains no key in this inventory.
