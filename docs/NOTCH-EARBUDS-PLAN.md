# Wireless earbuds in the notch: plan and design

Written 14 November 2026 against `codex/island-20261113` at `9f2ffe4` (read only; line numbers below were read there).
Follows `docs/NOTCH-SOURCES-PLAN.md` and `docs/NOTCH-EQUALISER-PLAN.md` and shares files with both and with the five
sibling plans of the same day (see "Sibling plans and merge order"). Same rules: pure rules in ZeusCore with tests
first, `docs/DESIGN-DIRECTION.md` for anything visible, nothing accepted until the named tests run on macOS and the
behaviour is seen on a Mac with real earbuds. Off by default. Nothing is asked until the owner turns it on. Every line
of Zeus code is written fresh; no code, asset, wording, layout, sound or animation comes from any other product, and
nothing third-party is bundled.

**Refactor first: yes, two small ones (ER1, ER2), with no change in behaviour.** The default output is read in three
places and listened to in one (`Intent/FastActions.swift:439-447`, `TopBar/OutputDevices.swift:29-36`,
`TopBar/TopBarServices.swift:470-476`, listener at `:461-468`); a listening mode bound to the default output would add
a fourth read and a second listener. The Music page swaps its top block through one Bool held in `LyricsToggle`
(`TopBar/TopBarViews.swift:529-541`, `:547`, `:580-581`); a third block needs one value, not a second Bool. The cue
side needs no refactor: one slot with one owner (`TopBarModel.cue`, `show(_:)`, `TopBar/TopBarModel.swift:207-209`,
`:362-387`), below recording and dictation (`ClosedWings.kind`, `TopBarViews.swift:1351-1365`). There is no Bluetooth
code in the repo today (grep for `bluetooth`, `IOBluetooth`, `CoreBluetooth`, `earbuds`, `ListeningMode` over
`Sources`: no hit), so nothing has to be untangled there.

| Ticket | Gap | Today | After |
| --- | --- | --- | --- |
| ER1 | One default-output reader and signal (refactor) | Three reads, one private listener | One reader, one watch with subscribers; same behaviour |
| ER2 | One Music page top block (refactor) | A Bool for lyrics | One `MusicTopBlock` value with a snapshot hook; same pixels |
| E0 | Shared types | None | One Core file of `Sendable` values and two `@MainActor` protocols, so E1 to E6 compile apart |
| E1 | Presence and battery rules | None | A pure reducer for switch, consent, session, sleep, connect, disconnect and reads; a battery book where unknown is never zero |
| E2 | Listening mode rules | None | A pure reducer: value map, supported set, release floor, one write in flight, read back after every set |
| E3 | Words and display rules | None | Name display, cue text, panel model, spoken text, every string in one tested file |
| E4 | Bluetooth side | No Bluetooth use, no usage string | Consent through a public call, connect and disconnect events, guarded private battery reads, the wave's lints |
| E5 | Listening mode device | None | Guarded reads and one guarded write of an undocumented Core Audio property on the current output, off the main thread |
| E6 | Notch surface | 19 cue cases, no earbuds | A connect and disconnect overlay, an earbuds button and panel on the Music page |
| E7 | Settings and wiring | None | Two opt-in rows, a Bluetooth status row, import guard, app wiring, state machine doc |

Order: step zero on the owner's Mac. Then ER1, ER2 and E0 in parallel. Then E1, E2 and E3 in parallel. Then E4, E5 and
E6 in parallel (E6 draws from the E0 protocols through fakes). E7 last, because it wires the live objects.

## Step zero, on the owner's Mac, before E4 and E5 are scheduled

Two throwaway probes, kept in `<models-dir>/earbuds-probe/`, outside every worktree and never committed. No ticket
owns them; the orchestrator writes them, the owner runs them, and the results are written under "Verification".

Probe A is a tiny signed `.app` with its own bundle id and its own `NSBluetoothAlwaysUsageDescription`, opened from the
Finder. It has to be an app: macOS charges Bluetooth consent to the app responsible for a process, so a script started
from a terminal answers for the terminal, and an interpreted script has no usage string of its own. A development Zeus
build with the Bluetooth consent of `app.zeus.mac` reset does the same job (the reset command's service name is
unverified). Probe A answers everything that touches Bluetooth:

1. Does creating the manager raise the prompt? Without a grant, does touching the connect registration or the paired list prompt, fail quietly or end the process? After a grant, do the connect and disconnect registrations deliver?
2. Do the four battery keys answer on macOS 27.2 for the owner's earbuds: both buds out, one bud in the case, lid closed? What does each return when it has no reading? How long does listing the paired devices take?
3. Withdraw the grant in System Settings while the probe runs: does the class property change without a relaunch, and does macOS quit the app?
4. Sleep and wake with the earbuds in: which events arrive, in which order, and how long after wake?

Probe B is one script, `swift earbuds-audio-probe.swift`. It calls Core Audio only, which needs no consent:

5. On the earbuds' audio device: does the mode property exist, in which scope and element, with which size; what does the supported mask hold; does a listener fire when the mode is changed from the system's own control; does a write take, and after how long does a read show it?
6. Does the audio device's UID contain the Bluetooth address, and does its name equal the Bluetooth name?
7. On the oldest macOS release the owner can reach, if any: questions 2 and 5 again.

Until step zero passes for a route, that route ships closed: no percentages, no mode row.

## Open source checked first

Licences as recorded by the research of 13 November 2026, except where "read here" says this plan re-read the page.
Slugs are kept only where a fact is taken, so its licence can be checked.

| Need | Project | Licence | Use |
| --- | --- | --- | --- |
| Connect and disconnect registration | insidegui/NoiseBuddy | BSD-2-Clause | Technique only: one class registration, one registration per device |
| Start-up quiet period, late battery reads | An open notch project (one open pull request) | GPL-3.0 | Technique only. No code is read into Zeus |
| Battery polling shape | An open battery monitor for the Mac | MIT | Technique only |
| Names of the battery keys | Hammerspoon/hammerspoon | MIT (the file itself carries no header; read here) | Facts only: four key names. Its private category is not copied; Zeus declares none |
| Mode property, value map, mask | gustaferiksson/anc | MIT (read here) | Facts only: two selectors, global scope, main element, 4 bytes, values 1 to 4, mask bits. Its "first device that has it" choice is not taken |
| Mode transport cross-check | raulgg/pods-control | MIT | Reference only; its private audio-video route is not used |
| Advertisement decoding | Three open decoders | AGPL-3.0, GPL-3.0, GPL-3.0 | Not used; out of scope |
| API facts | Headers in the local macOS 27.2 SDK, Apple's page for the Bluetooth usage key | n/a | Cited line by line below |

No code is copied, no dependency is added, so no notice file changes. `Package.swift:16-21` keeps its two packages.

## System interfaces relied on, where each was checked, and what each release is known to do

The deployment floor is macOS 14.2 (`Package.swift:6`, `Resources/Info.plist:21-22`). Headers were read in the 27.2
SDK; "study" is the private research of 13 November 2026. "Unknown" means nobody has shown it either way.

| Interface | Kind | Checked against | 14.2 and 15 | 26 | 27.2 |
| --- | --- | --- | --- | --- | --- |
| `CBCentralManager.authorization` (class property; reads the grant without creating a manager) | Public | `CBManager.h:79-86`, values `:62-66` | Known: there since 10.15 (header) | Known | Known |
| `CBCentralManager(delegate:queue:options:)` created once, never scanning, power alert off, to raise the prompt | Public | `CBCentralManager.h:126-139`, `CBCentralManagerConstants.h:24` | Unknown that it prompts | Unknown | Unverified, step zero 1 |
| `NSBluetoothAlwaysUsageDescription` | Public | Apple's page: required when an app uses Bluetooth, macOS 11.0 and later | Known | Known | Known |
| `IOBluetoothDevice.register(forConnectNotifications:selector:)`, fired for any connection | Public | `IOBluetoothDevice.h:121-136` | Unknown; unconfirmed reports that consent gates it from 14 | In use (study) | Unverified, step zero 1 |
| `register(forDisconnectNotification:selector:)` per device, `unregister()` | Public | `IOBluetoothDevice.h:139-151`, `IOBluetoothUserNotification.h:26` | Unknown | In use (study) | Unverified, step zero 1 |
| `pairedDevices()` (the pairings of every user of the Mac), `isPaired()`, `isConnected()`, `name`, `addressString` | Public | `IOBluetoothDevice.h:871-891`, `:565`, `:438`, `:479` | Public since 10.2.5 (header) | Known | Known |
| `deviceClassMajor`, `deviceClassMinor`; audio major `0x04`, headset `0x01`, hands-free `0x02`, headphones `0x06` | Public | `IOBluetoothDevice.h:412`, `:424`; `BluetoothAssignedNumbers.h:338`, `:401-406` | Known | Known | Known |
| Battery keys `batteryPercentLeft`, `Right`, `Case`, `Single` on the device object | Private | Absent from every SDK header (grep). Names from prior art | Unknown | Reported working by one unmerged change (study) | Unknown, step zero 2 |
| Device transport type, values `'blue'` and `'blea'`; device UID | Public | `AudioHardwareBase.h:743`, `:614-615` | Known | Known | Known |
| Mode selector `0x6c73746d`, mask selector `0x6c736d73`, `UInt32`, global scope, main element | Undocumented | Absent from the Core Audio headers (grep). One prior-art project | Unknown, untested | Untested (study) | Unknown; its author tested one model on 27.0. Step zero 5 |
| Mask layout: bit 0 noise cancelling, bit 1 transparency, bit 2 adaptive; off always allowed | Undocumented | The same single source. The study's two documents disagree on it | Unknown | Unknown | Step zero 5 decides |

All three routes (events, battery, mode) are probed at run time on every release and fail closed when anything is
missing. The mode route is the only one that writes, so it also sits behind a release floor:
`ListeningModeRelease.verifiedFrom` (E2) starts at 27.2 and is lowered only by an owner check (step zero 7). Below it
no probe binds and no write exists. Battery reads are read-only and keep the run-time guards alone.

## Privacy and consent

- Off by default. `lights.earbuds` and `earbuds.listeningMode` join the `opt_in` tuple (`scripts/gen-settings-catalog.py:243-246`) and `SettingsStore.neverEnabledByImport` (`Sources/Zeus/App/SettingsStore.swift:255-258`), so an imported file can turn them off, never on (`:314`).
- The Bluetooth prompt has exactly one door: the owner pressing "Allow" on the earbuds row. Never at launch, never from onboarding or the permission sweep (`PermissionSweep.Item` is not extended, `Sources/ZeusCore/Permissions/PermissionSweep.swift:13-15`), never from a stored `true`, never from a test. A stored `true` with no grant shows "Allow" and waits.
- Zeus touches the classic Bluetooth calls only while `CBCentralManager.authorization` reads allowed. Zeus is an accessory app (`Resources/Info.plist:23-24`, `Sources/Zeus/App/main.swift:105`) and rarely "becomes active", so the grant is re-read where it matters instead: before every Bluetooth event or read is acted on, after wake, when the session returns, and when the earbuds panel or the Settings card opens. No manager is kept alive to hear it.
- Usage string, added by E4: "ZEUS shows your earbuds in the notch when they connect or disconnect, with their battery level. It looks only after you turn this on." The plist lint gains a row for it.
- No scanning, ever: Zeus never calls `scanForPeripherals`, never reads advertisements, never opens a channel to a device. It listens for connections of devices the Mac already paired and reads values the system already holds.
- Only while this user's session is on screen: pairings and connect events belong to the whole Mac, so with another user switched in Zeus holds no registration and no device state (E1 `session`).
- Nothing about a device touches the disk: no name, address, battery or mode in defaults, caches or logs. State lives in memory and is dropped when the switch goes off, when the session goes away and at quit. The flight recorder keeps the cue's case name only (`TopBarModel.cueName`, `TopBarModel.swift:390-392`); the cue never becomes a macOS banner (`SystemNotificationPayload.forCue` falls to `nil`, `Sources/Zeus/App/SystemNotificationService.swift:47-48`).
- A device name often holds the owner's own name. When `MeetingState.hideDetails` is true (`SettingsStore.swift:351`; a view has to ask, as `TopBarViews.swift:1674` and `Notch/NotchView.swift:475` do), the cue, the panel and every spoken announcement use the fixed word "Earbuds" in place of the name.
- Nothing leaves the Mac, and nothing reaches a model, a voice turn, a chat or an agent context (lint, E4).
- The listening mode needs no permission: it is a Core Audio property of the output device. It is still its own opt-in switch, because it writes to the owner's hardware through an undocumented route.
- The overlay and the panel draw inside the notch window, which follows the capture rule (`ZeusWindowSharing.refresh`, `Sources/Zeus/App/ZeusWindowSharing.swift:45-52`). No new window, no system menu.
- Entitlements: Zeus is not sandboxed (`Resources/Zeus.entitlements:5-6`), so no Bluetooth entitlement is added. That the signed, hardened build reaches Bluetooth with the usage string alone is owed on a real Mac.

## Security: how this could be abused, and how each way is closed

| Abuse | Closed by |
| --- | --- |
| A settings file turns the feature on to raise a prompt or start watching | Both ids are in `neverEnabledByImport`; the prompt is reachable only from the row's button, never from a switch change (E1 "Switch") |
| Another program of the same user writes `true` into Zeus's defaults | A stored `true` never prompts. With a grant already given it only shows the owner their own earbuds on their own screen; nothing is stored or sent. Named as accepted |
| Another program drives the listening mode through Zeus (CLI, deep link, debug command, hook, bridge, voice, agent) | `choose(_:)` has one caller, the panel button. Lint 6 walks every target under `Sources/`, the three helper tools included. A silent switch to noise cancelling is a safety matter, so no automation exists |
| A nearby unpaired device connects again and again to flood the notch | Connect events fire for any connection (`IOBluetoothDevice.h:122`). Unpaired or non-audio devices are dropped before any state or cue; one cue per device per 10 s; 8 devices at most |
| Another user's earbuds, with fast user switching | Watching stops and every book is dropped while the session is not active; the return seeds with no cue (E1 `session`) |
| A hostile device name: very long, control or direction-override characters, text that reads like a system message | The shared `OutputName.clean`, then 32 characters at most (E3); drawn with `Text(verbatim:)`, fixed symbol and fixed words beside it, no button, never passed to a script, shell, log or model |
| A device reports 0, 255 or a moving value to fake a state | Only 1 to 100 counts. Anything else is "no reading" and can never draw as zero |
| The private key's return type changes in an update | Each selector is checked with `instancesRespond(to:)` and its return type encoding; the read runs inside `ZeusCatchObjCException` (`Sources/ZeusObjCGuard/include/ZeusObjCGuard.h:9`); the result must be a number |
| A virtual or aggregate audio device claims the mode property | The device must be the current default output, with Bluetooth transport, a 4-byte property, a known value and a mask that agrees with it. The only value ever written is one of three fixed codes |
| The mode write lands on another device after an output change | The write re-checks device, transport, property and settable state in the same call; the device key carries a generation |
| The device name shown to a meeting, a screen share or a listener | Notch window only, under the capture rule; and under `MeetingState.hideDetails` the name is replaced by "Earbuds" on screen and in speech (E3, E6) |

## ER1. One default-output reader and signal (refactor)

No behaviour changes. New file `Sources/Zeus/Audio/DefaultOutputWatch.swift`:

- `enum DefaultOutput`: `nonisolated static func current() -> AudioObjectID?`, the one read of `kAudioHardwarePropertyDefaultOutputDevice`. `FastActions.defaultOutput()` (`:439-447`), `OutputDevices.defaultOutput()` (`:29-36`) and `attachVolumeListener` (`TopBarServices.swift:470-476`) call it.
- `@MainActor final class DefaultOutputWatch` (`shared`): one listener block on the system object, installed on the first `subscribe(_:) -> Token` from a `nonisolated static` function with an explicit main hop, removed with the last `unsubscribe(_:)`. `TopBarServices.observeVolume` (`:461-468`) subscribes instead of adding its own block. The installer is injected so a test never touches Core Audio.

Tests first (`Tests/ZeusAppTests/DefaultOutputWatchTests.swift`, fake installer): two subscribers share one block; removing one keeps the other; removing both removes the block; a change reaches every subscriber once. One lint in `test_earbuds_lint.py` (created here, extended by E4): the selector is named in `Sources/Zeus` only in this file and in the setter at `TopBar/OutputDevices.swift:22`. Owed on a Mac: the volume cue still follows an output change.

## ER2. One Music page top block (refactor)

No behaviour changes. New file `Sources/ZeusCore/TopBar/MusicTopBlock.swift`: `enum MusicTopBlock` with `track` and
`lyrics`, and `pressed(_ block:) -> MusicTopBlock` (the shown block returns to `track`; any other is shown). In
`TopBarViews.swift`, `LyricsToggle` (`:529-534`) becomes `MusicTopToggle` holding `@Published var block` with
`static var snapshotBlock`; it stays an `ObservableObject` because the SwiftUI state macro is unavailable to this
toolchain (`:538`). `:547` switches on the value and `:580-581` calls `pressed(.lyrics)`.
`Sources/Zeus/App/SnapshotRenderer.swift:639`, `:665` and `:668` set `snapshotBlock`. One value means two blocks can
never both show; E6 adds `earbuds`, and the output plan's list adds its own case.

Tests first (`Tests/ZeusCoreTests/MusicTopBlockTests.swift`): `pressed` from every block to every block. Owed on a Mac: `parity-lyrics-music.png` is unchanged.

## E0. Shared types

New file `Sources/ZeusCore/Earbuds/EarbudsTypes.swift`, all `Sendable`:

- `EarbudsID` (the normalised address, opaque, `Hashable`; its `description` is the fixed word "earbuds").
- `EarbudsPart`: `left`, `right`, `case`, `single`. `BatteryLevel`: `unknown`, `fresh(Int)`, `lastKnown(Int)`. Both `Hashable`.
- `EarbudsCue` (`Equatable`, `Hashable`, because `NotchCue` is `Equatable`, `TopBarLayout.swift:231`): `id`, `name`, `event` (`connected`, `disconnected`), `levels: [EarbudsPart: BatteryLevel]`. Its `description`, `debugDescription` and mirror are fixed and empty of fields, so no string made from a cue carries the name or the address.
- `BluetoothAccess`: `notAsked`, `allowed`, `denied`, `restricted`.
- `EarbudsStatus` (what views read): `switchOn`, `access`, `asking`, `eventsClosed`, `batteryClosed`, `shown: EarbudsDeviceView?` (id, name, parts in order, levels), with `snapshotSample`.
- `ListeningMode`: `off`, `noiseCancelling`, `transparency`, `adaptive`. `ListeningModeStatus`: `hidden`, `shown(deviceName:, outputUID:, current:, choices: [ModeChoice], pending: ListeningMode?)`; `ModeChoice` is a mode plus `available` or `refused`.
- `@MainActor protocol EarbudsPresenceControlling: AnyObject`: `status`, `ownerPressedAllow()`, `switchChanged(on:)`, `recheckAccess()`, `panelOpened()`.
- `@MainActor protocol ListeningModeControlling: AnyObject`: `status`, `switchChanged(on:)`, `choose(_:)`, `panelOpened()`, `panelClosed()`.

The name and transport rules are not defined here. `OutputName.clean` and `OutputTransport` belong to ticket O1 of
`NOTCH-OUTPUT-PLAN.md` (`Sources/ZeusCore/TopBar/OutputRoutes.swift`, pure, first and alone in its wave). O1 merges
before E0; if the output wave is not scheduled first, E0 absorbs O1 whole, file and test.

Tests first (`Tests/ZeusCoreTests/EarbudsTypesTests.swift`): `@MainActor` fakes conform and compile (the isolation mismatch class of TYPE-012, `qa/native-compile-regressions.md:63`); `String(describing:)`, `String(reflecting:)` and `dump` of an id and of a cue holding the name "Secret" contain neither the address nor "Secret"; two cues with the same name and different ids are not equal.

## E1. Presence and battery rules

### Behaviour

- With the switch on, Bluetooth allowed and this user's session on screen, Zeus knows which paired audio devices are connected. A new connection shows the overlay; so does a disconnection. Devices already connected when watching starts, after wake or after the session returns show nothing.
- Battery: left, right and case for two-piece earbuds, one value for one-piece headphones. A part that reports nothing keeps its last value, marked as last known, for 30 minutes, then becomes unknown. Unknown is never 0.
- Values arrive late after a connection, so Zeus reads twice, 1.0 s and 2.5 s after it, and again when the owner opens the earbuds panel. There is no periodic timer.
- Locked Mac: state follows, nothing is shown or spoken, and nothing is shown later for what happened meanwhile. A display change touches nothing here: the cue slot belongs to `TopBarModel` and redraws like every other cue.

### Rules (ZeusCore, pure)

New file `Sources/ZeusCore/Earbuds/EarbudsBattery.swift`:

| Name | Rule |
| --- | --- |
| `BatteryReading.valid(_ raw: Int?) -> Int?` | 1 to 100 passes; nil, 0, negatives and above 100 give nil |
| `EarbudsParts.layout(answering: Set<EarbudsPart>)` | Left or right answers: left, right, case. Else single answers: single. Else empty (no battery for this device) |
| `BatteryBook.merge(_ raw: [EarbudsPart: Int?], now:)` | A valid part replaces its memory and stamps `now`; an invalid part changes nothing |
| `BatteryBook.level(_ part:, now:)` | No memory: `unknown`. Stamped by the latest read: `fresh`. Older, within `lastKnownLifetime` (1800 s): `lastKnown`. Older: `unknown` |
| `BatteryBook.hasAnyFresh(now:)` | True when one shown part is `fresh` |

New file `Sources/ZeusCore/Earbuds/EarbudsPresence.swift`:

| Name | Rule |
| --- | --- |
| `State` | `off`, `needsAccess(BluetoothAccess)`, `asking(token)`, `watching(Watch)`, `away`, `eventsClosed`. `Watch` holds `quietUntil`, `asleep`, `locked`, `battery` (`unchecked`, `open`, `closed`) and at most 8 devices (facts, book, connected, generation, `cuedAt`, `levelsCued`, `readInFlight`) |
| `Event` | `switched(on:, access:)`, `allowPressed(access)`, `accessAnswered(token, access)`, `askTimedOut(token)`, `accessRead(access)`, `started(seed:, now)`, `registrationFailed`, `batteryRouteChecked(open:)`, `connected(DeviceFacts, now)`, `disconnected(id, now)`, `readDue(id, token)`, `batteryRead(id, token, raw, answering, now)`, `panelOpened`, `willSleep`, `woke(now)`, `resynced(seed:, now)`, `session(active:, locked:)` |
| `Effect` | `requestAccess(token)`, `askTimeout(token, after:)`, `abandonRequest`, `storeSwitch(Bool)`, `startWatching`, `stopWatching`, `watchDisconnect(id)`, `unwatch(id)`, `scheduleRead(id, token, after:)`, `readBattery(id, token)`, `resync`, `showCue(EarbudsCue)` |
| Switch | The stored switch is the only "on" fact and `switched` its only messenger. On with `allowed`, from `off` or `needsAccess`: `startWatching`. On while `watching`, `asking`, `away` or `eventsClosed`: nothing, so an echo can never start twice. On with any other access: `needsAccess`, never `requestAccess`. Off from any state: `off`, `stopWatching` (which drops every registration), `abandonRequest`, every book dropped |
| Allow | `allowPressed(notAsked)` from `off` or `needsAccess(notAsked)`: `asking`, `requestAccess`, `askTimeout(60 s)`. While `asking`: nothing. `allowPressed(allowed)`: `storeSwitch(true)` only |
| `accessAnswered` | Stale token: dropped. Allowed: `off` and `storeSwitch(true)`; the store's own change comes back as `switched` and is the one thing that starts watching. Any other answer: `needsAccess(answer)` |
| `askTimedOut` | Stale token: dropped. Else `needsAccess(notAsked)` and `abandonRequest`; the button works again. A late answer is found by the next `accessRead` |
| `accessRead` | Not `allowed` while `watching` or `away`: `needsAccess`, `stopWatching`, books dropped. `allowed` in `needsAccess`: `startWatching`. Otherwise nothing |
| `DeviceFacts.qualifies` | Paired, audio major class, a minor of headset, hands-free or headphones |
| `started(seed:)` | `quietUntil = now + 2 s`. Every seed device is recorded as connected, with `watchDisconnect` and one `readBattery`; no cue |
| `connected` | Not qualifying: nothing. Already connected: facts refreshed, no cue. Else recorded, generation up, `watchDisconnect` and reads at 1.0 s and 2.5 s on every path; `showCue(connected, no levels)` only when the quiet rule allows. A ninth device replaces the oldest disconnected one (`unwatch`), or is ignored |
| Quiet rule | No cue while `now < quietUntil`, while `asleep` and while `locked`. `quietUntil` is set by `started` and by `woke`, 2 s each (one constant each, tuned by step zero 4). Only the cue is withheld; state follows, and a withheld cue is never shown later |
| Cue limit | A connect or disconnect cue for a device whose last such cue is under 10 s old is dropped; state still changes. The single levels update is exempt |
| `readDue`, `batteryRead` | A stale token is dropped. One read in flight per device. No read is emitted while `battery` is `closed`. After a merge, if the device's connect cue is under 4 s old, `levelsCued` is false and `hasAnyFresh`: `showCue(connected, levels)` once, outside the cue limit, inside the quiet rule |
| `batteryRouteChecked` | `open: false` sets `battery` to `closed`: reads stop; events, state and cues go on, and `status` reports it |
| `disconnected` | Unknown id: nothing. Else `unwatch`, connected false, generation up (pending reads die), the book kept for last-known, `showCue(disconnected)` under the cue limit and the quiet rule |
| `panelOpened` | `readBattery` for the shown device unless one is in flight or the route is closed |
| `willSleep`, `woke`, `resynced` | Sleep: `asleep`, every generation up. `woke(now)`: awake, `quietUntil = now + 2 s`, `resync`. `resynced`: devices not yet known are recorded with `watchDisconnect`; known ones no longer connected are `unwatch`ed and marked disconnected; never a cue |
| `session` | Not active while `watching`: `away`, `stopWatching`, every book dropped. Active again in `away`: `startWatching`, so `started` seeds with no cue. `locked` sets the flag |
| `registrationFailed` | `eventsClosed`, `stopWatching` |
| `status(now:)` | The `EarbudsStatus`; the shown device is the connected one that connected last |

Fail closed: a failed registration ends in `eventsClosed`. A closed battery route, or a device whose `answering` set is
empty, has no levels, so its cue reads "Connected" and nothing reads zero.

### Tests first (`Tests/ZeusCoreTests/EarbudsBatteryTests.swift`, `EarbudsPresenceTests.swift`)

Validity at nil, 0, 1, 100, 101, 255 and negative; layouts for each answering set; a merge with one invalid part keeps the old value and reports it `lastKnown`; `lastKnown` turns `unknown` at 1800 s; no path yields `fresh(0)` or `lastKnown(0)` (a property test over 0 to 255 for each part).

Reducer, consent and switch: a stored `true` with `notAsked` never emits `requestAccess`; Allow does, once, and a double press once; allow, then the store echo, gives exactly one `startWatching`, and a second echo none; a timeout returns to `needsAccess(notAsked)` and a new press asks again; an answer after the timeout is dropped; denied stays `needsAccess`.

Reducer, events: seed then disconnect cues once and emits `unwatch`; a connect inside the quiet period then a disconnect after it does the same; resync then disconnect does the same; a repeat connect gives no cue; an unpaired and a non-audio device change nothing; nine devices, with `unwatch` for the one replaced; a second connect cue inside 10 s is dropped while the levels update inside 4 s still shows, once and never twice; route closed, then connect: the cue has no levels and `status.batteryClosed` is true; a stale token after a disconnect is dropped; disconnect of an unknown id is silent; sleep kills pending reads; wake, connect at +0.5 s, resync at +1 s: no cue; a connect at +3 s cues; locked connect and disconnect: no cue then or after unlock; session away drops every device and emits `stopWatching`, and the return seeds with no cue; `accessRead(denied)` while watching stops it; off from every state emits `stopWatching` and leaves no device.

## E2. Listening mode rules

### Behaviour

- With the switch on, when the Mac's current output is a Bluetooth device that has the mode property, the earbuds panel shows the mode: Off, Noise cancelling, Transparency. A device without it shows no mode row at all.
- Choosing a mode writes once, then reads back. The panel shows what was read, never what was asked.
- A mode the device did not take is marked refused until the output changes. Zeus never writes a second time on its own and never "restores" anything.
- Adaptive is shown when the device reports it, as a fourth capsule that is selected and cannot be pressed. It is not a choice in this wave.
- Everything runs only while the panel is open: no listener and no read otherwise. While it is open Zeus follows output changes even when the current output has no mode, so earbuds that become the output a moment later appear.

### Rules (ZeusCore, pure)

New file `Sources/ZeusCore/Earbuds/ListeningMode.swift`:

| Name | Rule |
| --- | --- |
| `ListeningModeCode.mode(_ raw: UInt32)`, `.code(_ mode:)` | 1 off, 2 noise cancelling, 3 transparency, 4 adaptive; any other raw value is nil |
| `ListeningModeMask.choices(raw: UInt32?, current:)` | Off always. Noise cancelling for bit 0, transparency for bit 1. Nil when the mask is unreadable, or when the current mode is 2, 3 or 4 and its own bit is clear: a mask that contradicts the value read is not trusted |
| `ListeningModeRelease.allowed(major:, minor:)` | True from `verifiedFrom` (27.2 until an owner check lowers it) |
| `ModeProbe` | `key` (object id plus generation), `uid`, `name`, `transportCode`, `hasProperty`, `byteSize`, `rawMode`, `rawMask` |
| `ModeProbe.bound(release:)` | Release allowed, `OutputTransport(code:)` is Bluetooth (the shared rule), property present, size 4, a known mode, trusted choices with at least two entries; else nil |
| `State` | `off`, `dormant` (switch on, panel closed), `absent`, `ready(Bound)`, `setting(Bound, target, token, attempt)`; `Bound` holds key, uid, name, current, choices, refused |
| `Event` | `switched(on:)`, `panelOpened`, `panelClosed`, `probed(token, ModeProbe?)`, `outputChanged`, `externalChange(key, raw)`, `chosen(mode)`, `writeFinished(token, ok)`, `readBack(token, raw: UInt32?)` |
| `Effect` | `watchOutput`, `unwatchOutput`, `probe(token)`, `listen(key)`, `stopListening`, `write(key, code, token)`, `scheduleReadBack(key, token, after:)`, `announce(ModeOutcome)` |
| Panel | `panelOpened` from `dormant`: `watchOutput`, `probe`. `probed` with a bound probe: `ready`, `listen`. Otherwise `absent`; the output watch stays. A stale probe token is dropped. `panelClosed`: `dormant`, `stopListening`, `unwatchOutput`; during `setting` the read back still completes first |
| `outputChanged` | In `absent`, `ready` or `setting`: tokens die, `stopListening`, a new `probe`. In `off` or `dormant`: nothing |
| `chosen` | Only in `ready`, only an available choice that is not the current mode: `setting`, `write`. Anything else, and any press during `setting`, does nothing |
| `writeFinished` | Failed: `ready` with the old mode, the target refused, `announce(stayed)`. Succeeded: `scheduleReadBack(after: 0.5)` |
| `readBack` | Equals the target: `ready(current: target)`, `announce(changed)`. Differs on attempt 1: one more read 1.0 s later. Differs on attempt 2: `ready(current: what was read)`, target refused, `announce(stayed)`. Unreadable or unknown: `absent`, `stopListening` |
| `externalChange` | In `ready`: the current mode follows (the owner used the earbuds or the system's own control). In `setting`: ignored; the read back decides |
| `status` | `hidden` unless `ready` or `setting` |

Fail closed: an unverified release, no property, a wrong size, an unknown value, an untrusted mask or a non-Bluetooth
output all end in `absent` and a hidden row. There is no "offer everything and see" path.

### Tests first (`Tests/ZeusCoreTests/ListeningModeTests.swift`)

The value map both ways and 0, 5 and `UInt32.max` as nil; mask choices for 0, 1, 2, 3 and 7; a current mode whose bit is clear gives nil; a probe that is wired, lacks the property, has size 8, an unknown mode or a release below the floor is not bound; nothing is probed while the panel is closed; a probe that sees the speakers gives `absent`, then `outputChanged` probes again and a bound probe gives `ready`; `absent` keeps the output watch until the panel closes; a stale probe is dropped; `chosen` outside `ready`, for the current mode, for a refused mode and during `setting` emits no `write`; every `write` is followed by a read back before `ready`; a read back that differs twice shows the read value, refuses the target and writes nothing more; a failed write never shows the target; an external change during `setting` is ignored; an output change during `setting` drops the late read back; adaptive is shown and never a choice; off from every state emits `stopListening` and `unwatchOutput`.

## E3. Words and display rules

New file `Sources/ZeusCore/Earbuds/EarbudsDisplay.swift` (pure; every string a person reads lives here):

| Name | Rule |
| --- | --- |
| `EarbudsName.display(_ raw:, hideDetails:)` | Details hidden: "Earbuds". Else the shared `OutputName.clean` (control and format scalars and the line and paragraph separators dropped, every space separator folded to one U+0020, trimmed), then private-use and unassigned scalars dropped, at most 32 characters with an ellipsis as the last one when cut; nothing left gives "Earbuds". If the shared rule lacks a step this needs, E3 adds it there with its test; there is no second cleaner |
| `EarbudsWords.cueStatus(_ cue:)` | Disconnected: the word "Disconnected". Connected with no known level: "Connected". Else the known parts only, in order: "L 80%", "R 75%", "Case 60%", or "80%" for one-piece. An unknown part is left out; a last-known part carries the `clock` symbol |
| `EarbudsWords.panelParts(_:)` | Every part, always: "Left 80%", "Right 75%", "Case 60%"; last known adds the `clock` symbol; unknown is the `questionmark.circle` symbol and the word "unknown" |
| `EarbudsWords.spoken(_ cue:, hideDetails:)` | "Name connected. Left 80 percent, right 75 percent, case 60 percent last known." Unknown parts are spoken as "unknown". The name goes through `display` |
| `EarbudsWords.modeTitle(_:)`, `.modeSymbol(_:)` | "Off", "Noise cancelling", "Transparency", "Adaptive", each with its symbol |
| `EarbudsWords.modeCapsules(_ status:)` | One capsule per choice (`available`, `refused`, `pending`, `selected`), plus one `fixed` selected capsule when the current mode is not a choice (Adaptive). Spoken: "Adaptive, selected" |
| `EarbudsWords.spoken(_ outcome: ModeOutcome)` | "Noise cancelling on." or "Listening mode stayed on Transparency." |
| `EarbudsMatch.same(id:, name:, outputUID:, outputName:)` | True when the UID holds the address (hex pairs, case and separators ignored) or both names are equal after cleaning. Step zero 6 says which half is real; if neither holds, the mode route ships closed |
| `EarbudsPanelModel.make(presence:, mode:, hideDetails:)` | Always one group under one name. Earbuds only: battery parts. Mode only: the mode row under the audio device's name. Both and `EarbudsMatch.same`: battery parts and the mode row under the Bluetooth name. Both and no match: battery parts only, the mode row hidden. Empty when neither has content, which hides the button |
| `EarbudsSettingsWords.state(_ status:)` | "Allowed", "Not asked", "Not allowed", "Battery not available", "Not available" |

Tests first (`Tests/ZeusCoreTests/EarbudsDisplayTests.swift`): "Pro Max Buds" comes back unchanged; a no-break space becomes one space; names with a newline, a line separator, a direction override, a zero width joiner run, 200 characters and only white space; details hidden gives "Earbuds" in `display` and in spoken text; cue status for every mix of fresh, last-known and unknown, with "0%" never produced; panel parts always list every part; the capsules for each state and for Adaptive; the match rule on an address in a UID, on equal names and on neither; the panel model for each of its four cases, always one group; every string free of U+2014 and U+2013 (the dash lint covers only `Sources/Zeus`, `qa/closed-loop/tests/test_source_lint.py:126-132`).

## E4. Bluetooth side

### Behaviour

- "Allow" on the earbuds row raises the Bluetooth prompt, once. Allowed: the switch turns on and watching starts. Refused: the row reads "Not allowed" with "Open System Settings". No answer in 60 s: the row offers "Allow" again.
- While watching, Zeus holds one connect registration and one disconnect registration per connected earbuds device. With the switch off, with the grant gone, or with another user's session in front, it holds nothing.

### Files

| File | Notes |
| --- | --- |
| `Sources/Zeus/Earbuds/BluetoothConsent.swift` | Protocol plus `LiveBluetoothConsent`. `current() -> BluetoothAccess` from the class property, no manager. `request() async -> BluetoothAccess` creates one manager with the power alert off and never scans; it re-reads the class property in every state callback and finishes only when that is no longer not-determined. `abandon()` releases the manager and completes a pending request with the value read at that moment, so no caller waits for ever. The delegate is a separate `NSObject` that is not main-actor isolated and hops explicitly (the TCC handler trap, `test_source_lint.py:91-94`). A manager is never created when the access is already decided |
| `Sources/Zeus/Earbuds/EarbudsBluetoothFeed.swift` | Protocol `EarbudsFeed` plus `LiveEarbudsFeed`. All Bluetooth calls on the main thread. `start()` checks `current() == .allowed` again, registers, returns the connected paired audio devices as `DeviceFacts`; a nil registration is `registrationFailed`. `watchDisconnect` and `unwatch` hold or drop one registration per id. The `@objc` callbacks live in a type that is not main-actor isolated (pattern `Sources/Zeus/Scribe/ScribeMicActivity.swift:12-15`), copy plain facts out of the device object and hop to the main actor. `stop()` unregisters everything |
| `Sources/Zeus/Earbuds/EarbudsBatteryProbe.swift` | Protocol plus `LiveEarbudsBatteryProbe`. The four key names exist only here, as strings turned into selectors. `routeOpen`: `IOBluetoothDevice.instancesRespond(to:)` for at least left or single, sent once as `batteryRouteChecked`. Per device: `responds(to:)` and a return type encoding that is an integer scalar, else the part is not answering. The read is a key-value read inside `ZeusCatchObjCException`; anything that is not a number is nil. No private header, category or framework is declared or loaded |
| `Sources/Zeus/Earbuds/EarbudsSessionSource.swift` | Protocol (`active`, `locked`, one change handler) plus the live type. When L0 of the lock screen plan has merged, the live type reads its `SessionPresenceMonitor`. Until then it observes the two workspace session notifications (as `Sources/Zeus/Voice/WakeWordController.swift:69`) and the two lock names (as `Sources/Zeus/Notch/NotchController.swift:90`), and L0 later replaces its body |
| `Sources/Zeus/Earbuds/EarbudsPresenceController.swift` | `@MainActor @Observable`, conforms to `EarbudsPresenceControlling`, holds one `EarbudsPresence.State`, applies effects. `init(feed:probe:consent:session:storeSwitch:showCue:)` has no live defaults; live ones come only from `AppDelegate` (E7). It sends `accessRead(consent.current())` before it applies any feed event or battery answer, after wake, on a session change, and from `recheckAccess()` and `panelOpened()`. Scheduled reads and the ask timeout are one tracked `Task` per token, cancelled on stop. Sleep and wake through `NSWorkspace` on `.main` with `MainActor.assumeIsolated` (as `NotchController.swift:85`) |
| `Resources/Info.plist` | `NSBluetoothAlwaysUsageDescription` after `:44` |
| `qa/closed-loop/tests/test_earbuds_lint.py`, one row in `test_source_lint.py` | The lints below |

Lints, each with a fail-first sample as `test_pointing_lint_detects_its_failure_shapes` does (`test_source_lint.py:157`).
They live in the wave's own file, which walks every target under `Sources/`: the shared file's `swift_files()` walks
`Sources/Zeus` only (`:46-47`) and is edited by four sibling plans. Every file and type name below is fixed by this
plan, so each lint passes on the day E4 merges and binds when the named file lands.

1. One row in the shared usage-string table (`test_source_lint.py:110-118`): `CBCentralManager\(|IOBluetoothDevice\.` needs the Bluetooth key.
2. `CBCentralManager(` appears only in `Earbuds/BluetoothConsent.swift`; `scanForPeripherals` appears nowhere.
3. `LiveBluetoothConsent(`, `LiveEarbudsFeed(`, `LiveEarbudsBatteryProbe(` and `LiveListeningModeDevice(` appear only in `App/AppDelegate.swift`.
4. `batteryPercent` appears only in `Earbuds/EarbudsBatteryProbe.swift`; the two mode selector values only in `Earbuds/ListeningModeDevice.swift`.
5. `Sources/Zeus/Earbuds/` never calls `NSLog`, `print(`, `os_log` or `Logger(`, and its flight recorder lines carry no interpolation.
6. No mention of `Earbuds` or `ListeningMode` under `Intent/`, `Voice/`, `Agents/`, `Chat/`, `Brain/`, `Proactive/`, `Hands/`, `Chrome/`, `App/DeepLinks.swift`, `App/CommandCenter.swift`, `App/DebugCommands.swift`, `ZeusCore/ZeusCommand.swift`, or anywhere in the `zeus-cli`, `zeus-bridge` and `zeus-hook` targets.
7. `Tests/` never names `IOBluetoothDevice`, `CBCentralManager` or any of the four live types.

### Tests first

`Tests/ZeusAppTests/EarbudsPresenceControllerTests.swift` (`@MainActor @Suite(..., .serialized)`, fake feed, probe, consent, session and an instant sleeper): a stored switch with no grant never calls `request`; Allow calls it once; a refusal starts nothing; a consent that never answers times out, releases through `abandon`, and a second press asks again; an answer that lands after the Settings card has gone still stores the switch and starts once; the grant withdrawn while watching: the next feed event stops the feed and no cue shows.

Events: a connect produces one cue and two reads; a battery answer inside the window re-cues once; a seeded device that disconnects cues, because its registration was held; session away unregisters and forgets every device; switch off unregisters and cancels every task; `registrationFailed` reports `eventsClosed`; a probe whose route is closed reports `batteryClosed` and the cue still shows the name. Its own native-fixture entry in `qa/feature-map.json`.

## E5. Listening mode device

New file `Sources/Zeus/Earbuds/ListeningModeDevice.swift`: protocol `ListeningModeHardware` and
`LiveListeningModeDevice`.

- Threading: `probe`, `write` and the read back run on one serial queue, `app.zeus.earbuds.mode`, never on the main actor, because a Core Audio call can stall on a Bluetooth device that is waking. Only `Sendable` values cross (`ModeProbe`, a status, a token); each answer hops back to the main actor with its token and the reducer drops a stale one.
- `probe()`: the default output from ER1's `DefaultOutput.current()`, its transport type, UID and name, `AudioObjectHasProperty` for the mode selector, the data size, then the two `UInt32` reads. Each call's status is checked; any failure gives a probe that cannot bind.
- `write(key, code)`: in one call, confirms the key's device is still the default output, still Bluetooth, still has the property and reports it settable, then sets 4 bytes. Returns whether the status was `noErr`.
- Output changes come from ER1's `DefaultOutputWatch`: `watchOutput` subscribes, `unwatchOutput` unsubscribes. No second listener on the system object exists.
- The mode listener on the device is installed from a `nonisolated static` function on that queue and delivered through an explicit main hop; added on `listen`, removed on `stopListening`. If it never fires on a real device (step zero 5), nothing breaks: the panel probes each time it opens.
- The property is addressed by number, so there is no symbol to load. "Check every symbol" here means: release floor, has property, size, settable, status, before every use.

New file `Sources/Zeus/Earbuds/ListeningModeController.swift`: `@MainActor @Observable`, conforms to
`ListeningModeControlling`, one `ListeningMode.State`, applies effects, `init(hardware:watch:release:)` with no live
default. `announce` posts a polite VoiceOver announcement (as `NotchController.swift:603-606`).

Tests first (`Tests/ZeusAppTests/ListeningModeControllerTests.swift`, fake hardware and watch): nothing is read while the panel is closed; a choice writes once and reads back; a fake that reports the old value twice ends on the old value with the target refused and exactly one write; an output change mid-set drops the late answer; a probe of the speakers, then an output change to earbuds while the panel stays open, shows the row; a release below the floor never writes; switch off removes the listener and the subscription. Its own native-fixture entry.

## E6. Notch surface

### Behaviour

- Overlay: when earbuds connect or disconnect and the notch is closed, the wings show a cue for 4 s (3 s for a disconnect). Left wing: the earbuds symbol. Right wing: the name, then "Connected", the battery parts, or "Disconnected". When the first reading lands the same cue updates in place, once.
- The cue sits where every cue sits, below a recording and a dictation (`TopBarViews.swift:1351-1358`). `show` replaces whatever cue is up, so the policy keeps it off nine cues: the eight `show` treats as essential (hint, usage, focus, keep-awake, dictation, and the volume, brightness and keyboard-light bars the owner is adjusting, `TopBarModel.swift:366-367`) and the permission cue, which carries a button (`TopBarViews.swift:1549-1557`). It obeys `lights.earbuds` and the cue master switch like its neighbours.
- Music page: an earbuds button after the output button (`:579`), drawn only when there is something to show. Pressed, the page's top block becomes the earbuds panel through ER2's one value, so Lyrics and Earbuds can never both show. The panel closes itself when its content goes away.
- Panel, top to bottom: the name; the battery parts; the mode row (capsules, symbol and word each). The current mode is the filled, bordered capsule; a pending choice shows a small progress mark in place of its symbol; a refused choice is disabled and carries the `exclamationmark.circle` symbol; Adaptive, when current, is a fourth selected capsule that is not a button.
- With details hidden (a meeting, or `privacy.details` off) the name reads "Earbuds" everywhere, spoken too.

### Rules (ZeusCore, pure)

In `Sources/ZeusCore/TopBar/TopBarLayout.swift`: `NotchCue` (`:231`) gains `case earbuds(EarbudsCue)`, with
`duration` 4.0 connected and 3.0 disconnected (`:258-274`). `MusicTopBlock` gains `earbuds`. New `EarbudsCuePolicy`:
`mayShow(_ cue:, over current: NotchCue?)` is false over those nine protected cases, and for a levels update unless
the current cue is the connected cue of the same `id`.

### App side

| File | Change |
| --- | --- |
| `Sources/Zeus/Earbuds/EarbudsViews.swift` (new) | `EarbudsCueIcon`, `EarbudsCueDetail`, `EarbudsButton`, `EarbudsPanel`. Each reads `MeetingState.hideDetails` once and passes it to E3. The panel calls `panelOpened()` and `panelClosed()` on both controllers from its own appear and disappear, so the Music page needs no hook |
| `Sources/Zeus/Earbuds/EarbudsCuePresenter.swift` (new) | Applies `EarbudsCuePolicy` against `topBar.cue`, calls `topBar.show(.earbuds(cue))`, and posts one polite announcement with `EarbudsWords.spoken` only when `show` returned true |
| `Sources/Zeus/TopBar/TopBarViews.swift` | Three arms, required because both cue switches are exhaustive: `extraWidth` 230 (`:1470-1477`), `cueIcon` (`:1494-1513`), `cueDetail` (`:1520-1561`). `MusicPage`: one branch on `MusicTopBlock.earbuds` at `:547` and the button at `:579`, which calls `pressed(.earbuds)` |
| `Sources/Zeus/TopBar/TopBarModel.swift` | `show(_:)` (`:362-387`) becomes `@discardableResult` and returns whether the cue was put up (false at its two early exits), so its other callers are untouched. `lightOption` (`:399-412`) maps the case to `lights.earbuds`; two optional properties hold the controllers as their protocols |
| `Sources/Zeus/App/SnapshotRenderer.swift` | Fixtures beside `:873-875` and `:906-907`: connected with levels, connected with a last-known case, connected with no reading, disconnected, details hidden, and the open panel with a mode row, without one and with Adaptive. The panel fixtures open it with `MusicTopToggle.snapshotBlock = .earbuds`, the hook the lyrics fixture uses (`:665`); the details-hidden fixture turns `privacy.details` off and restores it, as `:636-640` does for its settings. Fixtures use `snapshotSample` and never start a controller (as `Sources/Zeus/Audio/AudioSpectrumService.swift:84`) |

### Design

- Name: `TopBarStyle.label(11, .medium)`, one line, cut at the tail; the status keeps its full width. Percentages use monospaced digits. No tagline, no helper line, no second label anywhere on the cue or the panel, and the panel has one group under one name in every case.
- Status is a word with a symbol throughout: the earbuds symbol with "Connected" or "Disconnected"; `clock` with a last-known value; `questionmark.circle` with "unknown"; the capsule border, not colour alone, for the chosen mode.
- Symbols: `earbuds` for the device (fallback `headphones`); mode symbols are chosen in the SF Symbols app at build. Vendor-specific product symbols are not used.
- Motion: none new. The content swap uses the 0.2 s opacity transition the mascot word uses (`:1435-1436`), and no transition when `Motion.reduced` is true (`Sources/Zeus/App/Preferences.swift:66-68`). The wing width change rides `NotchView.wingsSpring`, a fixed spring with no `Motion.reduced` check (`Notch/NotchView.swift:114-116`, applied at `:300`). That is a Reduce Motion gap for every cue today; it is named here and left to its own follow-up.
- VoiceOver: one polite announcement per cue that was shown; the button is "Earbuds" with the mode as its value; each choice capsule is a button with a selected trait; a refused one says "not available"; a mode outcome is announced.
- Keyboard: the button and the capsules are in the page's focus order; Escape behaviour of the notch is untouched.
- The mode row uses `ViewThatFits`: one row, else the capsules wrap. Its width on a small display is owed on a Mac.

Fail closed: no content, no button. A cue refused by the policy is dropped, not queued. An unknown symbol name
would draw nothing, so a test guards every name.

### Tests first

`Tests/ZeusCoreTests/EarbudsCuePolicyTests.swift`: refused over each of the nine protected cues, allowed over the rest and over none; a levels update only over the cue of the same id, and not over a same-named device with another id; durations; `String(describing:)` and `String(reflecting:)` of `NotchCue.earbuds(cue)` carry neither name nor address; `pressed(.earbuds)` from lyrics shows earbuds and never both.

`Tests/ZeusAppTests/EarbudsSurfaceTests.swift` (fakes of both protocols): `cueName` is "earbuds"; `forCue` is nil; `show` returns false with the light off and with cues off, and the presenter then posts no announcement; the presenter skips a protected cue and never calls `show` twice for one update; with details hidden the cue, the panel and the announcement hold "Earbuds" and not the name; the button is absent with empty models; a capsule press calls `choose` once; a refused capsule is disabled; the Adaptive capsule is selected and not a button; the panel calls `panelOpened` and `panelClosed`; every symbol name resolves with `NSImage(systemSymbolName:)`. Its own native-fixture entry.

## E7. Settings and wiring

### Behaviour

- Appearance gets an "Earbuds" card with two rows and no helper text.
  - "Earbuds in the notch": "Allow" while Bluetooth is not asked; the switch once allowed; "Not allowed" with "Open System Settings" when refused. The shape of `AirDropPermissionRow` (`Sources/Zeus/Settings/GlanceSettingsPages.swift:1246-1276`). A closed route adds its state word beside the switch with `GSStatus` (`Sources/Zeus/Settings/GlanceSettingsStyle.swift:400-410`).
  - "Listening mode on the Music page": a switch and nothing else. Zeus cannot tell a closed route from a device that has no modes, so Settings claims neither.
- Permissions gets a "Bluetooth" row in the Access card after Automation (`:1023-1043`): the state word, and "Open System Settings" when refused. No "Allow" there: the prompt belongs to the feature's own row.

### App side

| File | Change |
| --- | --- |
| `scripts/gen-settings-catalog.py` | Rows below; both ids added to `opt_in` (`:243-246`). `SettingsCatalog.swift` and `docs/settings-inventory.md` regenerated, never hand-edited |
| `Sources/Zeus/Settings/GSEarbudsCard.swift` (new) | The card and the Bluetooth access row. "Allow" calls `ownerPressedAllow()` and writes nothing itself; the card's appear calls `recheckAccess()` |
| `Sources/Zeus/Earbuds/EarbudsSwitchForwarder.swift` (new) | `forward(id:, value:, presence:, mode:)`: maps the two setting ids to `switchChanged(on:)` on the right controller and can call nothing else. Extracted because the `onChange` closure is private to `AppDelegate` (`:884-898`) and no test can reach it |
| `Sources/Zeus/Settings/GlanceSettingsPages.swift` | One line in the `Group` at `:372-376` (the body is at the ten-view limit, `:371`); one row after `:1043` |
| `Sources/Zeus/App/SettingsStore.swift` | Both ids in `neverEnabledByImport` (`:255-258`) |
| `Sources/Zeus/App/AppDelegate.swift` | Inside `on(.topBarServices)` after `:138`: build the four live objects, the session source, the two controllers and the presenter; hand the controllers to `TopBarModel`; `storeSwitch` writes `lights.earbuds`. At start each controller gets `switchChanged(on:)` with the stored value. One case in `store.onChange` (`:884-898`) calls the forwarder; it can start watching with a grant and can never prompt. `applicationWillTerminate` (`:88`) stops both. A QA or snapshot start builds nothing (`Sources/ZeusCore/StartupPolicy.swift:49`) |
| `qa/closed-loop/tests/test_earbuds_lint.py` | Two lints that need this ticket's files, each with a fail-first sample: both ids sit inside the `neverEnabledByImport` literal; `ownerPressedAllow(` is called only from `Settings/GSEarbudsCard.swift` |
| `docs/STATE-MACHINES.md` | Two entries, explicit from the start: earbuds presence, listening mode |

### Tests first

`Tests/ZeusAppTests/EarbudsSettingsTests.swift`: an import carrying both ids as `true` leaves them `false`, and as `false` turns them off; both ids are in the generated `opt_in` set; the card with a fake in `notAsked` shows "Allow" and no switch, in `denied` shows no switch; pressing "Allow" calls `ownerPressedAllow` once and writes no setting; the forwarder, given `lights.earbuds` true and a fake presence in `notAsked`, calls `switchChanged(on: true)` and never `ownerPressedAllow`; given an unknown id it calls nothing; the card's appear calls `recheckAccess`; the snapshot card touches no controller. `scripts/check-settings-catalog.sh` passes.

## Settings rows

| Id | Where | Control | Default | Ticket |
| --- | --- | --- | --- | --- |
| `lights.earbuds` | Appearance, card "Earbuds" | Toggle "Earbuds in the notch", state `custom`, empty note | Off, opt-in, never enabled by import | E7 |
| `earbuds.listeningMode` | Same card | Toggle "Listening mode on the Music page", state `custom`, empty note | Off, opt-in, never enabled by import | E7 |
| `perm.bluetooth` | Permissions, Access status | Status "Bluetooth", state `custom` | n/a | E7 |

No raw defaults key is added: nothing about a device is stored.

## What the owner sees when a route is closed

| Route closed by the system vendor | On screen |
| --- | --- |
| Battery keys gone or changed | The overlay still names the device with "Connected" or "Disconnected". No percentage appears anywhere. The earbuds row reads "Battery not available" |
| Battery keys answer but hold nothing | Parts read "unknown" in the panel and are left out of the cue. Never 0 |
| Connect registration refused | No overlay. The earbuds row reads "Not available". Nothing else in Zeus changes |
| The prompt never answers | After 60 s the row offers "Allow" again. Nothing is watched |
| Bluetooth grant withdrawn | Watching stops at the next Bluetooth event or read, at wake, or when the panel or the Settings card opens, whichever is first. Both rows then read "Not allowed" with "Open System Settings". Whether macOS also quits Zeus at that moment is unverified (step zero 3) |
| Mode property gone, resized, or its mask no longer agrees; or a release below the floor | No mode row, exactly as for a device without modes. Settings says nothing more |
| A write is accepted but not applied | The panel shows the value read back, the choice is marked refused, VoiceOver says the mode stayed |

## Parallel build and file sets

| Ticket | Worktree | Files | Parallel with | After | REG |
| --- | --- | --- | --- | --- | --- |
| ER1 | `codex/earbuds-output-watch-YYYYMMDD` | `Audio/DefaultOutputWatch.swift`, `TopBarServices.swift` (`:461-476`), `FastActions.swift` (`:439-447`), `OutputDevices.swift` (`:29-36`), `test_earbuds_lint.py` (new), App test | ER2, E0 | step zero | 510 |
| ER2 | `codex/earbuds-top-block-YYYYMMDD` | `MusicTopBlock.swift`, `TopBarViews.swift` (`:529-541`, `:547`, `:580-581`), `SnapshotRenderer.swift` (`:639`, `:665`, `:668`), Core test | ER1, E0 | step zero | 511 |
| E0 | `codex/earbuds-types-YYYYMMDD` | `EarbudsTypes.swift`, its test (and O1's file and test if absorbed) | ER1, ER2 | step zero | 512 |
| E1 | `codex/earbuds-presence-YYYYMMDD` | `EarbudsBattery.swift`, `EarbudsPresence.swift`, two tests | E2, E3 | E0 | 513 to 516 |
| E2 | `codex/earbuds-mode-YYYYMMDD` | `ListeningMode.swift`, its test | E1, E3 | E0, O1 | 517, 518 |
| E3 | `codex/earbuds-words-YYYYMMDD` | `EarbudsDisplay.swift`, its test | E1, E2 | E0, O1 | 519, 520 |
| E4 | `codex/earbuds-bluetooth-YYYYMMDD` | Five files under `Sources/Zeus/Earbuds/`, `Resources/Info.plist`, `test_earbuds_lint.py`, one row in `test_source_lint.py`, App test, `qa/feature-map.json` | E5, E6 | E1, E3, ER1 | 521 to 523 |
| E5 | `codex/earbuds-device-YYYYMMDD` | `ListeningModeDevice.swift`, `ListeningModeController.swift`, App test, `qa/feature-map.json` | E4, E6 | E2, ER1 | 524 |
| E6 | `codex/earbuds-surface-YYYYMMDD` | `EarbudsViews.swift`, `EarbudsCuePresenter.swift`, `TopBarLayout.swift`, `MusicTopBlock.swift`, `TopBarViews.swift`, `TopBarModel.swift`, `SnapshotRenderer.swift`, two tests, `qa/feature-map.json` | E4, E5 | E3, ER2 | 525 to 527 |
| E7 | `codex/earbuds-settings-YYYYMMDD` | The generator and its outputs, `GSEarbudsCard.swift`, `EarbudsSwitchForwarder.swift`, `GlanceSettingsPages.swift`, `SettingsStore.swift`, `AppDelegate.swift`, `test_earbuds_lint.py`, `docs/STATE-MACHINES.md`, App test | none | E4, E5, E6 | 528, 529 |

`test_earbuds_lint.py` is created by ER1, extended by E4 after it and by E7 last, never by two tickets at once. Every
ticket appends its own rows to `qa/regressions.json` (last id on the base is REG-409, line 4359); this wave holds
REG-510 to REG-529 and clashes go through `<models-dir>/zeus-merge-reg.py`. Core guards bind to
`native-ZeusCoreTests`, the lints to `closed-loop-selftests`. E4, E5 and E6 each add one `qa/feature-map.json`
entry; they merge in that order and the later ones rebase. Builds go in `<models-dir>/<name>-build`, never
inside OneDrive.

## Sibling plans and merge order

Five plans were written the same day against the same commit (`<models-dir>/zeus-plans/`). Shared files are
rebased in merge order and never hand-merged; generated files are regenerated on the merged base.

| Plan | Same files and lines | Order |
| --- | --- | --- |
| `NOTCH-OUTPUT-PLAN.md` | O1 owns `OutputName.clean` and `OutputTransport`, which E2 and E3 call. O3 deletes `OutputDevices.swift:6-27`, rewrites the reader, adds a listener on the default output and edits `TopBarServices.swift:47`, `:211-227`. O4 rewrites the swap at `TopBarViews.swift:547-556` and the button at `:579`, `:591-609`. O6: `Info.plist`, `SettingsStore.swift`, `GlanceSettingsPages.swift:1142-1146` | O1 before E0, or absorbed by it. ER1 before O3, which then takes the default output from the one watch. ER2 before O4 and E6, which never run together: each adds its case to the one value. O4 keeps its list's open state in its reducer, so who owns "which block shows" is decision 6 |
| `NOTCH-FOCUS-PLAN.md` | F4 adds a `NotchCue` case (`TopBarLayout.swift:231`) and arms in `extraWidth` (`:1468-1489`), `cueIcon` (`:1494-1513`) and `cueDetail` (`:1520-1561`), a value in `TopBarModel.swift`, fixtures in `SnapshotRenderer.swift`. F3: `AppDelegate.swift:135-138`, `:884-898`. F5: `GlanceSettingsPages.swift` after `:350` | F4 and E6 one after the other; the switches are exhaustive, so the second adds its arms on the first's |
| `NOTCH-LOCK-SCREEN-PLAN.md` | L0 creates `SessionPresenceMonitor`, the one session model, and edits the shared lint; later tickets add fixtures, settings and `AppDelegate.swift` lines | L0 before E4 when the lock wave is scheduled first; E4's session source then reads it |
| `NOTCH-DRAWN-NOTCH-PLAN.md` | P2: `TopBarModel.swift:128-134`, `:344-346`, `TopBarViews.swift:1362`, `:1448-1451`, `AppDelegate.swift:885-897`, `GlanceSettingsPages.swift` after `:354`. D0: `SnapshotRenderer.swift:1010-1023`. D3: `GlanceSettingsPages.swift:91`, after `:260` | Separate hunks; rebase |
| `NOTCH-SYSTEM-SOURCE-PLAN.md` | P1e: one line in `TopBarServices.start`, `AppDelegate.swift`. P1d: the shared lint | Separate hunks; rebase |
| The two house plans | `TopBarViews.swift`, `TopBarModel.swift`, `TopBarLayout.swift` (A1, A4; the base still reads `nowPlaying?.player` at `TopBarViews.swift:583`, so A1 has not landed), `GlanceSettingsPages.swift` and the generator (A1, A3, B4), `SettingsStore.swift` (A3), `Info.plist` and `AppDelegate.swift` (B3), `OutputDevices.swift` (B2b, one line in `ids()`) | Rebase |

All five siblings add an id to `neverEnabledByImport` (`SettingsStore.swift:255-258`) and rows to the settings
generator, and four edit `test_source_lint.py`. This wave touches that lint in one table row and keeps the rest in
its own file. E6 and E7 touch each shared file in a handful of lines on purpose.

## Repo hazards that apply

- Swift 6: a callback written inside a `@MainActor` type inherits its isolation and traps when the system calls it elsewhere. The Bluetooth `@objc` callbacks, the manager delegate and the Core Audio listener blocks live in types that are not main-actor isolated and hop explicitly. No main-actor default values in nonisolated types (TYPE-012). No unapplied main-actor method as a `Binding` setter (TYPE-011). Detached work captures `Sendable` values only (TYPE-001, TYPE-005).
- Objective-C exceptions cannot be caught in Swift: the key-value read goes through `ZeusCatchObjCException`, and the `Zeus` target already depends on `ZeusObjCGuard` (`Package.swift:25-28`).
- A missing usage string ends the process on first use (`test_source_lint.py:106`): E4 lands the key with the first Bluetooth call, and lint 1 keeps it there.
- `pairedDevices()` talks to the system service from the main thread. E4 calls it only at start, after wake and on a session return, never per frame; its duration is measured in step zero. If it is slow, the start waits 2 s.
- Core Audio reads can stall on a waking Bluetooth device: E5 keeps every one of them off the main actor. No semaphore or group wait is used, so the blocking-call audit list is unchanged.
- `TopBarModel.show(_:)` is called from many files (`grep "\.show(\."` over `Sources/Zeus` gives 91 lines, some of them other `show` methods); E6's return value is discardable so no caller changes.
- The Appearance page body is at the view builder limit (`GlanceSettingsPages.swift:371`): E7 adds its card as one child of the existing `Group`. E6 adds one child to the Music page's control row (`TopBarViews.swift:577-584`).
- The em dash lint covers `Sources/Zeus` only; ZeusCore strings are covered by E3's own test.
- Settings generator, REG ids, the shared QA files and the sandbox that cannot compile Swift: as in the house plans.
- No new window, so the capture registry is untouched.
- Idle cost: switch on, nothing connected: registrations only, no timer, no polling, no manager kept alive. Panel closed: no mode listener and no subscription of this wave on the output watch. `<pid>` is `the Zeus process id`. `PID="<pid>" SECONDS_IDLE=60 scripts/check-perf-budget.sh` must pass with both switches on.

## Out of scope

- Any other battery route: the system profiler tool, the registry tool, the Bluetooth preferences file, decoding advertisements. Each is slower, staler or needs scanning.
- Setting Adaptive; conversation or spatial settings; ear detection; microphone side; renaming.
- Any automation of the mode: voice, shortcut, CLI, agent, per-app rules.
- A lock screen surface, a Home widget, a menu bar item, a sound on connect.
- More than one earbuds device in the panel (the last connected one is shown).
- The Reduce Motion gap of the wing spring, which belongs to every cue.
- Other private routes to the mode (the private audio-video route needs an entitlement Zeus cannot hold; scripting the system's own control broke on three releases).

## Decisions the owner owes

1. Two switches (overlay with Bluetooth, mode without) as planned, or one switch for both.
2. Adaptive as a choice, once step zero shows a write of it reads back.
3. If the battery keys are closed on 27.2: ship name-only, or open one of the out-of-scope routes.
4. Last-known lifetime (30 minutes, memory only) or values kept across relaunch (a device identifier on disk).
5. A disconnect cue at all, and whether it should carry the last battery values.
6. The merge order of the six plans, and with it one owner for the Music page's top block: this plan's ER2 value, or the output plan's reducer. Both existing at once is the one outcome to refuse.
7. Whether a mode outcome also deserves a visible cue when VoiceOver is off (today: the panel shows the truth).
8. The release floor of the mode row: 27.2 only, or lowered after a check on an older Mac, if the owner has one.

Nothing third-party is bundled, so no licence duty arises from this wave.

## Choices made while planning

- Consent goes through the public manager and the public class property, so Zeus never learns the grant by touching the classic calls first. If step zero shows the classic calls ignore that grant, E4 is re-planned.
- The mode binds to the default output only; taking the first device that has the property is wrong with two pairs.
- The mask must agree with the value read, or the row hides. No automatic second write, and no restoring.
- The read back checks the system's own cached value, which can differ from the earbuds after a dropped write. Zeus cannot see past that; the owner check compares by ear.
- No private header or category is declared; the names are strings checked at run time, this repo's closest equivalent of loading a symbol and testing the pointer (`Sources/Zeus/TopBar/SystemHUDHardware.swift:10-20`).
- `RequestFlight` (`Sources/ZeusCore/Permissions/RequestFlight.swift:7-45`) is not reused: the reducer's own `asking` state, with its token and timeout, already makes a double press one request.

## Verification for this wave

1. Tests are committed before the code and shown failing on the base (the build fails on the missing names).
2. `swift build --build-tests`, then `swift test --filter` for `DefaultOutputWatchTests`, `MusicTopBlockTests`, `EarbudsTypesTests`, `EarbudsBatteryTests`, `EarbudsPresenceTests`, `ListeningModeTests`, `EarbudsDisplayTests`, `EarbudsCuePolicyTests`, `EarbudsPresenceControllerTests`, `ListeningModeControllerTests`, `EarbudsSurfaceTests`, `EarbudsSettingsTests`, and the pinned `SystemNotificationServiceTests`.
3. The whole `ZeusCoreTests` module on the branch and on the base, compared.
4. `python3 -m unittest discover -s qa/closed-loop/tests -p 'test_*.py'`, the settings generator and its check, `./tools/check.sh` development mode from a worktree under `<models-dir>`.
5. A real compile on a Mac before any ticket is called done (TYPE-012).
6. An independent review of each diff, reading the consent door, the guarded reads and the write path line by line.
7. Owed on a real Mac, by the owner, with real earbuds:
   - Step zero, all seven questions, with the numbers written here.
   - After ER1 and ER2: the volume cue follows an output change; the lyrics swap and its snapshot are unchanged.
   - Fresh install: no Bluetooth prompt at launch, in onboarding, in "Allow all", or on opening Settings. The prompt appears only on "Allow". Refusing leaves the row at "Not allowed" and Zeus otherwise unchanged. Leaving the prompt open for a minute brings "Allow" back, and it works.
   - An imported settings file with both switches on turns neither on and raises nothing.
   - Connect: the cue names the device at once and shows levels within about 3 s. One bud in the case: that part shows its last value with the clock mark, then "unknown" after 30 minutes. Lid closed: the case is never 0.
   - Disconnect: the cue, also for earbuds that were in before Zeus started. Sleep and wake: no cue from the reconnect. Zeus launched with earbuds already in: no cue. Locked Mac: nothing shown or spoken.
   - Fast user switching: the other user's earbuds never appear, and nothing cues on the way back.
   - Withdraw the Bluetooth grant while watching: watching stops as the table says.
   - A recording or a dictation in progress hides the cue; a permission cue and a volume bar are not replaced.
   - A second paired audio device and a paired keyboard: the keyboard never cues.
   - Meeting mode on, and "show in screen sharing" on: the cue and the panel read "Earbuds", and so does VoiceOver.
   - Mode: each choice is heard in the ears and matches the system's own control; changing it there updates the open panel; wired headphones and the built-in speakers show no mode row; the panel opened before the output moves to the earbuds gains the row by itself; switching output mid-set changes nothing on the new device.
   - The row width on the smallest display; Reduce Motion; VoiceOver reading of the cue, the panel and an outcome; keyboard reach.
   - Screen share with Zeus hidden: neither the cue nor the panel is captured.
   - Idle CPU with both switches on, and the main-thread time of the first start.
   - System Settings opens the Bluetooth privacy pane from both buttons (the pane anchor is unverified).

Unverified, stated once more: the battery keys on 27.2 and on every older release; the mode property beyond one
model; the mask layout; the grant covering the classic calls; what a withdrawn grant does to a running app; whether
a background session receives connect events; the privacy pane anchor; the symbol names.

## Review notes

Changed after review: refactor first is now yes (one default-output reader and watch, one Music top block value with
a snapshot hook, no `@State`); step zero asks its consent questions from a signed app and keeps the script for Core
Audio; every recorded device gets a disconnect registration and `unwatch` exists; the stored switch is the one "on"
fact and an echo cannot start twice; the request has a timeout, an abandon path and finishes only on a decided
grant; the grant is re-read at named moments and the table says so; session, lock, sleep and wake rules with a quiet
window after wake; the battery route is a field, not a state; `absent` keeps the output watch; the mode device runs
on its own serial queue; a release table and a floor for the only route that writes; the name rule is shared with
the output plan and keeps ordinary spaces; details hidden swaps the name for "Earbuds" on screen and in speech; one
panel group; an Adaptive capsule; nine protected cues; `show` returns a result; cue types are `Equatable` with an
id; lints moved to a file that walks every target, with the import lint in E7; all five sibling plans listed with
lines and order; the stale output-menu decision dropped; every minor citation corrected.

- Keeping a Bluetooth manager alive to hear a withdrawn grant was not taken: it is a standing object held for one rare event. The re-read at each Bluetooth event, read, wake and open covers it and is testable with a fake.
- No display-change event in the presence reducer: the cue slot and its redraw belong to `TopBarModel` and `NotchController` (`:79-82`) for every cue alike. Lock and session are handled; a display change needs no rule.
- The Settings word for the mode route was dropped rather than based on the last probe: a plain Bluetooth speaker would read "Not available" too, and a label explaining that would be the helper text the design forbids.
- Lint rows per ticket were not taken: E4, E5 and E6 run together and cannot share a file. ER1 creates the wave's lint file, E4 fills it with names fixed here, and E7 adds the two lints that need its files.
- Four prior-art slugs stay in the table: a licence claim has to be checkable where a fact is taken. The notch project and the battery monitor, whose names read as products, are now described and not named.
- Probe A also asks the battery questions, beyond what the review asked: a script that touches the classic Bluetooth calls from a terminal has the same consent problem, and no usage string.
