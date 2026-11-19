# Notch sound output list: plan and design

Written 14 November 2026 against `codex/island-20261113` at `9f2ffe4`, revised the same day after review (see "Review
notes"). It follows `docs/NOTCH-MUSIC-PLAN.md`, `docs/NOTCH-SURFACE-PLAN.md`, `docs/NOTCH-SOURCES-PLAN.md` and
`docs/NOTCH-EQUALISER-PLAN.md` and redoes none of them. Same rules: pure rules in ZeusCore with tests first,
`docs/DESIGN-DIRECTION.md` for anything visible, nothing accepted until the named tests run on macOS and the behaviour
is seen on a Mac. Public interfaces only: Core Audio device properties and the Network framework's service browser.
There is no private system call in this plan, so nothing is loaded at run time and there is no symbol to check. Line
numbers were read on `9f2ffe4`; the two house plans cite `47566d1`, where the output block sat at
`TopBarServices.swift:196-212` (it is `:211-227` now).

**Refactor first: no.** The output menu today holds no state at all, so there is nothing to untangle: about 35 lines
are replaced by one reducer, one controller and one view, and the Core Audio reader is kept and extended. One small
enabling ticket (O0) adds a notch cue for a sound notice, because the permission cue cannot carry one.

## The output menu Zeus has today, and the verdict

| Fact | Where |
| --- | --- |
| The Music page has one output button; it calls a closure on the model | `TopBarViews.swift:579`, `:591-609`, `TopBarModel.swift:246-247` |
| The closure builds an `NSMenu` and pops it up at the pointer; `popUp` blocks until the menu closes | `TopBarServices.swift:47`, `:213-227` |
| A row is a name and a checkmark; nothing says what kind of output it is | `TopBarServices.swift:217-220` |
| The list is every device with an output channel and a name; hidden devices, devices that cannot be the default and Zeus's own tap aggregates are not filtered | `OutputDevices.swift:12-18`, aggregates at `SystemAudioTap.swift:43-50`, `ScribeLiveCapture.swift:630` |
| A pick writes the default output and throws the result away; nothing is read back | `OutputDevices.swift:20-27`, `:74-77` |
| The pick carries the object id read when the menu was built, not a stable identifier | `TopBarServices.swift:219` |
| The only caller in the repository is that button (grep of `Sources`, `Tests`, `scripts`) | `TopBarViews.swift:597` |
| No test covers any of it (grep of `Tests/` for `OutputDevices` and `chooseOutputDevice`: nothing) | n/a |
| The default output has two more readers and one listener that lives as long as the app, all for volume | `FastActions.swift:439-446`, `TopBarServices.swift:460-476` |
| Nothing in Zeus browses the network for services; the only Network framework use is a path monitor | `InsomniaController.swift:60`, `:247` |

**Verdict: replaced on screen, extended underneath.** The `NSMenu` path (`TopBarServices.swift:211-227`) and its
target object (`OutputDevices.swift:69-78`) are removed. The reader `OutputDevices` (`:5-67`) stays and gains the
facts it does not read today. The button stays where it is and opens a list drawn inside the Music page. A menu cannot
do the job: it blocks while open, so it cannot follow a headset being plugged in; it closes on the pick, so a failed
switch has nowhere to be shown; it cannot host a part that asks for a permission only when opened; and it is a system
menu window, outside the windows `ZeusWindowSharing.refresh` walks (`ZeusWindowSharing.swift:45-52`). Whether that
menu window is hidden from a screen share today is unverified; the list in the notch panel is covered by the rule
(`NotchController.swift:122-127`).

## The state machines

Two, both pure, both new, both in ZeusCore.

- `OutputList` (O2): `closed`, `open`, `settling`. One value holds the routes, the switch in flight and the last
  failure. The "Current" mark is never a guess: it is always what Core Audio last reported.
- `SpeakerDiscovery` (O5): `off`, `collapsed`, `searching`, `found`, `waitingForAccess`, `unavailable`. Turning the
  setting on only reaches `collapsed`; the browse, and so the system prompt, starts on `partToggled` and nowhere else.

Controllers run effects and hold one state value each. Every delay and every deadline is an effect carrying a token;
the reducer drops a late answer. There is no flag, timer or tracker outside the two values.

| Ticket | Gap | Today | After |
| --- | --- | --- | --- |
| O0 | Notice cue | The only text cue for a problem is the permission cue: a lock, and a macOS banner titled "Zeus needs access" | A sound notice cue: a speaker symbol, in the notch only, never a banner |
| O1 | Route model | A device is an id, a name and a Bool | A route value: stable id, cleaned name, transport, symbol, spoken word; one filter; one order |
| O2 | Switch and read back | The write's result is discarded; the checkmark is from a read made before the menu opened | A reducer: pick, write with a deadline, two read-backs, an honest result; live list while open |
| O3 | Reader, listeners, controller | Private helpers, no listeners on the device list | The reader returns facts; listeners exist only while the list is open; the menu path is gone |
| O4 | The list on screen | A system menu at the pointer | Rows in the Music page: symbol, name, status word with a symbol; VoiceOver; Reduce Motion |
| O5 | Network speaker rules | None | Name cleaning, de-duplication, kind from the service record, the discovery reducer |
| O6 | Browse and consent | None | A browser that runs only while that part is open; setting off by default; usage string; status row |

## Worktrees and order

| Ticket | Files it owns | Runs |
| --- | --- | --- |
| O0 | `Sources/ZeusCore/TopBar/TopBarLayout.swift` (one case after `:255`, one duration arm), `TopBarViews.swift` (one arm each in `cueIcon` `:1493-1513` and `cueDetail` from `:1519`), `TopBarModel.swift` (`:366`), new `Tests/ZeusCoreTests/SoundNoticeCueTests.swift`, new `Tests/ZeusAppTests/SoundNoticeBannerTests.swift`, its `qa/feature-map.json` entry | First, parallel with O1 |
| O1 | new `Sources/ZeusCore/Audio/ZeusAudioDevices.swift` and its test (unless equaliser B2a has merged), new `Sources/ZeusCore/TopBar/OutputRoutes.swift`, new `Tests/ZeusCoreTests/OutputRoutesTests.swift` | First, parallel with O0 |
| O2 | new `Sources/ZeusCore/TopBar/OutputList.swift`, new `Tests/ZeusCoreTests/OutputListTests.swift`, `docs/STATE-MACHINES.md` | After O1, parallel with O5 |
| O3 | `OutputDevices.swift`, new `TopBar/OutputDeviceListener.swift`, new `TopBar/OutputListController.swift`, `TopBarServices.swift` (`:47`, `:211-227`, three observers beside `:113-119`), `TopBarModel.swift` (one property, the comment at `:246`), `test_source_lint.py`, new `Tests/ZeusAppTests/OutputListControllerTests.swift` and `OutputDevicesReadTests.swift`, their feature-map entries | After O0 and O2, parallel with O4 |
| O4 | new `TopBar/OutputListView.swift`, `TopBarViews.swift` (`:536-579`, `:591-609`), `SnapshotRenderer.swift` (one fixture), new `Tests/ZeusAppTests/OutputListViewTests.swift`, its feature-map entry | After O0 and O2, parallel with O3; merges after O3 |
| O5 | new `Sources/ZeusCore/TopBar/NetworkSpeakers.swift`, new `Tests/ZeusCoreTests/NetworkSpeakersTests.swift`, `SpeakerDiscoveryTests.swift`, `docs/STATE-MACHINES.md` | After O1, parallel with O2 |
| O6 | new `TopBar/SpeakerBrowser.swift`, new `TopBar/SpeakerDiscoveryController.swift`, new `TopBar/NetworkSpeakersSection.swift`, one line each in `OutputListView.swift`, `TopBarServices.swift` and `TopBarModel.swift`, `App/AppDelegate.swift` (one case at `:884-899`, one action at `:900-920`), `Resources/Info.plist`, `SettingsStore.swift`, `GlanceSettingsPages.swift` (`:1142-1146`), the settings generator and its outputs, `test_source_lint.py`, App tests, their feature-map entries | Last, alone, after the owner's yes on D5 |

Tickets that run in parallel own no file in common, with one exception: O3 and O4 each add an entry to
`qa/feature-map.json`, so O3 merges first and O4 rebases its entry (as equaliser B2b and B4 do). Step zero (below)
comes before O5 and O6 are scheduled. O2 and O5 both append to `docs/STATE-MACHINES.md`: O2 merges first. Every
branch appends to `qa/regressions.json` from the block REG-540 to REG-559 (clashes go through
`~/AI-Brain-build/zeus-merge-reg.py`). Branch names `codex/output-<ticket>-YYYYMMDD`; builds in
`~/AI-Brain-build/<name>-build`, never inside OneDrive.

Overlap with waves in flight. Whichever branch merges second rebases, then repeats its Mac build.

| File | Who else edits it | How it is settled |
| --- | --- | --- |
| `TopBarServices.swift` | Sources A1 moves the music block out and leaves the output block | O3 touches `:47`, `:211-227` and adds three observers beside `:113-119` |
| `TopBarViews.swift` | On `9f2ffe4`, A1 edits `:111`, the Open label at `:583` (cited as `:567` on `47566d1`) and adds a page appear hook; A4 edits the controls (`:505-526`, `:577-584`) | O4 edits `:536-579` and `:591-609`, so the control row `:577-584` is shared, one line each. O4 rebases onto A1 and A4 when they land first |
| `TopBarLayout.swift` | A4 changes `.trackChanged` (`:237`) | O0 adds a case after `:255`. Both touch the exhaustive switches in `cueIcon` and `cueDetail`, which only a Mac compile checks |
| `OutputDevices.swift`, the own-aggregate rule | Equaliser B2a defines `ZeusAudioDevices.isOwnAggregate` (`NOTCH-EQUALISER-PLAN.md:178`); B2b applies it in `ids()` (`:216`) | One rule under that one name. If O1 lands first it creates the rule in a neutral file and B2a reuses it; if B2a lands first O1 creates no file. O3 rewrites `ids()`, so B2b's filter line lives in the pure rule either way |
| `AppDelegate.swift` | B2b (controller wiring), B3 (a catalog case beside `:894`) | O6 adds a catalog case and an action: other lines of the same switch. O6 is last and rebases |
| `SettingsStore.swift`, the Privacy Music card, the generator | Sources A3 (import list, `SettingStatus`, a privacy row) | O6 rebases onto A3 and re-runs the generator on the merged table |
| `test_source_lint.py`, `qa/feature-map.json` | A3, B2b and B3 append lints; B2b and B4 add entries | O3 and O6 append lints. Entries merge in the order O0, O3, O4, O6 |

## Step zero, on a Mac, before O5 and O6 are scheduled

1. Pick a wireless speaker in Control Center, then list Core Audio devices with their transport codes. This settles
   whether such a speaker ever appears as a device with transport `airp` on 27.2 (open in the study, one report says
   no). If it does, O1 to O4 already list it and can switch to it; O5 only improves its symbol.
2. In Terminal (tools run from Terminal are exempt from the Local Network rule, per TN3179): `dns-sd -B _airplay._tcp`
   and `dns-sd -B _raop._tcp`, then `dns-sd -L` on one of each. Record the name shapes and whether the record keys
   `model` and `am` are present. O5's kind rule rests on them and is unverified until then.
3. Write the default output to a pair of connected Bluetooth headphones from a scratch script and watch five seconds:
   how long until the default reads back as the pick, and does macOS move it back? This sizes both read-backs in O2.
4. Open today's output menu during a screen share with "show Zeus in screen shares" off: is the menu visible to the
   viewer? This records the gap the replacement closes.

## Open source checked first

Licences are as recorded in the research verification of 13 November 2026; no LICENSE file was re-read for this plan.

| Need | Project | Licence | Use |
| --- | --- | --- | --- |
| Read and write the default output | deweller/switchaudio-osx | MIT | Technique only: one property write. Zeus's reader is its own and already exists |
| A typed device model with a transport field | rnine/SimplyCoreAudio | MIT, archived | Technique only |
| Routing sound to a wireless speaker from an app | stonerl/cacophony, jgarms/airlift | MIT | Not used: both rest on a private call that the study found refused for a process without the vendor's entitlement |
| Service type names for wireless speakers | bpetrynski/airplay-cli | MIT by its README | Technique only: the two type names |
| Output pickers inside notch utilities | Three projects of that category, listed in the private study | GPL-3.0 | Technique only. No code is read into Zeus |
| Interface facts | CoreAudio headers, the Network module interface and `dns_sd.h` in the local macOS 27.2 SDK; Apple TN3179 | n/a | See "System interfaces relied on" |

No code is copied, nothing is bundled, no package is added, so no notice file changes and no licence duty arises.

### System interfaces relied on, and where each was verified

| Interface | Verified in |
| --- | --- |
| `kAudioHardwarePropertyDevices`, `kAudioHardwarePropertyDefaultOutputDevice`, `kAudioHardwarePropertyDefaultSystemOutputDevice` | `AudioHardware.h:608-611`, SDK 27.2 |
| `kAudioDevicePropertyTransportType`, `...DeviceIsAlive`, `...DeviceCanBeDefaultDevice`, `...IsHidden` | `AudioHardwareBase.h:743`, `:746`, `:748`, `:757` |
| `...DeviceCanBeDefaultDevice` answers for input or output "depending on the scope", so it is read with the output scope, as the stream configuration already is (`OutputDevices.swift:49-50`) | `AudioHardwareBase.h:681-684`; the study's contract names the output scope too |
| Transport codes `bltn`, `grup`, `virt`, `pci `, `usb `, `1394`, `blue`, `blea`, `hdmi`, `dprt`, `airp`, `eavb`, `thun`, `ccwd`, `ccwl`, `rscr`, `rstr` | `AudioHardwareBase.h:607-624` |
| `NWBrowser`, descriptor `bonjourWithTXTRecord(type:domain:)`, result metadata `.bonjour(NWTXTRecord)`, state `.waiting(NWError)`, `NWError.dns`; `kDNSServiceErr_PolicyDenied = -65570` | Network module interface, lines 185-275, 594; `dns_sd.h:801` |
| Service browsing needs Local Network permission from macOS 15; without it the browser sits in a waiting state with that code, and waiting is not an end state; no call reads or requests the permission; the choice is kept per user account; a build not signed with a vendor-issued identity may not keep the choice | Apple TN3179, fetched again 14 November 2026 |
| Whether the waiting state also appears while the system alert is still up, before any answer | Unverified: TN3179 does not say. O5 is correct for either order; O6 records it on a Mac |
| Whether `NSBonjourServices` is required on macOS | Unverified: TN3179 says to list browsed types and does not say macOS enforces it. O6 declares both keys |
| Record keys `model` and `am`, and the id prefix on `_raop._tcp` names | The study and public protocol notes only. Unverified until step zero |
| The settings links for the Sound pane and the Local Network pane; that a private aggregate appears in its creator's own device list | Unverified on 27.2. Fallback for the links: open System Settings itself. The aggregate is assumed listed, as the equaliser plan assumes |
| Every symbol name in O0 to O6 exists on the package floor (macOS 14.2, `Package.swift:6`) | The system symbol availability list on this Mac: the newest are `cable.connector` and `beats.headphones` (macOS 12) and `airpodsmax` (11.3) |

## Privacy and consent

| Topic | Rule |
| --- | --- |
| O0 to O4 | No permission, no entitlement, no plist key. Reading device properties and writing the default output never prompt. Nothing is captured, stored or sent. Device names stay in memory while the list is open. Nothing is saved, so quitting mid-switch needs no cleanup: the listeners end with the process |
| The failure notice | A notice about a switch that failed after the list closed is drawn in the notch only (O0). It is never a macOS banner, so no device name reaches Notification Centre or the lock screen. The flight recorder keeps the cue's case name only (`TopBarModel.swift:390-392`) |
| O5 and O6 | One permission, Local Network, behind one setting, `music.networkSpeakers`, off by default. It joins `SettingsStore.neverEnabledByImport` (`SettingsStore.swift:255-258`) and the generator's `opt_in` tuple (`gen-settings-catalog.py:243-246`), so an imported file can turn it off or leave it alone and never turn it on |
| Two gates, in order | The owner turns the setting on (Privacy page). Then the owner opens the "On the network" part of the list. Only that second act starts a browse, and the first browse is what makes macOS ask. Never at launch, never from the permission sweep or onboarding (lint, O6), never from a test, never from turning the setting on. On macOS 14, which `Package.swift:6` still allows, the Local Network rule does not exist (TN3179): no prompt can appear, and the setting plus the open are the only gates |
| What the browse does | It only listens for service announcements. Zeus never resolves a service, never opens a connection to a speaker and never learns its address (lint: no `NWConnection` in the browser file). Names live in memory while the part is open and are dropped when it closes. They are never written to disk, logged, shown in diagnostics or given to a model, voice, chat or agent context. Logs carry counts and state names only. Zeus never claims it can play to a speaker it only knows by name: those rows are not buttons |
| Screen sharing | The list is drawn in the notch panel, so device and speaker names follow the screen-share setting like the rest of the notch. No new window, so `ZeusWindowSharing` needs no new entry |
| Tests | No test writes the default output, installs a listener or touches the network: controllers take their reader, listener and browser by injection with no live default, and a lint keeps the live names out of `Tests/`. One App test reads device properties and writes nothing (O3) |

When the system vendor closes a route, the owner sees:

| What changes | What the owner sees |
| --- | --- |
| The transport property stops answering | A plain speaker symbol and the spoken word "Other". The list and the switch still work |
| The default-output write is refused, quietly ignored or never returns | "Not switched" with a warning symbol on that row (after five seconds for a call that stalls); "Current" stays on the output that is really playing |
| macOS moves the sound away after the switch held | "Did not stay" on that row within two seconds, or one notch cue "Sound moved to <output>" if the list is already closed |
| Wireless speakers are not Core Audio devices | They are names in the network part only, with "Sound settings" as the way to pick one |
| Local Network is refused, or service browsing is changed or removed | "No access" with a button to the system pane, or "Not available". The device rows above are untouched |

## Abuse and hostile input

| Route | How it is closed |
| --- | --- |
| Another program of the same user changes the default output, or adds and removes devices, while Zeus switches | The mark follows Core Audio, never the pick. A read-back that differs is reported in words that stay true if someone else moved the sound. Change notices are coalesced: one read in flight, one queued, whatever the burst. At most 32 routes are kept |
| A virtual or aggregate device named like the built-in speakers or like headphones, placed to receive the sound | The symbol and the spoken word come from the transport Core Audio reports, never from the name. Name-based art applies only inside transport Bluetooth. Zeus switches only on a press on a row |
| A device named "Zeus spectrum" or "Zeus Scribe" by another program, to stay out of the list | It is hidden from Zeus's list only and can never be picked there. It closes fully when Zeus's aggregates carry a UID prefix (see "Out of scope") |
| A switch triggered without the owner | Lint (O3): the write is called from one file; `Intent/**`, `Voice/**`, `Chrome/**`, `App/DeepLinks.swift`, `App/DebugCommands.swift` and the CLI target never name it. No setting stores a "preferred output", so an import cannot move sound either |
| A hostile device name (a Bluetooth peer or a driver chooses it): control characters, direction overrides, newlines, kilobytes | `OutputName.clean` strips them and caps the length; rows draw with `Text(verbatim:)`; a name is never put in a log line, a URL, a script, a prompt or a macOS banner |
| A device name pushed onto the lock screen or kept in Notification Centre through the failure notice | The notice is a cue with no banner form (O0, tested) |
| A network peer announcing hostile names or records: imitation of a real device, thousands of services, oversized records | The same cleaning; 128 sightings read, 24 rows drawn; one row per folded name; only two record keys read, ASCII, 64 characters, matched by prefix to a closed set; anything else is a plain speaker. Network rows sit in their own part and cannot change routing |
| A peer taking the name of a real route to hide or replace it | A network name equal to a listed route is not drawn in the network part. The route row keeps its own name, transport and action; the peer can at most change the art of a wireless route |
| An imported file or an edited preference turning discovery on | Import: refused by `neverEnabledByImport`. A direct edit by a same-user program can set the switch, as it can for any preference; even then nothing browses until the owner opens the part, and the system permission still applies |
| A forged "allowed" in the stored status | The key only feeds a status row. It is not in `appRules` (`SettingsStore.swift:241-248`), so it is not imported, and it never gates a browse |
| A stale device identifier | A pick carries the device UID; the object id is looked up again at the moment of the write. A device that is gone gives "Not switched" and no write |
| A Core Audio call that never returns (a device waking, a broken driver) | Every read and write has a five-second deadline in the reducer; reads and the write use separate queues, so one cannot hold the other |
| Rows moving under the pointer as a device arrives | The order is stable: a pick never reorders rows and "Current" moves in place. A device arriving can still shift later rows once; the action carries the UID of the row as drawn and the result is read back and shown |
| Names of the owner's devices or the neighbours' speakers leaking into a shared screen or a log | Drawn in the notch panel under the capture rule; never logged |

## O0. Notice cue

A new cue, `NotchCue.soundNotice(String)`, shows one line with a speaker symbol in the closed notch. O3 raises it when
a switch fails after the list has closed. It is shown even when everyday cues are off, because it answers an act of
the owner, and it has no macOS banner form. The permission cue cannot be used: `.hint` means "a feature needs a
permission" (`TopBarLayout.swift:249-250`), draws `lock.fill` (`TopBarViews.swift:1505`) and becomes a banner titled
"Zeus needs access" (`SystemNotificationService.swift:41-42`) whenever the notch is closed
(`AppDelegate.swift:127-131`), and that banner is kept in Notification Centre.

| File | Change |
| --- | --- |
| `TopBarLayout.swift` | `case soundNotice(String)` after `.screenshot` (`:255`); duration 3.5 s (`:258-273`) |
| `TopBarViews.swift` | `cueIcon` gains `("speaker.wave.2.fill", Theme.ember)`; in `cueDetail` the case joins the plain text arm (`:1547`) |
| `TopBarModel.swift:366` | The case joins the essential list. `SystemNotificationPayload.forCue` (`SystemNotificationService.swift:33-49`) is not edited: its `default` arm already returns nil, and the test below keeps it so |

Tests first. `SoundNoticeCueTests` (Core): the duration. `SoundNoticeBannerTests` (App): `forCue(.soundNotice("x"))`
is nil; `systemNotificationAllowed` is false; `show(.soundNotice("x"))` with cues off still sets `cue`; a recording
`onSystemNotification` is never called. Only at the Mac: the cue in the closed notch, and nothing in Notification
Centre afterwards.

## O1. Route model

### Behaviour

- An output is listed when it has an output channel, a UID, a name left after cleaning, is alive, is not hidden and
  can be the default. A flag that cannot be read counts as acceptable, as today, because every switch is read back.
- Zeus's own aggregates are never offered: "Zeus spectrum" and "Zeus Scribe" today, any UID starting `app.zeus.` later.
- The device that is the default right now is always listed, whatever its flags and even if it is Zeus's own, so
  "Current" is never missing. This rule wins over every filter. Pressing the current row does nothing.
- Order: built-in, wired, display, Bluetooth, wireless speaker, virtual, other; inside a group by name (case and
  diacritics ignored, digits as numbers), then by UID. Nothing moves when the default changes.

### Rules (ZeusCore, pure)

New files: `Sources/ZeusCore/Audio/ZeusAudioDevices.swift` (the first row) and
`Sources/ZeusCore/TopBar/OutputRoutes.swift` (the rest). No CoreAudio import; codes are plain `UInt32`.

| Name | Rule |
| --- | --- |
| `ZeusAudioDevices.isOwnAggregate(uid:name:)` | True for a UID starting `app.zeus.` (which covers the equaliser's `app.zeus.eq.`) or the names "Zeus spectrum" and "Zeus Scribe". Today's two aggregates use a random UUID (`SystemAudioTap.swift:45`, `ScribeLiveCapture.swift:631`), so they match by name only. The one rule the output list, the microphone list and the equaliser share |
| `OutputDeviceFacts` (Sendable) | `objectID`, `uid`, `name`, `transportCode`, `outputChannels`, `canBeDefault`, `isHidden`, `isAlive`; optionals are nil when the read failed. `outputChannels` and `canBeDefault` are output-scope facts; O3's address table is tested for it |
| `OutputTransport` | `builtIn`, `wired`, `bluetooth`, `wirelessSpeaker`, `display`, `virtual`, `other`. `init(code:)`: `bltn` built-in; `usb `, `thun`, `1394`, `pci `, `eavb` wired; `blue`, `blea` Bluetooth; `airp` wireless speaker; `hdmi`, `dprt` display; `virt`, `grup` virtual; nil, 0 and every other code `other`. `word`: "Built-in", "Wired", "Bluetooth", "Wireless speaker", "Display", "Virtual", "Other" |
| `OutputSymbol.name(transport:name:)` | `speaker.wave.2`, `cable.connector`, `headphones`, `airplayaudio`, `display`, `square.on.square.dashed`, `hifispeaker`. Inside Bluetooth only, a name containing "AirPods Max", "AirPods Pro", "AirPods" or "Beats" (longest first, case ignored) takes `airpodsmax`, `airpodspro`, `airpods` or `beats.headphones`. Every name is in `OutputSymbol.all`; `OutputSymbol.fallback` is `speaker.wave.2`, drawn by the app when the system has no image for a name |
| `OutputName.clean(_:) -> String?` | Drops control and format scalars (direction overrides and zero-width marks included, the emoji joiner kept), line and paragraph separators; folds whitespace to single spaces; trims; keeps at most 48 characters; nil when nothing is left |
| `OutputRoute` (Identifiable by `uid`, Sendable) | `uid`, `objectID`, `name`, `transport`, `symbol`, `isCurrent` |
| `OutputRouteRules` | `routes(from:defaultObjectID:locale:) -> [OutputRoute]`: filter through `isOwnAggregate`, clean, order, cap at 32, the default always kept. `spokenValue(for:status:)`, such as "Bluetooth, current" |

Fail closed: an unreadable name or UID drops the device; an unknown code is `other`; an empty result is an empty list,
which O4 draws as "No outputs found".

### Tests first (`OutputRoutesTests.swift`, `ZeusAudioDevicesTests.swift`)

Every code in the header maps, and nil, 0 and an invented code give `other`; hidden, dead, cannot-be-default,
channel-less and Zeus-owned devices are dropped; the current default survives every filter, a Zeus-owned default
included; unreadable flags are kept; order by group, then name, then UID, and unchanged when the default moves; the
cap; cleaning (a direction override, a newline, a 4,000-character name, only-control input gives nil, an emoji
sequence survives); name art only inside Bluetooth (a virtual device called "AirPods Pro" keeps the virtual symbol);
the spoken value; own-aggregate UIDs and names, and a plain UUID with another name is not own; every word and symbol
name free of U+2014 and U+2013.

Only at the Mac: the symbols read well at 16 pt beside each real device the owner has.

## O2. The list and switch reducer

### Behaviour

- Opening the list reads the outputs and listens for changes. Closing it stops both.
- A press on a row that is not current starts a switch: the row reads "Switching" and the mark does not move yet. A
  second press replaces the first and the older result is dropped. A press on the current row only clears a failure.
- The write runs, then the default is read back after 0.25 s and again after 2 s. When the first read names the
  pick, the row becomes "Current". When the write fails, does not return within 5 s, the device is gone, or the first
  read names another output, the row reads "Not switched" and "Current" stays where the sound really is.
- When the first read named the pick and the second names another output, the row reads "Did not stay": true whether
  macOS moved the sound back or the owner moved it in Control Center. Zeus does not claim the switch failed. A
  failure stays until the next press, until the list closes, or until Core Audio reports that row as current.
- If the list closes while a switch is settling, the checks still run. A failure then raises one notch cue: "Could
  not switch to <name>" or "Sound moved to <current name>"; VoiceOver hears the same sentences, and "Sound is on
  <name>" on success. Reopening before the checks end keeps the pending switch; its result shows in the list, no cue.
- Sleep, a locked screen or a switch to another user ends everything quietly: listeners stop, a pending switch is
  dropped, no cue follows. Bluetooth drops during sleep, so a check made after wake would report a false failure.

### Rules (ZeusCore, pure)

New file `Sources/ZeusCore/TopBar/OutputList.swift`:

| Name | Rule |
| --- | --- |
| `State` | `closed`; `open(Open)`; `settling(Pending)`. `Open`: `routes`, `pending`, `failure`, `reading` (a token or nil), `readQueued`, `loaded`, `run` (a counter that makes tokens) |
| `Pending`, `Failure` | `Pending`: `uid`, `name`, `token`, `step` (`writing`, `firstCheck`, `secondCheck`), `retried`. `Failure`: `uid`, `name`, `reason`: `deviceGone`, `refused(Int32)`, `timedOut`, `elsewhere`, `unread`, `left(current: String?)` |
| `Event` | `toggled`, `closed`, `interrupted`, `picked(uid)`, `devicesChanged`, `facts(token, [OutputDeviceFacts], defaultObjectID)`, `writeFinished(token, Int32?)`, `readBack(token, uid: String?, name: String?)`, `expired(token)` |
| `Effect` | `startListening`, `stopListening`, `readDevices(token)`, `write(token, uid)`, `readBackAfter(token, seconds)`, `expireAfter(token, seconds)`, `announce(String)`, `cue(String)` |
| `toggled` | `closed` opens: `startListening`, `readDevices`. `open` acts as `closed`. `settling` reopens with its pending switch kept: `startListening`, `readDevices` |
| `closed` | From `open` with a pending switch: `settling`; otherwise `closed`. Both emit `stopListening` |
| `interrupted` | Any state becomes `closed`; `stopListening` if it was open; the pending switch is dropped and the counter moves on, so every late answer is stale. No cue, no announcement |
| `devicesChanged` | Only in `open`: while `reading` it sets `readQueued`, else `readDevices`. Ignored in `closed` and `settling` (a listener block already queued when the listener stopped) |
| `facts` | Rebuilds routes through O1; a pending device missing from them fails as `deviceGone`; a failure whose route is now current is cleared; one more read if `readQueued` |
| `picked` | In `open`, for a listed UID that is not current: `write` and `expireAfter(token, 5)`. Any other pick does nothing |
| `writeFinished` | nil is `deviceGone`; a non-zero status is `refused`; zero asks `readBackAfter(token, 0.25)` |
| `expired` | For a pending switch still `writing`: `timedOut`. For the read in flight: `reading` is cleared, routes are kept, and one more read runs only if `readQueued`. Every `readDevices` carries its own `expireAfter(token, 5)` |
| `readBack`, first check | The pick: the mark moves in place, `announce`, `readBackAfter(token, 2)`. Another UID: `elsewhere`. nil (the default could not be read): one retry after 0.25 s, then `unread` |
| `readBack`, second check | The pick: done. Another UID: `left(current:)` with that output's cleaned name. nil: done, the first check stands |
| A failure | In `open`: stored and announced. In `settling`: exactly one `cue`, then `closed` |
| `rows(_:) -> [OutputRow]` | Route, symbol and `OutputRowStatus`: `none`; `current` ("Current", `checkmark`); `switching` ("Switching", `arrow.triangle.2.circlepath`); `failed` ("Not switched", `exclamationmark.triangle`) for every reason but `left`; `left` ("Did not stay", `arrow.uturn.backward`) |
| `OutputListText`, `State.snapshotSample` | The three sentences above, and "Sound left <name>" when the current output has no usable name. The sample: five routes, one current, one failed |
| `OutputListControlling` | `@MainActor public protocol ... : AnyObject` with `state`, `toggle()`, `close()`, `pick(uid:)`. Views can only express the owner's three acts |

`docs/STATE-MACHINES.md`: one new entry under the next free number, "EXPLICIT from the start". The reducer knows
nothing of the network part or of `TopBarModel`; those are wired in O3 and O6. Fail closed: any result whose token
is not the live one is dropped; a failure never moves the mark; nothing is marked current without a read that names
it; `closed` and `interrupted` from any state stop listening.

### Tests first (`Tests/ZeusCoreTests/OutputListTests.swift`)

| Group | Cases |
| --- | --- |
| Open and pick | Open emits listen then read; a second `toggled` closes and stops; a pick emits one write with its deadline and shows "Switching" with the mark unmoved; a second pick supersedes and every late event of the first is dropped; a pick of the current row or of an unknown UID emits nothing |
| Write and checks | Status 0 then two matching read-backs leave no pending and no failure; a refused write fails with no read-back; `writeFinished(nil)` fails as gone and asks for a fresh read; `expired` during the write gives `timedOut`, and a `writeFinished` after it changes nothing; a first read-back naming another output is `elsewhere` and never marks the pick; a nil first read-back is retried once, then `unread`; a second read-back naming another output is `left` with that name, and a nil one leaves no failure; a failed route that turns current loses its failure |
| Reads | 100 `devicesChanged` during one read give exactly one more read; `devicesChanged` in `closed` and in `settling` emits nothing; `expired` during a read clears `reading` and reads again only when a change was queued; a pending device vanishing from `facts` fails |
| Closing | Closing mid-switch gives `settling`, a later failure gives exactly one `cue` and then `closed`, a later success gives none; `toggled` in `settling` reopens with the pending switch and a later failure gives no `cue`; `interrupted` from `open` and from `settling` gives `closed`, no `cue`, and drops every later answer; `closed` always emits `stopListening` |
| Words and types | A `@MainActor` fake conforms to `OutputListControlling` and compiles; every status word and sentence is free of dashes |

Only at the Mac: nothing; this ticket is pure and edits no app file.

## O3. Reader, listeners and controller

Nothing new is visible from this ticket alone. It makes O2 real: live facts, a write whose status is kept, listeners
that come and go with the list, and the old menu removed.

### App side

| Piece | What it does |
| --- | --- |
| `OutputDevices.swift` | `facts() -> [OutputDeviceFacts]`, `defaultOutputID()`, `uid(of:)` and `setDefault(uid:) -> Int32?`, which finds the device by UID at that moment and returns the write's status, or nil when the device is gone. `Device`, `all()`, the `@discardableResult` `setDefault(_:)` and `OutputDeviceTarget` (`:6-27`, `:69-78`) are deleted; their only caller goes with the menu. Only the default output is written, as today |
| Scopes | Reads go through the typed readers in `ScribeCallWatcher.swift:9-46`, which check `AudioObjectHasProperty` first and default to the global scope (`:12`). One table, `OutputDevices.address(for:)`, names the scope of every read: the stream configuration and `DeviceCanBeDefaultDevice` with `kAudioObjectPropertyScopeOutput`; name, UID, transport, `IsHidden` and `IsAlive` with the global scope. A headset with a microphone, read with the wrong scope, would answer for its input |
| The default reader | `defaultOutputID()` is today's private reader (`:29-36`) made internal and returning nil on an error, not a new one. `SystemVolume.defaultOutput()` (`FastActions.swift:439`) and the volume block stay as they are, in files this plan does not own |
| `OutputDeviceReading`, `LiveOutputDeviceReader` | The protocol is declared in `OutputListController.swift`; its live adapter is a Sendable struct in `OutputDevices.swift`, so the selector write stays in one file |
| Queues | Reads run on the serial queue `app.zeus.output.read`, the write on `app.zeus.output.write`, never on the main actor: a Core Audio call can stall on a device that is waking, and O2's deadline is what the owner then sees. Only Sendable values cross; each answer carries its token back to the main actor |
| New `OutputDeviceListener` | Final class, `@unchecked Sendable`, not main-actor isolated, in the shape of `ScribeMicActivityObserver` (`ScribeMicActivity.swift:15-24`): one block each on the device list and the default output of the system object, kept so `stop()` can remove exactly those blocks, delivered through an explicit hop. It is separate from the volume listener (`TopBarServices.swift:460-466`) on purpose: that one is installed inside a main-actor type, is never removed and only re-attaches volume. The mark comes only from this ticket's reads, so the two cannot disagree about it |
| New `OutputListController` | `@MainActor @Observable`, conforms to `OutputListControlling`, holds one `OutputList.State`, applies effects. `init(reader:listener:sleep:show:)` has no live default; the live reader and listener are made only in `TopBarServices.start`. `readBackAfter` and `expireAfter` are one `Task` per token. `announce` posts an accessibility announcement; `cue` calls `show(.soundNotice(text))` (O0). `var onClosed` is an optional closure called each time `stopListening` is applied; O6 sets it. `systemInterrupted()` sends `interrupted` |
| `TopBarServices.swift` | `:47` becomes the controller's `toggle()`; `:211-227` is deleted, with it the output use of `model.menuOpen` (`:224-226`). Three observers, written like those at `:113-119` (`queue: .main`, then `MainActor.assumeIsolated`), call `systemInterrupted()`: `NSWorkspace.willSleepNotification`, `NSWorkspace.sessionDidResignActiveNotification` and the distributed `com.apple.screenIsLocked` (`NotchController.swift:90-91`). The list lives in the panel, so the hover rule keeps it up while the pointer is inside (`NotchController.swift:336-361`) |
| `TopBarModel.swift` | One new property `var outputList: (any OutputListControlling)?`, set in `start()`, and the comment at `:246` corrected (it says the list pops up under the pointer). In snapshots no controller is made |

Left alone, on purpose: `SystemAudioDucker` restores the device it lowered, not the current default
(`Voice/SystemAudioDucker.swift:11`, `:28-40`; lint at `test_source_lint.py:776-782`). The listen-only taps read the
system output, not the default output (`SystemAudioTap.swift:118`, `ScribeLiveCapture.swift:702`); see decision 2.

Lints added to `qa/closed-loop/tests/test_source_lint.py`, each with a fail-first sample in the style of
`test_pointing_lint_detects_its_failure_shapes`:

| Lint | Rule |
| --- | --- |
| `test_the_default_output_is_written_in_one_file` | Under `Sources/`, a line naming `kAudioHardwarePropertyDefaultOutputDevice` or `...DefaultSystemOutputDevice` within eight lines above an `AudioObjectSetPropertyData` call appears only in `TopBar/OutputDevices.swift`. Today's other writers set volume and mute (`FastActions.swift:462`, `:469`, `SystemHUDHardware.swift:100`, `:123`), far from that selector |
| `test_the_output_switch_is_called_only_by_the_list_controller` | `setDefault(uid` appears in `Sources/Zeus` only in `TopBar/OutputDevices.swift` and `TopBar/OutputListController.swift`; `Intent/`, `Voice/`, `Chrome/`, `App/DeepLinks.swift` and `App/DebugCommands.swift` never name `outputList` or `OutputListControlling` |
| `test_tests_never_switch_the_real_output` | Nothing under `Tests/` names `AudioObjectSetPropertyData` or `OutputDeviceListener(`; only `OutputDevicesReadTests.swift` may name `LiveOutputDeviceReader`, and it never names `setDefault` |

Fail closed: a read that fails gives an empty list; a write that cannot find its device gives nil; a listener that
cannot be installed leaves a list that is correct when opened and simply does not update; the write is never retried.

### Tests first

| Suite | Cases |
| --- | --- |
| `OutputListControllerTests.swift` (`@MainActor @Suite(..., .serialized)`; a fake reader, a fake listener, an instant sleeper, a recording `show`; evidence label: direct controller calls) | Opening reads once and installs both listeners; closing removes both; a pick reaches the fake with the UID and is followed by two default reads; a status of -1 shows "Not switched"; a write that never answers shows "Not switched" once the deadline runs; a default that does not move shows "Not switched"; 100 change notices before the first read returns give two reads; closing mid-switch then a differing read-back shows exactly one `soundNotice` cue and no `hint`; reopening before the check shows the result in the list and no cue; `systemInterrupted()` mid-switch removes both listeners and shows no cue; a second pick's result wins; `onClosed` runs once per close |
| `OutputDevicesReadTests.swift` | `addressScopes` (the scope table, per selector); `liveBuiltInOutputCanBeDefault` reads the live facts, writes nothing, and expects every device with transport `bltn` and an output channel to say it can be the default (recorded as not exercised on a runner with no built-in output); `outputTransportCodesMatchTheSDK` compares O1's literals with the header constants; `everyOutputSymbolExists` loads each name in `OutputSymbol.all` with `NSImage(systemSymbolName:)` on the build Mac (the floor is covered by the availability list and by the fallback) |

Both suites are in `Tests/ZeusAppTests`, each with its own native-fixture entry in `qa/feature-map.json`, otherwise CI
compiles it and never runs it.

Only at the Mac: plug and unplug wired headphones with the list open (rows appear and go within a second); connect
and disconnect Bluetooth headphones; switch to each output and hear it; switch while Zeus is speaking; no listener
after the list closes (a device change then causes no read in the log); start a switch and close the lid at once,
then wake: no cue; the same with a locked screen and with a switch to another user; quit mid-switch and relaunch.

## O4. The list on screen

### Behaviour

- The output button opens the list in the place of the track text and the progress line (or of the lyrics, if they
  are showing); a second press, a tab change or the notch closing closes it. The album tile and the control row stay
  where they are, so the button that opened the list is still under the pointer to close it. This is the swap the
  lyrics use (`TopBarViews.swift:547-556`), widened to the progress block (`:557-576`).
- One row per output: the transport symbol, the name, and at the trailing edge a status only when there is one:
  "Current", "Switching", "Not switched" or "Did not stay", each a word with its symbol. The whole row is the button.
- Last row: "Sound settings", which opens the system's Sound pane: the way to reach anything Zeus cannot switch to.
- No outputs: "No outputs found" with `speaker.slash` (today's wording, `TopBarServices.swift:223`). Before the first
  read returns nothing is drawn; there is no spinner.
- With two displays each panel has its own Music page (`NotchController.swift:540-574`); both draw the one state. A
  display added or removed rebuilds the panels (`:519`): the list closes, and a switch in flight is reported by cue.

### Design

New file `Sources/Zeus/TopBar/OutputListView.swift`. No tagline, helper text or second line anywhere in the list.

| Topic | Rule |
| --- | --- |
| Type and rows | Heading "Sound output" in `TopBarStyle.label(12, .semibold)`, `Theme.cloudSecondary`, as the lyrics heading (`TopBarViews.swift:548-549`). Rows 30 pt high: symbol 16 pt in a 22 pt column, name in `TopBarStyle.label(13)` on one line truncated at the tail, status in `TopBarStyle.label(11, .semibold)` |
| Height | 236 pt (`GlanceTopBar.swift:58`) less 12 pt of padding, the 27 pt control row, the heading and two 8 pt gaps leaves about 165 pt: four device rows and "Sound settings" show before scrolling; more scroll inside the existing wrapper (`TopBarViews.swift:1760-1766`) |
| Status | Never colour alone: a warning tint may be added to the two failure words, but the word and the symbol carry it. Symbols are drawn through one helper that falls back to `OutputSymbol.fallback` when the system has no image |
| Open and close | The open flag is reducer state, not view state: the SwiftUI state macro is unavailable to this toolchain (`TopBarViews.swift:538`). The button (`:591-609`) becomes a toggle drawn like `GlyphButton`'s active look (`:68-77`) with the spoken value from `ToggleOnLook.spoken`. The view calls `close()` from its own `onDisappear`, inside `OutputListView.swift`, so no page hook in `TopBarViews.swift` is needed; `close()` twice is harmless |
| Reduce Motion | The swap carries `.animation(Motion.page(reduceMotion: reduceMotion), value: isOpen)`, the rule the tabs use (`TopBarViews.swift:494-499`), and the button does not call `withAnimation`. The lyrics button does (`:581`), whatever the setting; that is not copied. Rows never travel and status symbols do not animate |
| VoiceOver | The list is one container named "Sound output". A row reads its name, then `OutputRouteRules.spokenValue` ("Bluetooth, current"); the current row carries the selected trait |
| Keyboard | The notch panel refuses key status except on a page that takes text (`NotchController.swift:741-747`), so the Music page gets no key events today and Escape cannot close the list. O4 keeps that rule, which exists so the notch never takes the keyboard from the front app, and records the gap in its `qa/feature-map.json` entry instead of claiming keyboard support |
| Snapshot | A static flag `OutputListSnapshot.show`, off by default, in the shape of `LyricsToggle.snapshotShow` (`TopBarViews.swift:530-534`, set at `SnapshotRenderer.swift:665-668`). One new fixture sets it and draws `State.snapshotSample`, once more with Reduce Motion. Every other fixture draws the closed page, so no existing baseline changes |

Fail closed: with `topBar.outputList` nil (snapshots, a QA start) the button draws and a press does nothing.

### Tests first

`Tests/ZeusAppTests/OutputListViewTests.swift` against a `@MainActor` fake `OutputListControlling`. With real window
events through `OwnedWindowEventDriver` (`Tests/ZeusAppTests/OwnedWindowEventDriver.swift:322`; rows and the button
register with the control registry as the Scribe end window does, `ScribeEndWindow.swift:11-22`): a click on a row
calls `pick` with that row's UID; a click on the button calls the model's closure; removing the page calls `close`.
Offscreen, and labelled so: the new fixture renders with the list open, and with the flag off the Music page fixtures
are unchanged and the controller is never touched. What each row says is pure and tested in O1 and O2.

Only at the Mac: light and dark, Reduce Motion (no slide) and Reduce Transparency; a 60-character device name; eight
outputs (scroll); VoiceOver order and the announcements; with VoiceOver on, whether Escape closes the list and focus
returns to the button, recorded either way; two displays, then unplug one with the list open; the list hidden from a
screen share when Zeus is hidden; the cue after the pointer leaves mid-switch; "Sound settings" opening its pane.

## O5. Network speaker rules

### Behaviour

- With the setting on, the list has a part headed "On the network", closed by default every time the list opens.
- Opened, it reads "Searching" until a speaker is seen, then lists names with a symbol for the kind. It never says
  "none found": while it searches, "Searching" is the truth, and that needs no timer.
- Only speakers and television boxes are listed. A computer that announces itself as a receiver is left out, so the
  part is not a list of the neighbours' laptops. A name already in the device rows is not repeated.
- While macOS gives no access the part reads "No access" with a button to the Local Network pane, and the browse
  keeps waiting: the moment access is given, names appear without another press. "No access" is true both after a
  refusal and while the system alert still waits for an answer. No network or a browser failure: "Not available".

### Rules (ZeusCore, pure)

New file `Sources/ZeusCore/TopBar/NetworkSpeakers.swift`:

| Name | Rule |
| --- | --- |
| `SpeakerService`, `SpeakerSighting` | `airplay` (`_airplay._tcp`), `raop` (`_raop._tcp`), with `type` strings and `modelKey` (`model`, `am`). A sighting (Sendable): `service`, `rawName`, `model` |
| `NetworkSpeakerRules.displayName(_:service:)` | For `raop`, a leading run of 12 to 16 hex digits followed by `@` is removed; then `OutputName.clean` |
| `SpeakerKind.init?(model:)` | ASCII only, at most 64 characters, by prefix: `AudioAccessory` home speaker (`homepod`), `AppleTV` television box (`appletv`); `Mac`, `iMac` or `MacBook` gives nil and the sighting is dropped; anything else, or no model, a plain speaker (`hifispeaker`) |
| `merge(_:ownName:) -> [NetworkSpeaker]` | Reads at most 128 sightings; cleans; drops empties, computers and the Mac's own name; one entry per folded name (case and diacritics ignored), the `airplay` record's model preferred |
| `rows(found:routes:)`, `withKindSymbols(_:found:)` | Rows: minus names equal to a listed route; at most 24; sorted by name. `withKindSymbols` maps `[OutputRow]`: a wireless-speaker route whose name matches takes that kind's symbol. No other transport is ever changed, and O2's `rows` knows nothing of this |
| `SpeakerDiscovery` | `State` as listed under "The state machines". `Event`: `settingChanged(Bool)`, `partToggled`, `listClosed`, `results(token, [SpeakerSighting])`, `noAccess(token)`, `failed(token)`. `Effect`: `startBrowse(token)`, `stopBrowse`, `record(Access)` where `Access` is `allowed` or `noAccess` |
| `off` | Ignores everything but `settingChanged(true)`, which gives `collapsed` and no effect |
| `partToggled` | From `collapsed` or `unavailable`: `searching` and `startBrowse`. From `searching`, `found` or `waitingForAccess`: `collapsed` and `stopBrowse` |
| `noAccess` | `waitingForAccess` and no effect: the browser keeps running and nothing is recorded yet |
| `results` | With a live token, from `searching`, `found` or `waitingForAccess`: `found`, or `searching` when empty. The first non-empty one emits `record(.allowed)` |
| `failed`, `listClosed`, `settingChanged(false)` | `unavailable`, `collapsed` and `off`, each with `stopBrowse`; the last two drop the names. Leaving `waitingForAccess` by `partToggled`, `listClosed` or the setting going off also emits `record(.noAccess)`, once |
| `SpeakerDiscoveryControlling` | `@MainActor` protocol: `state`, `togglePart()` |

Fail closed: a stale token changes nothing; a malformed name is dropped; an unknown model is a plain speaker; the
only path to `startBrowse` is `partToggled` in a state other than `off`.

### Tests first

| Suite | Cases |
| --- | --- |
| `NetworkSpeakersTests.swift` | The id prefix is removed only for `raop` and only in that exact shape; hostile names are cleaned or dropped; kinds by prefix, with lower-case, over-long and non-ASCII models giving the plain speaker and a computer model dropped; both services fold to one row; the Mac's own name is dropped; a listed route is not repeated; the caps; `withKindSymbols` touches only wireless-speaker routes |
| `SpeakerDiscoveryTests.swift` | `settingChanged(true)` alone never emits `startBrowse`; no event in `off` does; open then close stops; results from an older browse are dropped; `noAccess` is its own state, emits no `stopBrowse` and records nothing; `noAccess` then `results` gives `found` with no new `startBrowse`; `results` then `noAccess` gives `waitingForAccess`; closing the part or the list from `waitingForAccess` records `noAccess` exactly once; `allowed` is recorded only after a non-empty result; reopening after no access browses again; `listClosed` and the setting going off stop and forget; every word free of dashes |

Only at the Mac: nothing; this ticket is pure. Step zero confirms the record keys first.

## O6. Browse, consent and settings

Everything O5 describes, made real, plus the setting, the usage string and a status row.

### App side

| Piece | What it does |
| --- | --- |
| New `SpeakerBrowser` | Final class, `@unchecked Sendable`, not main-actor isolated: two `NWBrowser`s, one per service type, descriptor `bonjourWithTXTRecord`, peer-to-peer off, on its own serial queue, handlers built in `nonisolated static` functions. A result becomes a `SpeakerSighting` (the service name from the endpoint, the one model key from the record). A waiting state whose error is the DNS policy code is `noAccess` and the browser is left running; a ready state or a results change after it is `results`; any other waiting or failed state is `failed`. It never resolves and never connects |
| New `SpeakerDiscoveryController` | `@MainActor @Observable`: one `SpeakerDiscovery.State`, a browser factory by injection with no live default; `record` writes the raw key `music.networkSpeakers.access`. `TopBarServices.start` sets the list controller's `onClosed` to send it `listClosed`, which also covers sleep, lock and a user switch. `TopBarModel` gains `var speakerDiscovery: (any SpeakerDiscoveryControlling)?` |
| `App/AppDelegate.swift` | One case in the catalog change hook, the single `store.onChange` switch (`:884-899`), passes `music.networkSpeakers` to the controller through `topBarServices` (`:36`). One entry in `store.actions` (`:900-920`), written like `privacy.openAccessibility` (`:912-914`), opens the Local Network pane for the list button and the status row. The file never constructs the browser |
| New `NetworkSpeakersSection` | Placed by one line in `OutputListView.swift` between the device rows and "Sound settings", drawn only when the state is not `off`. Heading row: `wifi`, "On the network", a chevron, spoken as collapsed or expanded. Speaker rows are plain text with a symbol, not buttons, read by VoiceOver as "<name>, on the network". Status rows: `dot.radiowaves.left.and.right` "Searching"; `hand.raised` "No access" with the button "Local Network settings"; `wifi.slash` "Not available". The same line passes the device rows through `withKindSymbols` |
| `Resources/Info.plist` | `NSLocalNetworkUsageDescription`, proposed: "ZEUS looks for speakers on your network to show their names in the sound output list, only when you open that part of the list." And `NSBonjourServices` with the two types |
| Lints on the browser | `NWBrowser(` joins the usage-string table at `test_source_lint.py:110-118`, mapped to `NSLocalNetworkUsageDescription`; every `bonjourWithTXTRecord(type:` literal must be listed in `NSBonjourServices`; `NWBrowser(` appears only in `TopBar/SpeakerBrowser.swift`, which never names `NWConnection`; `SpeakerBrowser(` is made only in `TopBarServices.swift`; `App/PermissionSweepRunner.swift`, `App/OnboardingPermissions.swift` and `App/AppDelegate.swift` never name `SpeakerBrowser(`; nothing under `Tests/` names `NWBrowser(` or `SpeakerBrowser(` |
| Lint on the copy | `test_plist_and_settings_copy_has_no_dash_or_banned_word`: every string value in `Resources/Info.plist` and every string literal in `scripts/gen-settings-catalog.py` is free of U+2014, U+2013 and the owner's banned words. Today's dash lint reads only `Sources/Zeus/**/*.swift` and only U+2014 (`test_source_lint.py:46-47`, `:126-131`). Neither file has a dash today (grep), so the lint starts green |

Fail closed: setting off, no part and no browser object; setting on and part closed, no browser object; no access
shows its own state and never a list; a build with a missing usage string fails the lint before it can ship.

### Tests first

| Suite | Cases |
| --- | --- |
| `Tests/ZeusAppTests/SpeakerDiscoveryControllerTests.swift`, with a fake browser (direct controller calls) | Turning the setting on creates no browser; opening the part creates one; closing the part, closing the list, `systemInterrupted()` and turning the setting off each cancel it; `noAccess` keeps the browser and writes nothing; `noAccess` then a result shows names with the same browser; closing after `noAccess` writes `noAccess`; a late result after close changes nothing |
| `SettingsImportGuardTests` (new; no test names `neverEnabledByImport` today) | Importing `music.networkSpeakers = true` leaves it off; importing false turns it off |

The lints, each with a fail-first sample. Each suite has its own native-fixture entry in `qa/feature-map.json`.

Only at the Mac, on a build signed for release (TN3179: a locally signed build may not keep the choice): the prompt
appears on the first open of the part and at no other moment (launch, setting on, list open, permission sweep,
onboarding); its wording; the order of browser states while the alert is up, written down; Allow shows names with no
second press; Don't Allow shows "No access" and the button opens the right pane; allowing later in System Settings
shows names; no computer and no output already listed appears; no browse runs after the list closes or the Mac
sleeps (Console shows the browser cancelled); idle CPU (`PID=<pid> SECONDS_IDLE=60 scripts/check-perf-budget.sh`).

## Settings rows

| Id | Where | Control | Default | Ticket |
| --- | --- | --- | --- | --- |
| `music.networkSpeakers` | Privacy, Music card (`GlanceSettingsPages.swift:1142-1146`) | Toggle: "Find speakers on the network". Consent text: "Looks for speaker names on your network when you open that part of the sound output list. macOS asks first. Names are not saved." | Off, never enabled by import, in `opt_in` | O6 |
| `perm.localNetwork` | Access status, beside `perm.location` (`gen-settings-catalog.py:145`) | Status row: "Not asked", "Allowed" or "No access", from the last browse; button to the system pane | n/a | O6 |

Rows go in `scripts/gen-settings-catalog.py`; regenerate, never hand-edit `SettingsCatalog.swift` or
`docs/settings-inventory.md`; `scripts/check-settings-catalog.sh` passes. `SettingStatus.value` gains the case and its
snapshot value (`SettingsStore.swift:438-466`, `:484-495`). Raw key, not a catalog row: `music.networkSpeakers.access`.
The status can be out of date, since macOS offers no read of this permission; it corrects itself on the next open.
O0 to O4 add no setting.

## Regression rows (REG-540 to REG-559)

Feature `F13`, as the sources plan binds its rows. Core guards bind to `native-ZeusCoreTests`, lints to
`closed-loop-selftests`.

| Id | Ticket | Failure guarded |
| --- | --- | --- |
| REG-540 | O1, O3 | A hidden device, one that cannot be the default (read with the wrong scope included) or a Zeus aggregate was offered |
| REG-541 | O1 | An unknown transport code, or a virtual device named like headphones, took the wrong symbol or word |
| REG-542 | O1 | A device name with direction overrides, newlines or kilobytes reached the screen |
| REG-543 | O0 | The switch notice became a macOS banner, or was dropped because everyday cues were off |
| REG-544 | O2 | A write reported success, the sound stayed, and the pick was shown as current |
| REG-545 | O2 | The late result of an older pick overwrote a newer pick |
| REG-546 | O2 | A device unplugged between draw and press was written to, or failed silently |
| REG-547 | O2 | A burst of device changes started a read per change |
| REG-548 | O2 | A switch that failed after the list closed was never reported, or one the owner undid was called a failure |
| REG-549 | O3 | Device listeners or a pending switch outlived the list closing, sleep, a locked screen or a user switch |
| REG-550 | O3 | The output switch became reachable from voice, an agent, a deep link, a debug command or a second writer (lint) |
| REG-551 | O3 | A test switched the real output of the build Mac (lint) |
| REG-552 | O4 | A row status was shown without its word or its symbol |
| REG-553 | O5 | A service name was shown with its id prefix or hostile scalars, or a flood grew the list without bound |
| REG-554 | O5 | This Mac, another computer, or an output already listed appeared as a network speaker |
| REG-555 | O2 | A Core Audio call that never returned left a row on "Switching" or blocked every later read |
| REG-556 | O5 | Turning the setting on started a browse, so macOS asked before the owner opened the part |
| REG-557 | O5 | A wait for access ended the browse, so Allow showed nothing, or it was drawn as an empty or searching list |
| REG-558 | O6 | A service type was browsed without its usage string or plist entry, or that copy carried a dash (lint) |
| REG-559 | O6 | An imported settings file turned network discovery on |

## Repo hazards that apply

- Swift 6: a Core Audio or Network callback written inside a `@MainActor` type inherits that isolation and traps on
  the system's queue. Listener and browser blocks are built in types that are not main-actor isolated, with an
  explicit hop (`ScribeMicActivity.swift:12-14`). Detached work captures Sendable values only (TYPE-001, TYPE-005).
  No unapplied main-actor method as a Binding setter in O4 (TYPE-011). No main-actor default value in a controller
  initialiser or a nonisolated struct (TYPE-012). Sandboxes cannot compile Swift: budget a Mac build per ticket.
- `NotchCue` has exhaustive switches in the app target (`TopBarViews.swift:1494`, `:1520`), so O0's Core edit and
  its two view arms land in one commit. No semaphore or group wait and no audio tap or IO proc, so
  `AUDITED_BLOCKING_FILES` and `AUDITED_AUDIO_FILES` are unchanged. `NotchController`, `SystemAudioDucker` and their
  lints are not touched.
- The em dash lint covers `Sources/Zeus` Swift only (`test_source_lint.py:126-131`), so the Core tests check their
  own words and O6 adds a lint for the plist and the generator. The settings generator is the only writer of the
  catalog. New settings cards must be placed on a page (`test_source_lint.py:313`); O6 adds a row, not a card.

## Out of scope

- Playing to a wireless speaker that is not a Core Audio device. The only known ways are a private call refused to
  ordinary apps and a virtual audio driver with an admin install; neither is planned.
- Per-device volume, balance or sample rate in the list; input devices; a keyboard shortcut for the list; letting the
  notch panel take the keyboard on the Music page. Battery level or listening mode of headphones (another plan).
- Remembering a preferred output or switching automatically when a device connects. Zeus switches only on a press.
- Making Zeus's listen-only taps follow the default output (named in the equaliser plan, not fixed there or here).
- Giving the spectrum and Scribe aggregates a UID that starts `app.zeus.` (`SystemAudioTap.swift:45`,
  `ScribeLiveCapture.swift:631`), after which the name match in `isOwnAggregate` can go. Those files belong to no O
  ticket; it is a two-line change for whoever next owns them.

## Decisions the owner owes

1. D5, service discovery. Three choices: stop at O4, which already lists and switches every Core Audio output and
   links to Sound settings; build O5 and O6 as written (one Local Network prompt; names of speakers and television
   boxes only, computers left out); or build only the symbol upgrade for a wireless route, with no list of names,
   which still needs the same prompt and another place to ask for it. O5 and O6 wait for a yes and for step zero.
2. Alert sounds: a switch writes only the default output, as today, so alerts stay on the device chosen in Sound
   settings. The alternative writes the system output too. The plan keeps today's behaviour.
3. The wording of the Local Network usage string and of the consent text on the Privacy row.
4. Where discovery is switched on: the Privacy page only (the plan), or also by a first press on the part in the list.
5. Bundling: none is needed, so there is no licence duty to accept.

## Verification for this wave

1. Tests are committed before the code and shown failing on the base (the build fails on each ticket's new names).
2. `swift build --build-tests`, then `swift test --filter` for each of the twelve suites named under "Tests first":
   six in `ZeusCoreTests`, six in `ZeusAppTests`.
3. The whole `ZeusCoreTests` module on the branch and on the base, compared, with the known failures recounted.
4. `python3 -m unittest discover -s qa/closed-loop/tests -p 'test_*.py'`; the settings generator and its check;
   `./tools/check.sh` development mode from a worktree under `~/AI-Brain-build`.
5. A real compile on a Mac before any ticket is called done, and an independent review of each diff, reading the
   listener install and removal, the token checks, the deadlines and the browser lifetime line by line.
6. Still owed on a real Mac by the owner: step zero, then the "Only at the Mac" lists of O0, O3, O4 and O6: above
   all each switch heard, a forced failure, sleep and lock mid-switch, and the prompt at the first open only.

## Review notes

An adversarial review left 20 findings. Each was checked against the code at `9f2ffe4`, the SDK headers, TN3179 and
the study; 15 were taken as written. Main changes: a `soundNotice` cue in its own ticket (O0), since `.hint` is the
permission cue and becomes a kept macOS banner; a wait for Local Network access is no longer an end state; one
own-aggregate rule shared with the equaliser plan, the current default winning over it; the output scope for the
can-be-default read; a deadline on every Core Audio call, two queues, and transitions for reopening while settling,
late change notices and an unreadable default; "Did not stay"; `interrupted` for sleep, lock and a user switch;
per-ticket feature-map entries and `OwnedWindowEventDriver`; `AppDelegate.swift` in O6; a lint for plist and
generator copy; the wider swap, four rows before scrolling, a snapshot flag and the tabs' Reduce Motion rule; a
write lint on the selector; symbol availability and a fallback; O2 pure again; a wider overlap table.

Narrowed or rejected:

- Open source names: the three notch utilities are no longer named. The other five projects stay: they are not
  products of that kind, and prior art is to be named once with its licence.
- No third default-output reader is added: the one in `OutputDevices.swift` exists today (`:29-36`). The separate
  listener is kept, for the reason given in O3.
- The claimed order of browser states on macOS 15 is not in TN3179. The reducer no longer depends on the order,
  which becomes a Mac check in O6. Escape and focus return are not promised: the panel refuses key status by design.
- A name-free cue, and one ticket holding every feature-map entry, were not chosen: with no banner form the name
  stays in the notch panel, and each ticket adds its own entry in a stated order.
- Dropping the network part stays the owner's choice (D5); the plan's default now leaves computers out.

Unverified, each named where it is used: the record keys and id prefix; the two settings links; whether
`NSBonjourServices` is enforced; the order of browser states under the alert; whether today's menu shows in a screen
share; whether a private aggregate is listed to its creator; the view tests' probe modifier; the licences.
