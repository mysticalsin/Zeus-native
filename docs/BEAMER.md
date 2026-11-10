# Beamer and Zeus

What Zeus knows about Beamer, from reading the signed app (uk.co.kalkman.beamer 1.5.18, build for macOS 13+, Team ID YNL35YT683) on 2026-11-02. The disk image was opened read-only; `kvm_bridge_app.py` is plain source and the modules in `lib/python312.zip` are compiled `.pyc`, read with the standard library (`marshal`, `dis`) without running any of it. Nothing here comes from running Beamer: it was installed to `/Applications` but never launched.

## What Beamer is

A Python (py2app) keyboard-and-mouse sharing app, a "KVM bridge". One Mac's keyboard and pointer cross a screen edge (or corner, or the notch) onto another machine on the same network. Pairing is by a code shown on one machine and typed on the other; the pairing token is stored in `settings.json`.

Machines it pairs (`machines.platform_name`): Windows, Mac, Linux, iPhone, Android. **There is no iPad.** Beamer is not Universal Control or Sidecar and does not use them. An iPad's continuity with a Mac is Apple's Universal Control (System Settings, Displays), which has no API any app can steer. Zeus says so when asked to "switch to my iPad".

It has its own notch effects (`notch_beam` "Outline", `notch_island` "Island"), a machines panel, a ledger of crossing ways, a "Paused/Held" crossing state, a menu bar item and a login item (SMAppService, set in Beamer's own settings).

## Files

| Path | What |
|---|---|
| `/Applications/Beamer.app` | The app. |
| `~/Library/Application Support/Beamer/settings.json` | Paired machines (`peers[]`), crossing zones, this Mac's `machine_id` and `name`, appearance. Each peer: `id`, `name`, `platform` (`windows` `mac` `linux` ...), `host`, `port`, `send`, `allow_drive`, `in_use`, `side`, `linked`, and **`token` (secret: Zeus never reads it)**. Written by Beamer; "Reload configuration" in its menu re-reads it. Zeus only reads. |
| `~/Library/Application Support/Beamer/Beamer.lock` | `flock` held by the running instance. |
| `~/Library/Application Support/Beamer/Beamer.sock` | The instance socket (below). |
| `~/Library/Logs/Beamer/Beamer.log` | Log. It records settings changes and crashes, not link state. |

## Instance socket

`instance_signal.pyc`: `InstanceSignalServer(path, activate)` is a `ThreadingUnixStreamServer`. The handler reads one line (`readline().strip()`) and calls `activate()` whatever it says; `request_running_instance(path)` (what a second launch does) sends `b"activate\n"`. `activate` is `open_window`, so **the socket has exactly one effect: show Beamer's window.** There is no status, pause or switch message.

## argparse

`--config <settings path>` (default `~/Library/Application Support/Beamer/settings.json`) and `--hidden` (start in the menu bar without opening the window). Nothing else. Zeus starts it with `--hidden`.

## Link state

`link_state.describe(controller)` gives a tone, a word, an LED tag and one sentence. Words: `Live` ("From <name>"), `Waking`, `Linked`/`Tunnel`, `Unlocking`, `On <name>` ("Keyboard and pointer are on <name>"), `Held`, `Paused`, `On Mac`, `Not paired`, `Pairing removed`, `Refused`, `Token mismatch`, `Version mismatch`, `Did not wake`, `Blocked` (macOS 27 blocked direct LAN access: open Beamer Tunnel), `Unreachable`, `Not listening`, `Dropped`, `Waiting`, `Disconnected`. Per machine (`machines.row`): Driving this Mac, Input here, Linked, Waiting, Needs re-pair, NOT IN USE, Refused, Version, Unreachable, Not listening, Blocked, Dropped, Looking.

None of this is exposed outside the process. The only outside view of "which screen has control" is the menu bar item's menu, built in `TrayApp`:

| Item title | Meaning |
|---|---|
| `Beamer 1.5.18` | header |
| `Idle` / `Driving <name>` / `Driven by <name>` | `_drive_status()`: input is on this Mac / on that machine / that machine drives this Mac |
| `Send input` or `Send input to <name>` (one per machine) | switch to a machine |
| `Return input to Mac` | bring it home |
| `Pause crossing` / `Resume crossing` | `crossing_paused`, held in memory only, not saved |
| `This Mac drives other machines`, `Other machines drive this Mac`, `Show in Dock` | toggles |
| `Settings…`, `Reload configuration`, `Open log folder`, `About Beamer`, `Quit Beamer` | |

## What Zeus can control

| | How | Needs |
|---|---|---|
| Installed? Running? | bundle id `uk.co.kalkman.beamer` (NSWorkspace) | nothing |
| Paired machines, platforms, in use | read `settings.json` (tokens ignored) | nothing |
| Start | open the app with `--hidden` | nothing |
| Show the machines panel / window | socket `activate\n` (falls back to launching it) | nothing |
| Where input is (`Idle`/`Driving`/`Driven by`), paused or not | read the tray menu through System Events (`menu bar 2 of process "Beamer"`) | Accessibility, and macOS asks once to let Zeus control System Events |
| Pause, resume, switch to a machine, bring input home | click the matching tray menu item through System Events | same |
| Start at login | **not controllable**: Beamer owns it (SMAppService, Beamer's settings). Zeus offers "Start Beamer when Zeus starts" instead | nothing |
| Turn Beamer's notch effect off | **not controllable**: it is part of crossing (`zones[].kind = "notch"`, `notch_style`), read at launch, and `settings.json` also holds the pairing tokens, so Zeus does not edit it. In Beamer, Crossing, set "Show at" to the screen edge, and let Zeus's own cue ("Light the notch when control crosses") do the notch | nothing |

The menu paths are written from the source and have not been run against a live Beamer. If a menu title is different on a machine, the command answers "Beamer's menu didn't respond" instead of guessing.

## Where it is in Zeus

- `Sources/ZeusCore/Integrations/Beamer/`: protocol, settings parser, menu parser, name matching, `BeamerClient` (all testable through `BeamerEnvironment`).
- `Sources/Zeus/Integrations/Beamer/`: the real environment, installer, `BeamerModel`, the Continuity tab, the Home chip, voice resolution.
- `Sources/Zeus/Settings/GSBeamerPage.swift`: Settings, Beamer.
- Continuity is `TopBarTab.continuity`, the last case. It is not in the default row; switch it on in Settings, Beamer, "Show the Continuity tab" (or the tab list in the older settings window). A small chip shows on Home while input is on another machine.
- Voice (fast path rules): "pause Beamer", "resume Beamer", "start Beamer", "open Beamer", "switch to my iPad / my <machine>", "send my keyboard to <machine>", "bring my keyboard back".

## What you do

1. Open Beamer once (Zeus: Settings, Beamer, Start, or Open window). macOS will ask it for Accessibility and Input Monitoring: allow them in System Settings, Privacy and Security.
2. Pair each Mac or PC inside Beamer (Overview, Pair). Beamer must run on both machines. On macOS 27 also open Beamer Tunnel if it says Blocked.
3. For Zeus to read and steer Beamer: allow Zeus in Accessibility (Settings, Permissions) and accept the one "control System Events" prompt.
4. iPad: use Universal Control. Beamer cannot pair it.
