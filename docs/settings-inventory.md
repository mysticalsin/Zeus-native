# a reference app settings inventory

Source: a reference app (build 26) from app-71mb.dmg, studied on the box: the fr and es `Localizable.strings` (1,644 keys; the en table is intentionally empty because the English copy lives in code), `Info.plist` usage strings, `strings` on the binary (defaults keys such as `notchpilot.lyrics.enabled`, `notchpilot.notifications.replaceSystem`, `notchpilot.notifications.mutedApps`, `haloStyle`, `cardStyle`, `avatarStyle`, `haloThickness`, `armWidthSetting`, `rainAlertEnabledKey`, `focusMinutes`, `keepAwake`, `inMeeting`) and the 14 `settings-glass-*` sidebar icon names. No code or assets were copied; Zeus draws its own UI and uses macOS system sounds.

Sidebar (the reference app order): General, Appearance, Notifications, Sounds, Voice, Dictation, Shortcut, Integrations, Permissions, Privacy, Interview, iPhone, Diagnostics, License. The Assistant (ChatGPT sign-in) strings exist but have no sidebar icon in 0.3.1.

**Coverage:** 174 of 174 the reference app options are in Zeus Settings with a matching control (100% of all, 100% of the 174 in scope). 163 are wired to real behaviour (93%). 11 are labelled stubs with a TODO. 0 are excluded.

**Before this round:** has 19, partial 27, missing 123.

Status key: **live** wired this round, **custom** an existing hand-built Zeus row, **stub** stored, exported and labelled "Coming" with a TODO, **excluded** not built on purpose.


## General

| Group | Reference option | Control | Reference default | What it does | Zeus before | Zeus now | Zeus id | Note |
|---|---|---|---|---|---|---|---|---|
| Your defaults | Language | menu | System language | Pins the app language instead of following macOS. | missing | stub | `general.language` | ZEUS copy is English only today. TODO: localize, then honour the pin. |
| Your defaults | Window appearance (System, Light, Dark) | segmented | System | Theme for Settings and the welcome guide. | missing | stub | `general.windowTheme` | Glass is drawn dark only. TODO: light glass palette. |
| Your defaults | Default agent for new chats | menu | Claude Code | Agent used when you start a new chat from the notch. | missing | live | `general.defaultAgent` | Pre-selects the agent in Chat > New chat; falls back to the first offered agent. |
| Your defaults | Show the notch on (Built-in display, Display with the pointer, All displays) | menu | Built-in display | Which screens carry the notch. Screens without a notch get a slim pill. | missing | live | `notch.displays` | Rebuilds the notch windows; lock, wake and Space changes re-raise them. |
| Day to day | Launch at login | toggle | on | Starts the app when you log in. | missing | live | `general.launchAtLogin` | SMAppService, bundled app only. |
| Day to day | Keep the Mac awake while agents work | toggle | off | Blocks idle sleep while an agent runs; the screen can still lock. | missing | live | `general.keepAwake` | Power assertion held only while a session is working. |
| Day to day | Welcome back recap (Recap and return) | toggle | on | After 10 minutes or more away, the notch shows what agents finished, failed or are waiting on, and Zeus says one line about it when voice answers are on. | missing | live | `general.welcomeBack` | Away is system idle time (no keys or mouse). Only agent events since you left are listed; waiting ones only while still waiting. |
| Day to day | Meeting mode (discreet during calls and screen sharing) | toggle | on | When another app uses the mic or camera, or the display is mirrored: leave captures, mute sounds, hide details. | partial | live | `general.meetingMode` | Detects the mic in use by another app and mirrored displays. Camera detection TODO. |
| Day to day | Show in screen sharing | toggle | - |  | missing | live | `general.showInScreenSharing` | N1. Every Zeus window uses the shared sharing helper. |
| Guided setup | Run setup again | button | - | Replays the first-run guide. | has | custom | `general.runSetup` |  |
| Updates | Check for updates automatically | toggle | on |  | missing | live | `about.autoUpdate` | N6. Polls the feed URL when set. |
| Updates | Update feed URL | text | - |  | missing | live | `about.updateFeedURL` | N6. JSON feed with version and downloadURL; empty means off. |
| Updates | Check for updates | button | - | Checks now. | missing | stub | `about.checkNow` | Same as above. |

## Appearance

| Group | Reference option | Control | Reference default | What it does | Zeus before | Zeus now | Zeus id | Note |
|---|---|---|---|---|---|---|---|---|
| Find your look | Card style (Classic, Glass, Physical, Liquid Glass, Dashboard, Dashboard B) | picture cards | Glass | Look of the permission, running and finished cards. | partial | live | `appearance.cardStyle` |  |
| Find your look | Home style (Device, Borderless, Borderless colour) | picture cards | Device | Frame of the Home band. | missing | live | `appearance.homeStyle` |  |
| Find your look | Customize Physical (Home and card finishes) | menus | - | Separate finishes for Home and cards in the Physical theme. | missing | live | `appearance.physicalFinish` |  |
| Home | Home slot 1 | menu | - | The widget in the first Home card. | missing | live | `home.widget.1` | Click a card in Customize Home, or pick here. Defaults are today's Music, Focus, Weather and Calendar. |
| Home | Home slot 2 | menu | - | The widget in the second Home card. | missing | live | `home.widget.2` | Click a card in Customize Home, or pick here. Defaults are today's Music, Focus, Weather and Calendar. |
| Home | Home slot 3 | menu | - | The widget in the third Home card. | missing | live | `home.widget.3` | Click a card in Customize Home, or pick here. Defaults are today's Music, Focus, Weather and Calendar. |
| Home | Home slot 4 | menu | - | The widget in the fourth Home card. | missing | live | `home.widget.4` | Click a card in Customize Home, or pick here. Defaults are today's Music, Focus, Weather and Calendar. |
| Home | Clock style | menu | - | Analog, digital, elastic or blue halo. | missing | live | `home.variant.clock` | Home Clock widget. |
| Home | Music style | menu | - | Art, disc, cassette, wave or synced lyrics. | missing | live | `home.variant.music` | Home Music widget. |
| Home | Weather style | menu | - | Summary, hourly curve, days, feels like or wind. | missing | live | `home.variant.weather` | Home Weather widget. |
| Home | Calendar style | menu | - | Next event, month, week or agenda. | missing | live | `home.variant.calendar` | Home Calendar widget. |
| Home | Home backdrop | picture cards | - | A quiet drawing behind the Home cards. Moves only while Home is open, and holds still with Reduce Motion. | missing | live | `home.backdrop` | Twelve procedural backdrops drawn in SwiftUI. |
| Home | World clock cities | text | - | Time zone names, separated by commas. | missing | live | `home.worldClock.zones` | Home World clock widget. |
| Home | Countdown title | text | - | What the Countdown widget counts down to. | missing | live | `home.countdown.title` | Home Countdown widget. |
| Home | Countdown date | text | - | A day as 2026-12-25. | missing | live | `home.countdown.date` | Home Countdown widget. |
| Agent cards | Running card (Wave, Essentials) | segmented | Wave | Layout of the running-agent preview. | missing | live | `appearance.runningCard` | Wave shows activity bars; Essentials keeps the compact status row. |
| Agents | Agent status icon (Glyphs, Lumi, Lumi Pixel, Creatures) | picture cards | Glyphs | Symbol or a character for each agent state. | partial | custom | `avatar.alwaysInNotch` | ZEUS answer: the Mini ZEUS mascot (13 states) on General. |
| Notch behavior | Hide the notch automatically | toggle | on | Closes when the pointer leaves. | partial | live | `notch.autoHide` | Off: it stays open until the shortcut or a click elsewhere. |
| Notch behavior | Delay before closing | menu | Short | How long it waits after the pointer leaves. | missing | live | `notch.closeDelay` | the reference app closes about 0.53 s after the pointer leaves (private reference notes). |
| Notch behavior | Hover delay | menu | On hover | How quickly hovering opens it. | partial | live | `notch.openDelay` | 0.1 s, 0.25 s or 0.6 s. |
| Notch behavior | Open the notch on | menu | - | Hover opens it after the delay. Click opens it only when you click the notch. | missing | live | `notch.openTrigger` | S1. Click opens the panel from the closed notch or a peek, from the hardware notch (or the pill, grown 12 pt each side, on a display without one); hover never opens it. |
| Notch behavior | Show Zeus next to cursor | toggle | off | When summoned, Zeus anchors beside the mouse pointer instead of the notch. | missing | live | `presence.nearCursor` | P0 item I. Offset 18 pt right and down from the pointer, clamped and flipped at screen edges, multi-display aware, 60 fps with a light spring; off keeps the notch/top-bar placement. Also in the menu bar menu and `zeus debug presence`. |
| Halo | Halo style | menu | Classic halo | The closed-notch glow while an agent works or needs you. One setting: the notch, Settings and the welcome guide all read it. | partial | custom | `halo.style` | Stable ids; titles come from ZeusCore.HaloStyle. Replaces the old topBar.halo key (migrated at launch). |
| Halo | Halo entrance | menu | Sweep | Animation as the halo lights up. | partial | custom | `halo.entrance` | Stable ids; titles come from ZeusCore.HaloEntrance. Each has its own choreography. |
| Halo | Entrance intensity | slider | 100 % | Strength of the entrance. | missing | live | `halo.intensity` | Controls the halo entrance effects and live preview. |
| Halo | Entrance speed | slider | 100 % | Speed of the entrance. | missing | live | `halo.speed` | Scales the closed-notch entrance duration from 50 to 200 %. |
| Halo | Match the halo colour to the wallpaper | toggle | on | Blends with white on light wallpapers. | partial | live | `halo.wallpaper` | Samples the wallpaper under the notch and blends the halo toward white as it gets lighter. |
| Halo | Halo arm width (Narrow, Medium, Wide, Extra wide) | segmented | Medium | 76, 130, 220 or 440 pt each side. | missing | live | `halo.armWidth` | Controls the closed-notch halo reach and live preview. |
| Halo | Light thickness | slider | 100 % | 100 to 200 %. | missing | live | `halo.thickness` | Controls the closed-notch halo and live preview. |
| Halo | Light wave to the screen edges | toggle | on | A wave of light crosses the screen on agent events. | partial | live | `halo.edgeWave` | A click-through overlay on every Space, left out of captures; fronts run round the screen edge. |
| Everyday lights | Light wave while music plays | toggle | on | Artwork-tinted wave on the closed notch. | has | custom | `topBar.musicWings` |  |
| Everyday lights | Progress outline on the music preview | toggle | on | Outline empties as the track plays. | missing | live | `lights.musicProgress` | Tracks media progress around the music wings. |
| Everyday lights | React to real sound (live spectrum) | toggle | off | The music light follows the sound your Mac is playing. | missing | live | `lights.liveSpectrum` | CoreAudio process tap of system output, listen only. Asks for System Audio Recording once, when this is turned on or the Waves tab opens. Runs only while music plays. |
| Everyday lights | Waves style (Bars, Wave, Mirror) | segmented | Bars | How the Waves tab draws the spectrum. | missing | live | `waves.style` | Zeus addition. The Waves tab is off by default; add it in Settings > Appearance > Top bar tabs. |
| Everyday lights | Waves sensitivity | slider | 100 % | How strongly the bars react to quiet sound. | missing | live | `waves.sensitivity` | Zeus addition. A gain on the live band levels. |
| Everyday lights | Light sweep on copy | toggle | on | Confirms a copy was caught. | partial | live | `lights.copy` | Gates the copy cue. |
| Everyday lights | Intake light when files land | toggle | on | Glow when files land on the shelf. | partial | live | `lights.shelf` | Gates the shelf cue. |
| Everyday lights | Case-key lights (Caps Lock and Shift) | toggle | on | Caps Lock flashes the outline. | partial | live | `lights.capsLock` | Caps Lock flash and the Shift-held-alone crest, both live (Shift needs Accessibility access). |
| Everyday lights | Shortcut peeks (cut, undo, save, print...) | toggle | on | Shows cards for command shortcuts. Requires Accessibility access. | missing | live | `lights.shortcutPeeks` | Key monitoring waits until Accessibility access is granted in Settings > Permissions. |
| Everyday lights | Green gauge when plugged in | toggle | on | Charge level outline on power changes. | partial | live | `lights.battery` | Gates charging and low-battery cues. |
| Everyday lights | Volume HUD in the notch | toggle | on | Level glow and wings when output volume changes. | live | live | `lights.hud.volume` | CoreAudio listener; no permission needed. |
| Everyday lights | Brightness HUD in the notch | toggle | on | Level glow when built-in brightness changes. | live | live | `lights.hud.brightness` | DisplayServices polling; keys accelerate when Accessibility is on. |
| Everyday lights | Keyboard backlight HUD | toggle | on | Level glow when keyboard illumination changes. | live | live | `lights.hud.keyboard` | Skipped on Macs without a backlight. |
| Everyday lights | Mute pulse in the notch | toggle | on | Dim slash pulse when output is muted. | live | live | `lights.hud.mute` |  |
| Everyday lights | Replace macOS volume and brightness HUD | toggle | on | Needs Accessibility in Settings > Permissions. Without it, both HUDs can show. | live | live | `lights.hud.replaceSystem` | CGEventTap consumes media keys when trusted. |
| Everyday lights | Screen-edge glow on volume, brightness and keyboard-backlight HUDs | toggle | on | A glow runs around every screen edge and joins the notch, filled to the level. | missing | live | `lights.hud.screenEdge` | P0 item G. Click-through overlay above the menu bar on every display; fades in 120 ms, holds, fades out after about 1.2 s idle; respects Reduce Motion and Reduce Transparency. |
| Everyday lights | Ignore mic conflicts (debug) | toggle | - | For QA environments where Core Audio keeps reporting a stale recorder. | has | stub | `wake.ignoreMicConflicts` | Item 6 (Hey Zeus). Never shown. Read only in DEBUG builds (WakeWordController); release builds always keep the call guard. |
| Everyday lights | Incoming rain alert | toggle | on | "Rain in X min" pill before a shower. | partial | live | `lights.rain` | Uses hourly forecast timing; suppresses repeat alerts for three hours after a shower starts. |
| Everyday lights | Timer light gauge | toggle | on | Outline counts down a focus session. | partial | live | `lights.timer` | Gates the closed focus wings. |
| Everyday lights | Purple glow while the mic listens | toggle | on | Glows with your voice during a spoken answer. | partial | live | `lights.micGlow` | Gates the mic-listening glow while Zeus speaks. |
| Everyday lights | Glow when a reminder is added | toggle | on | Blue crests after you add a reminder. | missing | live | `lights.reminderGlow` | Fires when ZEUS saves a reminder. |
| Everyday lights | Glow when an event is added | toggle | on | Cyan ribbon after you add an event. | partial | live | `lights.eventGlow` | Fires when ZEUS adds an event: the Calendar page quick-add, or "add lunch with Ana tomorrow at 1 pm". |
| Everyday lights | Glow when AirDrop arrives | toggle | off | Blue intake glow and drops the file on the shelf. | missing | live | `lights.airDrop` | Gated by Downloads folder access. |
| Everyday lights | Screenshot cue | toggle | off | Camera cue and shelf drop for new screenshots. | missing | live | `lights.screenshot` | Gated by Desktop folder access. |

## Notifications

| Group | Reference option | Control | Reference default | What it does | Zeus before | Zeus now | Zeus id | Note |
|---|---|---|---|---|---|---|---|---|
| Agent notifications | Permission requests | toggle | on | Alert when an agent asks. | has | custom | `notify.approvals` |  |
| Agent notifications | Finished tasks | toggle | on | Alert when an agent finishes. | has | custom | `notify.agentDone` |  |
| Agent notifications | Errors and stuck agents | toggle | on | Alert when an agent fails or stalls. | missing | live | `notify.errors` | Failed (Claude Code StopFailure, Codex error) and stalled agents get a red or amber halo and card; with this on they also send a macOS notification (when macOS allows ZEUS notifications) and a notch cue. |
| Agent notifications | Call an agent stalled after | menu | 5 min | A working agent with no events for this long turns amber. | missing | live | `notify.stallMinutes` | Checked every 20 seconds. |
| System alerts | Show system notifications (app alerts in macOS) | toggle | on | ZEUS sends focused macOS banners while the notch is closed. | missing | live | `notify.system` | Permission is requested only when you turn this on. |
| Other apps | Show notifications from other apps in the notch | toggle | off | Reads the local Notification Center store (Full Disk Access). | missing | custom | `notify.mirror` | Open question Q4, labelled Coming. |
| Other apps | Replace system banners | toggle | off | Dismisses the macOS banner once shown in the notch. | missing | live | `notify.replaceBanners` | Experimental auto-dismiss with Accessibility, gated per app. |
| Other apps | Auto-dismiss apps | text |  | Apps whose system banners are auto-dismissed. | missing | live | `notify.dismissApps` | Bundle ids, comma separated. |
| Other apps | Muted apps (Unmute) | list | empty | Apps whose notifications are hidden. | missing | custom | `notify.mutedApps` | Bundle ids, comma separated; the Settings card lists apps seen in Notification Center with Mute and Unmute. |
| Other apps | Peek new notifications under the notch | toggle | on | A slim line for about four seconds; click opens the app. | missing | live | `notify.peek` | Needs the mirror above. |
| Other apps | Show details in the peek | toggle | on | Off shows only the app name. Meeting mode hides details regardless. | missing | live | `notify.peekDetails` |  |

## Sounds

| Group | Reference option | Control | Reference default | What it does | Zeus before | Zeus now | Zeus id | Note |
|---|---|---|---|---|---|---|---|---|
| Sound feedback | Sound feedback | toggle | on | Master switch for every cue. | has | custom | `sound.on` |  |
| Sound categories | Run start sound (style + preview) | menu + play | Classic | When an agent starts. | missing | live | `sound.startStyle` | Zeus synthesized sounds (tools/sounds/make_sounds.py). |
| Sound categories | Requests sound (style + preview) | menu + play | Classic | When an agent needs you. | partial | live | `sound.approvalStyle` |  |
| Sound categories | Your answer sound (style + preview) | menu + play | Futuristic 1 | When you approve or deny. | missing | live | `sound.answerStyle` |  |
| Sound categories | Completion chime (style + preview) | menu + play | Success | When a task completes. | partial | live | `sound.doneStyle` |  |
| Sound categories | Dictation sounds | toggle | on | Cue when recording starts and ends. | has | custom | `dictation.sounds` |  |
| Sound categories | Timer alarms | toggle | on | Sound when a focus round ends. | missing | live | `sound.timer` |  |
| Sound categories | Ambient loop while an agent works | toggle | off | A quiet looping sound under a running agent. | missing | live | `sound.runningLoop` | Zeus addition. Plays the bundled running loop at half volume while any agent is working; fades out when none is. |
| Sound categories | Failure sound | toggle | on | A short sound when an agent turn fails. | missing | live | `sound.failure` | Plays the Failure sound when a session turns red (rate limit, auth or API error). |

## Voice

| Group | Reference option | Control | Reference default | What it does | Zeus before | Zeus now | Zeus id | Note |
|---|---|---|---|---|---|---|---|---|
| Voice answer | Listen for approval keywords | toggle | off | Say a keyword to answer a permission card. The microphone opens only while a card is waiting. Off until you turn it on. | partial | live | `voice.answers` | Opt-in: it opens the microphone. ZEUS also answers out loud (Answers card). |
| Voice answer | Speak replies | toggle | - | Zeus reads answers aloud with the Ultron voice. | missing | live | `voice.speakReplies` |  |
| Your keywords | Approve keywords | text | ok, yes | Comma separated; the last word counts. | missing | live | `voice.approveWords` |  |
| Your keywords | Deny keywords | text | no | Comma separated. | missing | live | `voice.denyWords` |  |
| Your keywords | Open the app keywords | text | open | Comma separated. | missing | live | `voice.openWords` |  |
| Your keywords | Reset the default words | button | - | Restores the keywords. | missing | live | `voice.resetWords` |  |

## Dictation

| Group | Reference option | Control | Reference default | What it does | Zeus before | Zeus now | Zeus id | Note |
|---|---|---|---|---|---|---|---|---|
| Local dictation | Enable local dictation | toggle | off | Dictate into any text field. | has | custom | `dictation.enabled` |  |
| Local dictation | On-device model (download, repair, status) | status + button | Not installed | 630 MB model for private transcription. | partial | live | `dictation.model` | ZEUS uses Apple on-device speech: no download. |
| Your shortcut | Dictation shortcut (Fn, modifier, pair) | recorder | Fn | Key to hold or press. | has | custom | `dictation.key` |  |
| Your shortcut | Shortcut behavior (Hold to speak, Press to start and stop) | segmented | Hold to speak | How the key works. | partial | live | `dictation.behavior` | Press toggles recording when dictation has a dedicated key; the shared talk key keeps hold/double-tap behavior. |
| Language and feedback | Dictation language (Automatic + list) | menu | Automatic | Language to transcribe. | partial | live | `dictation.language` | Selected locale is passed to Apple Speech and Whisper; Parakeet uses a script hint where supported. |
| Language and feedback | Play dictation sounds | toggle | on | Start and stop cues. | has | custom | `dictation.sounds` | Same switch as Sounds. |
| History | Dictation history (search, clear) | list | on | Saved only on this Mac. | has | custom | `dictation.keepDays` |  |
| History | Copy last dictation | button | - | Copies the last result. | missing | live | `dictation.copyLast` |  |
| History | Third-party licenses | button | - | Model licences. | missing | live | `dictation.licenses` | Apple speech: no third-party model. Opens About. |

## Shortcut

| Group | Reference option | Control | Reference default | What it does | Zeus before | Zeus now | Zeus id | Note |
|---|---|---|---|---|---|---|---|---|
| Global shortcut | Open the agent picker (Control Option Space) | toggle | on | Arrows pick a session, Return opens, Esc closes. | partial | custom | `shortcut.openNotch` | ZEUS: a preset menu for opening the notch. |
| Answer from the keyboard | Answer permissions from the keyboard (Control Option Y, N, O) | toggle | on | Approve, deny or open, live only while a request waits. | missing | live | `shortcut.answerKeys` | Registered only while a card is waiting. |

## Integrations

| Group | Reference option | Control | Reference default | What it does | Zeus before | Zeus now | Zeus id | Note |
|---|---|---|---|---|---|---|---|---|
| Available apps | Offer Claude Code for new chats | toggle | on | Shows it in New chat. | missing | live | `integrations.offerClaude` | Chat > New chat lists Claude Code only when on. |
| Available apps | Offer Codex for new chats | toggle | on | Shows it in New chat. | missing | live | `integrations.offerCodex` | Chat > New chat lists Codex only when on. |
| Connections | Claude Code connection (connect, repair, check again) | status + buttons | auto | Hooks for activity and approvals. | has | custom | `integrations.claude` |  |
| Connections | Codex connection (connect, validate, repair) | status + buttons | - | Activity follows local logs; the hook adds immediate approvals. | missing | live | `integrations.codex` | Hook installation is managed under General > Other agents. |
| Connections | Antigravity (event-driven plugin) | status | auto | Native plugin, no polling. | missing | live | `integrations.antigravity` | Detects the app. TODO: plugin. |

## Permissions

| Group | Reference option | Control | Reference default | What it does | Zeus before | Zeus now | Zeus id | Note |
|---|---|---|---|---|---|---|---|---|
| Access status | Accessibility | status + button | - | Shortcuts, keys and agent actions. | has | custom | `perm.accessibility` |  |
| Access status | Location | status + button | - | Local weather and rain alerts. | missing | live | `perm.location` | ZEUS uses a typed city, so this stays optional. |
| Access status | Calendar | status + button | - | Events and video calls. | partial | live | `perm.calendar` |  |
| Access status | Reminders | status + button | - | Read, create and complete tasks. | partial | live | `perm.reminders` |  |
| Access status | Notifications (app alerts) | status + button | - | Agent banners. | missing | live | `perm.notifications` |  |
| Access status | Full Disk Access | status + button | - | Notifications from other apps. | missing | live | `perm.fullDisk` | Only needed for the mirror (Q4). |
| Access status | Mic and speech recognition | status + button | - | Voice answers and interview. | has | custom | `perm.mic` |  |
| Access status | Screen and system audio | status + button | - | Interview transcription. | has | custom | `perm.screen` |  |
| Access status | Media control (automation per app) | status | asked when needed | Music, Spotify and browsers ask on first use. | missing | live | `perm.automation` |  |
| Trusted chats | Trusted chats (stop trusting, clear all) | list + buttons | none | Chats auto-approved except sensitive commands, cleared on quit. | missing | custom | `perm.trustedChats` | Allow this whole chat on an approval card; high-risk commands still ask. Memory only. |

## Privacy

| Group | Reference option | Control | Reference default | What it does | Zeus before | Zeus now | Zeus id | Note |
|---|---|---|---|---|---|---|---|---|
| Notification details | Show project and command details | toggle | on | Off hides commands and project names outside the notch. | missing | live | `privacy.details` | Off, or Meeting mode active: approval cards hide the command. |
| Usage data | Help improve (anonymous usage counts) | toggle | on | Daily anonymous counts. | has | live | `privacy.analytics` | ZEUS sends nothing; shown as a fact, not a switch. |
| Music metadata | Synced lyrics (LRCLIB) | toggle | off | Sends title and artist to lrclib.net. | missing | live | `privacy.lyrics` | Fetches time-synced lyrics from lrclib.net (title, artist, album, duration; no key), cached on disk. Lyrics button on the Music page and a Lyrics Home music style. Off by default as it sends data. |
| Access | Open Accessibility settings | button | - | Jumps to System Settings. | has | live | `privacy.openAccessibility` |  |

## Interview

| Group | Reference option | Control | Reference default | What it does | Zeus before | Zeus now | Zeus id | Note |
|---|---|---|---|---|---|---|---|---|
| AI provider | Provider and model | menus | - | Which AI writes the suggestions. | missing | stub | `interview.provider` | Copilot is Q3. No keys stored by ZEUS. |
| AI provider | API key (save, delete, test the connection) | field + buttons | - | Key in the keychain. | missing | stub | `interview.key` | ZEUS needs no key: it uses the CLIs on this Mac. |
| Candidate context | Candidate context | text | empty | CV, role, strengths for tailored answers. | missing | stub | `interview.context` | Stored locally for Q3. |
| Candidate context | Offer a suggestion automatically | toggle | off | Suggests without asking. | missing | stub | `interview.autoSuggest` | Q3. |
| Interviewer's voice | Capture and transcribe system audio (Deepgram) | toggle + key | off | Cloud transcription of the other person. | missing | stub | `interview.systemAudio` | Q3. Would be on-device in ZEUS. |
| Screen sharing | Hide from screen sharing | toggle | auto in meetings | Leaves shares and recordings. | has | custom | `interview.hide` |  |

## iPhone

| Group | Reference option | Control | Reference default | What it does | Zeus before | Zeus now | Zeus id | Note |
|---|---|---|---|---|---|---|---|---|
| Pairing | Connect an iPhone (pairing code, new code, disconnect) | QR + buttons | - | End-to-end encrypted pairing. | missing | custom | `iphone.pair` | Stub with design note: needs the iPhone app (Q6). |
| While agents work | Keep the Mac from sleeping | toggle | off | Same as General. | missing | custom | `general.keepAwake` | Shares the General switch. |
| Local connection | Restart the local connection | button | - | Restarts the relay. | missing | stub | `iphone.restart` | Q6. |

## Diagnostics

| Group | Reference option | Control | Reference default | What it does | Zeus before | Zeus now | Zeus id | Note |
|---|---|---|---|---|---|---|---|---|
| Status | Connection status (Connected, Offline) | status | - | Daemon reachable. | has | custom | `diag.socket` |  |
| Status | Tracked agents | list | - | Agents that sent events. | missing | live | `diag.agents` |  |
| Logs | Flight recorder: the last 2,000 app events | list | - | Voice steps, notch cues, agent events and errors, kept in memory with secrets removed. | missing | custom | `diag.logs` | Zeus addition. Filter by kind, copy the log. |
| Logs | Export diagnostics | button | - | A zip of the logs, a settings snapshot with secrets masked and the app version, saved to the Desktop or a chosen folder. | missing | custom | `diag.export` | Written by ZeusCore.DiagnosticsExporter (ditto). |
| Recovery | Restart the daemon | button | - | Running tasks stay in their apps. | missing | live | `diag.restart` | Restarts the agent socket. |

## License

| Group | Reference option | Control | Reference default | What it does | Zeus before | Zeus now | Zeus id | Note |
|---|---|---|---|---|---|---|---|---|
| License | Activate a license, key, buy, trial status | field + buttons | trial | Paid licence. | missing | custom | `license` | Trial countdown, offline Ed25519 key check, Keychain, deactivate to move Macs. No payment provider; gating off (Entitlements). |

## Assistant

| Group | Reference option | Control | Reference default | What it does | Zeus before | Zeus now | Zeus id | Note |
|---|---|---|---|---|---|---|---|---|
| Visual explanation | Enable visual explanations | toggle | off | Explain and edit diagrams in Chat with optional on-device narration. No capture starts automatically. | missing | live | `explanation.enabled` | Native opt-in Chat surface; requires an explicitly configured Any LLM endpoint. Physical-device acceptance remains pending. |
| Visual explanation | Spoken request shortcut | menu | Command-Shift-Space | Active only inside the visual explanation window. Hold the native Speak control for push-to-talk. | missing | live | `explanation.shortcut` | No global keyboard monitoring or Accessibility permission is required for this shortcut. |
| Desktop pointing | Enable desktop pointing | toggle | on | Hold the pointing keys, ask about what is under your pointer, and Zeus rings it and answers aloud. Nothing is captured until you hold the keys. | missing | live | `pointing.enabled` | On by default (owner decision, docs/FIRST-RUN-DEFAULTS.md). Needs your own Input Monitoring or Accessibility grant to see the keys, and Screen Recording to place marks. Zeus never prompts for these. |
| Desktop pointing | Pointing keys | menu | Control-Option | Control-Option is also the Talk to Zeus key: one hold is one Zeus turn that speaks in the Zeus voice and can point at the screen. Pick Right Option or Fn for a separate pointing turn that draws while held. | missing | live | `pointing.shortcut` | One hold, one turn (docs/VOICE-KEY.md). Control and Option is VoiceOver's modifier: while VoiceOver is on, Talk to Zeus moves to Option + Command and pointing on Control-Option pauses. |
| Desktop pointing | Draw while held | toggle | on | While you hold the pointing keys, your pointer leaves a trail on the screen and Zeus sees it. Clicks always reach your apps. Off: no trail is drawn; Zeus still follows the pointer. | missing | live | `pointing.drawWhileHeld` | Owner decision 2026-11-10. Drawing needs no Screen Recording permission; the ink is a Zeus overlay that is removed when you let go. |
| Desktop pointing | Send a screenshot with each question | toggle | off | Off: Zeus asks the model using only what is under your pointer. On: the display under your pointer is sent to the provider you picked, once per question, and never saved. | missing | live | `pointing.sendScreenshot` | Separate consent from the macOS Screen Recording permission. |
| Desktop pointing | Provider | menu | Auto | Auto uses the first provider with a saved key that responds, preferring the fastest it has measured this session. | missing | live | `pointing.provider` | Keys come from the Keychain only. Latency numbers stay in memory. |
| Desktop pointing | Double-tap Control to type a question | toggle | off | Two quick taps on Control open a small box to type a question about what is under your pointer. Off by default. | missing | live | `pointing.textEntry` | macOS Dictation can also use "Press Control key twice" (System Settings, Keyboard). If both are on, both fire. Turn one off. |
| Desktop pointing | Use Fn+Control for dictation | toggle | off | Sets the dictation key to Fn+Control. Turning it off puts your previous dictation key back. | missing | live | `pointing.dictationFnControl` | Off by default. Fn (Globe) alone is used by macOS for emoji and Dictation; check System Settings, Keyboard. |
| Account | ChatGPT account, model, reasoning effort, speed | sign-in + menus | - | Assistant on your ChatGPT plan. | missing | custom | `assistant.provider` | Bring your own key (OpenAI, Anthropic, ElevenLabs) in the Keychain, model picker. ChatGPT sign-in is Coming: needs an OAuth backend. |
| Model | Model | menu | - | Selected chat model for the chosen provider. | missing | custom | `assistant.model` | Provider-specific model picker on the Assistant settings page. |
| Behaviour | Double Command replies, Right Command hold to speak | toggles | - | Drafts a reply from the conversation. | partial | stub | `assistant.doubleCommand` | Hold-to-speak is the ZEUS talk key. Reply drafting TODO with the chat on devon/claude. |

## Integrations

| Group | Reference option | Control | Reference default | What it does | Zeus before | Zeus now | Zeus id | Note |
|---|---|---|---|---|---|---|---|---|
| Beamer | Beamer: start when Zeus starts | toggle | - | Opens Beamer hidden in the menu bar when Zeus starts. | missing | live | `beamer.autoStart` | Zeus addition. Beamer's own start-at-login switch is inside Beamer. |
| Beamer | Beamer: light the notch when control crosses | toggle | - | A Zeus cue when your keyboard and mouse move to another machine. | missing | live | `beamer.cue` | Zeus addition. Reads Beamer's menu bar status (Accessibility). |

## Voice

| Group | Reference option | Control | Reference default | What it does | Zeus before | Zeus now | Zeus id | Note |
|---|---|---|---|---|---|---|---|---|
| Fast path | Fast path (instant commands) | toggle | - | Simple commands run the moment you finish speaking; off sends everything to the AI. | missing | live | `fastPath.enabled` | Zeus addition. Jev is on the Engine page. |
| Hey Zeus | Listen for "Hey Zeus" | toggle | - | Say it, then your request. Off until you turn it on. | missing | custom | `voice.heyZeus` | Zeus addition. Hand-built card on Voice. Stored under wake.enabled (default off). |
| Talk to Zeus | Talk shortcut | recorder | - | Hold Control + Option to talk, let go to send. Point at something while you hold and Zeus sees what you mean. | missing | custom | `voice.talkKey` | Zeus addition. Recorder on Shortcuts. Earlier auto-written defaults move to Control + Option once; a key you record is kept. |
| Voice | Personality (Ultron or Plain) and Design voice | menu | - | How Zeus sounds and what it calls itself. | missing | custom | `voice.personality` | Zeus addition. Voice page. |
| Dictation | Murmure speech engines | menu | - | Which speech recognition writes your words. | missing | custom | `dictation.engine` | Zeus addition. Murmure page. |

## Keep awake

| Group | Reference option | Control | Reference default | What it does | Zeus before | Zeus now | Zeus id | Note |
|---|---|---|---|---|---|---|---|---|
| Insomnia | Insomnia (lid-closed mode) | toggle | - | Keep agents working with the lid closed. | missing | custom | `insomnia.lidClosed` | Zeus addition. Insomnia page. |

## Prompter

| Group | Reference option | Control | Reference default | What it does | Zeus before | Zeus now | Zeus id | Note |
|---|---|---|---|---|---|---|---|---|
| Teleprompter | Follow my presentation | toggle | - | Opens the prompter when a slideshow starts. | missing | custom | `prompter.followPresentation` | Zeus addition. Features page; stored under the prompter key. |
| Teleprompter | Advance slides when I finish their notes | toggle | - | Voice-follow moves to the next slide. | missing | custom | `prompter.followAdvances` | Zeus addition. Features page. |
| Teleprompter | Hide the prompter from screen sharing | toggle | - | You see it; shares do not. | missing | custom | `prompterWindow.private` | Zeus addition. Features page. |

## Agents

| Group | Reference option | Control | Reference default | What it does | Zeus before | Zeus now | Zeus id | Note |
|---|---|---|---|---|---|---|---|---|
| Browser agent | Let Zeus work in Chrome | toggle | - | Web tasks, step by step, with a card you can stop. | missing | live | `browserAgent.enabled` | Zeus addition. |
| Browser agent | Most steps per task | menu | - | Where a web task stops and tells you. | missing | live | `browserAgent.maxSteps` | Zeus addition. |
| Browser agent | Always ask before | text | - | Extra words that always show an approval card. | missing | live | `browserAgent.alwaysAsk` | Zeus addition. Added to the built-in list (buy, send, delete, post...). |
| Browser agent | Browser for the agent | menu | - | Your own Chrome through the ZEUS extension, or a separate browser (browser-use) with its own profile. | missing | live | `browserAgent.backend` | Zeus addition. The separate one needs the Set up button once; `zeus browse --separate` forces it for one task. |
| Browser agent | Allowed sites (separate browser) | text | - | Sites the separate browser may open, separated by commas. Empty means any site. | missing | live | `browserAgent.allowedDomains` | Zeus addition. Passed to browser-use as BROWSER_USE_ALLOWED_DOMAINS and checked before every open. |
| Scribe | When a meeting starts | menu | - | Off, ask first, or start notes on its own when a call or calendar meeting begins. | missing | live | `scribe.autoStart` | Zeus addition. Settings > Features > Scribe. Start automatically needs Microphone to be allowed already; otherwise Zeus asks. Never prompts for permission. |
| Coding | Default coding agent | menu | - | Claude Code, Codex, Gemini or Cursor Agent. | missing | custom | `code.tool` | Zeus addition. Stored under the code.tool key. |
| Coding | Terminal app | menu | - | Automatic, Ghostty, iTerm, Warp or Terminal. | missing | custom | `code.terminal` | Zeus addition. Stored under the code.terminal key. |
| Research | Research depth | menu | - | Quick or Deep when you do not say deep research. | missing | live | `research.depth` | Zeus addition. |
| Research | Save reports in | text | - | A folder for research reports. | missing | live | `research.folder` | Zeus addition. Empty keeps the second brain, else Documents/Zeus Research. |
| Models | Models Zeus uses (read-only) | status | - | Which model each engine uses, never above Haiku or Sonnet. | missing | custom | `models.caps` | Zeus addition. Read-only display of ModelCap. |
| Drive | When Zeus may drive your Mac | menu | - | How much Zeus may do on its own on your Mac. | missing | custom | `privacy.driveAutonomy` | Zeus addition. Privacy page; stored under drive.autonomy. |
| Drive | Move the system pointer | toggle | - | Drive mode may glide and click with CGEvent when Accessibility cannot. | missing | live | `present.physicalPointer` | L5. Off by default. Key present.physicalPointer. |

## Zeus additions beyond the reference app

- Search box in the Settings sidebar (every option, section titles and notes; Return opens the first hit).
- Live preview card on Appearance (halo style, arm width, thickness and cues drawn as you change them).
- Reset this section to defaults (header button on every page).
- Export and import all settings as JSON (General).
- Keyboard navigation: Up and Down move between sections, Command F focuses search, Escape clears it.
- Sections the reference app does not have: Top Bar (tab order, weather city and units), the To-do quick-add shortcut, second-brain rows.
