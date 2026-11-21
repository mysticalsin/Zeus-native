# Step-zero probe: plan and design

Written 14 November 2026 against `codex/island-20261113` (HEAD `3757de2`: the six plans on top of `9f2ffe4`), read
only, and revised the same day after an adversarial review ("Review notes", at the end). Nothing was built, compiled
or launched, and no worktree was edited. It serves six plans and redoes none: `docs/NOTCH-SYSTEM-SOURCE-PLAN.md`
(P1.0, `:130-151`), `docs/NOTCH-LOCK-SCREEN-PLAN.md` (`:55-81`), `docs/NOTCH-EARBUDS-PLAN.md` (`:37-59`),
`docs/NOTCH-FOCUS-PLAN.md` (`:56-84`), `docs/NOTCH-OUTPUT-PLAN.md` (`:93-104`) and `docs/NOTCH-SOURCES-PLAN.md` (A2,
`:175-180`). Same rules: pure rules in ZeusCore with tests first, `docs/DESIGN-DIRECTION.md` for anything visible,
nothing accepted until the named tests run on macOS and the behaviour is seen on a Mac. Every line of Zeus code is
written fresh and nothing third-party is bundled.

What it is: one mode of the real, signed Zeus app, started by one launch argument in a specially marked build that
stops working 72 hours after it was made. It shows one plain window with seven rows: one per plan, and one for the
kill test that two plans share. Each row says what it will do, waits for Continue, measures what it can by itself,
walks the owner through the steps that need a hand, and puts back what it changed. One report file then holds 45
answers as facts and yes or no values. The six hand procedures and their throwaway probes
(`<models-dir>/zeus-lock-probe`, `<models-dir>/earbuds-probe/`, the P1.0 throwaway) are not written; one
sitting of about 90 minutes on macOS 27.2 replaces them, plus a shorter run on one macOS 26 Mac that the lock plan
requires.

**Refactor first: no.** There is no step-zero code in the tree to untangle. The patterns it needs exist already:
launch modes decided in `main.swift` before any `AppDelegate` (`Sources/Zeus/App/main.swift:89-100`), a self-test
that writes a receipt, runs under a background watchdog and exits
(`Sources/Zeus/Pointing/PointingSelfTest.swift:21-43`, watchdog at `:30-35`), and private names looked up at run
time that give nil when missing
(`Sources/Zeus/Intent/FastActions.swift:477-481`, `Sources/Zeus/TopBar/SystemHUDHardware.swift:10-20`). Those two
older lookups use `RTLD_LAZY` and one handle per name; they are left alone. The new loaders follow the stricter shape
the six plans ask for.

| Ticket | Gap | Today | After |
| --- | --- | --- | --- |
| Z0 | Report model | Results would be typed into six plans by hand | A pure catalogue of 45 questions, typed answers, a versioned codec that cannot hold free text, a journal, a summary |
| Z1 | Gate, launch mode, packaging | No way to run step zero inside Zeus | One argument, refused unless the build carries a sealed marker that has not expired and Zeus is its own responsible process; a writer for the report; a marked build |
| Z2 | Window, flow and watchdog | Nothing | One window, one reducer: Continue, Skip, a result word with a symbol; no part runs before its Continue; every effect has a time limit |
| Z3 | System source: library and launch rules | No helper library, no launch rule | The symbol table and a facts-only entry in Zeus's own library; the launch constants; a plain reader |
| Z4 | System source: section | Nothing | Items P1.0-1 to 11 measured, the canary, every command put back |
| Z5 | Lock screen section | No space code | L3's loader file, a probe panel, a timeline recorder, a ruler |
| Z6 | Earbuds section | No Bluetooth code | The three guarded loader halves, consent through the public call, mode write and restore |
| Z7 | Focus section | No store read | The lowest layer of the Focus reader file; bounded reads that keep key paths and counts only; a watch on the folder and on the file |
| Z8 | Sound output and Music position | Nothing | Transport list, the lowest layer of the speaker browser file, a five-second switch and restore, Music notification log |
| ZK | Kill test | Nothing | One part after the system source and lock sections: the helper and the card up, then the process ended |
| Z9 | The owner's run | Six procedures | One runbook, one report per Mac |

Worktrees and order:

| Ticket | Files it owns | Runs |
| --- | --- | --- |
| Z0 | new `Sources/ZeusCore/StepZero/StepZeroReport.swift`, `StepZeroCodec.swift`, `StepZeroJournal.swift`, `StepZeroSummary.swift`, four test files under `Tests/ZeusCoreTests/` | First, alone |
| Z1 | new `Sources/ZeusCore/StepZero/StepZeroGate.swift`, new `Sources/Zeus/StepZero/StepZeroProbe.swift`, `StepZeroSeal.swift`, `StepZeroReportWriter.swift`, `Sources/Zeus/App/main.swift` (one line before `:53`), `Sources/ZeusCore/StartupPolicy.swift` (one entry at `:69-77`), `scripts/bundle.sh`, `scripts/package.sh`, `scripts/verify-release-signature.sh`, `qa/release-scripts/test_release_scripts.py`, new `qa/closed-loop/tests/test_step_zero_lint.py`, `Tests/ZeusCoreTests/StepZeroGateTests.swift`, `Tests/ZeusAppTests/StepZeroWriterTests.swift` | After Z0 |
| Z2 | new `Sources/ZeusCore/StepZero/StepZeroFlow.swift`, new `Sources/Zeus/StepZero/StepZeroSession.swift`, `StepZeroWatchdog.swift`, `StepZeroWindow.swift`, `StepZeroView.swift`, seven stub section files (each answering "not built"), `Tests/ZeusCoreTests/StepZeroFlowTests.swift`, `Tests/ZeusAppTests/StepZeroSessionTests.swift` | After Z1 |
| Z3 | new `Sources/ZeusNowPlayingHelper/**` (header, `ZNPSymbols.m`, `ZNPProbe.m`), new `Sources/zeus-np-plain/main.m`, `Package.swift`, new `Sources/ZeusCore/TopBar/SystemSourceLaunch.swift` (launch half), new `Sources/ZeusCore/StepZero/StepZeroHelperLine.swift`, `scripts/bundle.sh` (library and reader copied and signed in a marked build), `test_release_scripts.py`, new `qa/closed-loop/tests/test_step_zero_helper_lint.py`, three test files (the App one needs the test target's dependency at `Package.swift:45`) | After Z2, parallel with Z5 to Z8 |
| Z4 | `Sources/Zeus/StepZero/SystemSourceSection.swift` (replaces its stub), new `Sources/Zeus/TopBar/SystemSourceCanary.swift`, `Tests/ZeusAppTests/StepZeroSystemSourceTests.swift` | After Z3 |
| Z5 | new `Sources/Zeus/LockScreen/LockSpace.swift`, new `Tests/ZeusAppTests/LockSpaceTests.swift`, `Sources/Zeus/StepZero/LockSection.swift` (replaces its stub), new `StepZeroLockPanel.swift`, `Sources/ZeusCore/Compliance/AtticusCleanRoom.swift` (comment only), new `qa/closed-loop/tests/test_step_zero_lock_lint.py`, `Tests/ZeusAppTests/StepZeroLockTests.swift` | After Z2, parallel |
| Z6 | new `Sources/ZeusCore/Earbuds/EarbudsTypes.swift` (`BluetoothAccess` only), new `Sources/Zeus/Earbuds/BluetoothConsent.swift`, `EarbudsBatteryProbe.swift`, `ListeningModeDevice.swift` (guarded halves), `Sources/Zeus/StepZero/EarbudsSection.swift`, new `qa/closed-loop/tests/test_step_zero_earbuds_lint.py`, `Tests/ZeusAppTests/StepZeroEarbudsTests.swift` | After Z2, parallel |
| Z7 | new `Sources/ZeusCore/StepZero/StepZeroFocusFacts.swift`, new `Sources/Zeus/SystemFocus/SystemFocusStoreReader.swift` (lowest layer), `Sources/Zeus/StepZero/FocusSection.swift`, new `qa/closed-loop/tests/test_step_zero_focus_lint.py`, `Tests/ZeusCoreTests/StepZeroFocusFactsTests.swift`, `Tests/ZeusAppTests/StepZeroFocusWatchTests.swift` | After Z2, parallel |
| Z8 | new `Sources/ZeusCore/StepZero/StepZeroSoundFacts.swift`, new `Sources/Zeus/TopBar/SpeakerBrowser.swift` (lowest layer), `Sources/Zeus/StepZero/OutputSection.swift`, `MusicPositionSection.swift`, new `qa/closed-loop/tests/test_step_zero_output_lint.py`, `Tests/ZeusCoreTests/StepZeroSoundFactsTests.swift` | After Z2, parallel |
| ZK | `Sources/Zeus/StepZero/KillTestSection.swift` (replaces its stub), `Tests/ZeusAppTests/StepZeroKillTests.swift` | After Z4 and Z5 |
| Z9 | Nothing in the repo. The reports, copied by the owner to `<models-dir>/zeus-plans/step-zero/` | Last. Owner at the Mac |

Shared files, said plainly. No two tickets that run together share a Swift, Objective-C or lint file: each parallel
ticket has its own lint file, as `qa/closed-loop/tests/test_alerts_lint.py` is the alerts wave's own, so
`test_source_lint.py` is not touched. Two files are shared by every ticket and merged in the fixed order Z0, Z1, Z2,
Z3, Z4, Z5, Z6, Z7, Z8, ZK, each later branch rebasing: `qa/feature-map.json` (one `native-<Suite>` row per App
suite) and `qa/regressions.json` (clashes go through `<models-dir>/zeus-merge-reg.py`). Two are shared in
sequence, never at once: `scripts/bundle.sh` and `test_release_scripts.py` (Z1, then Z3). Regression ids come from
the block REG-580 to REG-599, all used: Z0 580 to 583, Z1 584 to 587, Z2 588 and 589, Z3 590 and 591, Z4 592, Z5 593
and 594, Z6 595 and 596, Z7 597, Z8 598, ZK 599. The highest id in the tree is REG-409. Feature `F13`. Branch names
`codex/step-zero-<ticket>-YYYYMMDD`; builds in `<models-dir>/<name>-build`, never inside OneDrive.

## Open source checked first

The probe adds no technique of its own. Every fact it tests comes from the six plans, whose tables name the prior
art. Licences are as those plans record them; no licence file was re-read for this plan.

| Need | Project | Licence | Use |
| --- | --- | --- | --- |
| A library hosted in the system interpreter, and a self-test entry | ungive/mediaremote-adapter | BSD-3-Clause | Technique only, as in the system source plan |
| Space calls for a window above the lock screen | Lakr233/SkyLightWindow | MIT | Technique only, as in the lock screen plan |
| Names of the four battery keys | Hammerspoon/hammerspoon | MIT | Facts only |
| The two listening-mode selectors and the mask | gustaferiksson/anc | MIT | Facts only |
| Key paths in the Focus store | eugenehp/macos-focus | MIT declared | Key names only |
| Service type names for wireless speakers | bpetrynski/airplay-cli | MIT by its README | The two type names |

No code is copied, no file is bundled and no dependency is added, so no notice is owed.

## How the probe starts, and why an ordinary launch cannot reach it

The owner starts it with `open -n /Applications/Zeus.app --args --step-zero-probe`. Launch Services then starts Zeus
as its own app, so a consent prompt names Zeus and the answer is kept for Zeus. A terminal that runs the executable
directly would be charged instead (`docs/NOTCH-EARBUDS-PLAN.md:42-44`), so that start is refused.

`StepZeroProbe.runIfRequested()` is called once in `main.swift`, inside the `!startupPolicy.isQA` block and before
`DebugForward` (`main.swift:50-53`), so before the single-instance hand-off (`:61`) and long before `AppDelegate`
(`:102`). When the arguments do not contain the flag it returns after one `contains` and reads nothing else: no
plist key, no signature, no file. That is the whole cost and the whole surface at an ordinary launch.

With the flag present the pure rule `StepZeroGate.decide` must pass all of these, or the process exits with code 64
and never falls through to a normal start:

| # | Check | Why |
| --- | --- | --- |
| 1 | The arguments after the executable are exactly the one flag | No path, no second mode, nothing to smuggle |
| 2 | The bundle's `Info.plist` holds `ZeusStepZeroProbe` true | Only a marked build has it. `scripts/bundle.sh` adds it beside the build stamp (`:39`) when `STEP_ZERO_PROBE=1`; the file in the repo never has it |
| 3 | The same plist holds `ZeusStepZeroProbeUntil`, a whole number of seconds, and the clock reads before it and no more than 72 hours before it | A marked build left on disk, or kept as a rollback copy, stops answering the flag. `bundle.sh` writes build time plus 72 hours. A clock set back by an administrator defeats it; named and accepted |
| 4 | The bundle on disk passes a static signature check with nested code and resources, run off the main thread with a 10 s limit | The marker and the date are then sealed: changing either in an installed app breaks the seal |
| 5 | Zeus is its own responsible process. All three must hold: the responsible pid read through a guarded lookup of `responsibility_get_pid_responsible_for_pid` equals Zeus's own pid; the parent is launchd; the launch service name in the environment begins `application.app.zeus.mac.` | A parent of 1 alone does not prove it: a process started from a terminal and forked twice, or started by a launch job, also has parent 1, while macOS keeps charging the terminal. All three are unverified on 27.2. A missing symbol or an unreadable value refuses; the builder of Z1 then reports to the owner and does not weaken the check alone |
| 6 | No other Zeus process runs | The probe's census, kill test and prompts must not mix with a running Zeus. The owner quits Zeus first |
| 7 | Not a QA start; the session is on the console and unlocked | `--qa-startup` already refuses to combine once the flag joins `StartupPolicy.conflictingFlags` (`StartupPolicy.swift:69-77`) |

A release for users is never marked: `bundle.sh` refuses `STEP_ZERO_PROBE=1` with `RELEASE=1` (beside `:12-15`),
`package.sh` refuses it outright (beside `:11-16`), and `verify-release-signature.sh` fails on an app that holds
either key. So a published Zeus contains the code, inert, and no argument can wake it. In an unmarked build the
refusal is silent on screen (a line on standard error); in a marked build a failed check 3, 5, 6 or 7 shows one alert
with the reason and the exact command, because a start through `open` has no terminal to read.

One more rule follows the signature kind. In a marked build that is not signed with a Developer ID (the two extra
builds question P3 needs), only the System source row can run and every other row is fixed at "Not run". Those rows
talk to the consent system, and an answer given to a build with another signature can replace the code requirement
macOS stored for Zeus and break the grants of the normal app.

## Consent

- Nothing of the probe runs at an ordinary launch, from onboarding, from the permission sweep, from a setting, a
  stored value or a test. The probe has no setting and reads none: it does not read `general.showInScreenSharing`
  (its window is always hidden from capture), and it does not go through `Automation`, whose finished checks write a
  defaults key (`Sources/Zeus/App/PermissionsModel.swift:378-386`).
- A section is a list of parts. A part that can raise a system prompt or change anything is gated: the window shows
  its one sentence, in plain words, and waits for that part's Continue. Skip is beside every Continue, for a part
  and for a whole section. A skipped part is recorded as skipped and the run goes on.
- That holds at the next start too. When a run ended early and left something to put back, the first row is "Put
  back", gated like any other part. Nothing is written, stopped or restored before its Continue.
- Continue is dead for 1.5 seconds after the window appears or becomes key again, so a press cannot be stolen by a
  window raised under the pointer.
- The probe never asks twice and never opens System Settings by itself. It never scripts an answer to a prompt
  (`AGENTS.md:72-73`).
- The sentences, complete:

| Part | Prompt it may raise | Sentence shown before Continue |
| --- | --- | --- |
| Put back (only after a run that ended early) | None | "The last run ended early. This puts your earbuds' listening mode back and stops one helper process." |
| System source | None (`docs/NOTCH-SYSTEM-SOURCE-PLAN.md:92`) | "This reads what any app on this Mac is playing, pauses it, moves the position, and shows the word Zeus in the Mac's own now-playing display for up to three seconds. Each is put back." |
| System source, skip part | None | "This skips to the next track and back in your music player. The player may count one skip." |
| Lock screen | None | "This puts a small test card on your lock screen while you lock and unlock the Mac. It also asks you to switch user, start the screensaver and sleep the display." |
| Lock screen, player part (runs unlocked, before the first lock) | Automation for Music and for Spotify, only for a running player that is not already allowed | "Next, macOS may ask to let ZEUS control Music and Spotify, so the probe can play, pause and skip from the lock screen. The player may count one skip." |
| Kill test | None | "This ends the probe on purpose while the test card and the helper are up. You then start it again." |
| Earbuds, paired-list part | Bluetooth | "Next, macOS may ask to let ZEUS use Bluetooth. The probe lists the devices paired with this Mac to see whether that needs your permission." |
| Earbuds, manager part | Bluetooth | "Next, macOS will ask to let ZEUS use Bluetooth, so the probe can see your earbuds connect and read their battery." |
| Earbuds, mode part | None | "This changes your earbuds' listening mode for a few seconds and puts it back." |
| Focus | None. Full Disk Access has no prompt (`Sources/ZeusCore/Permissions/PermissionSweep.swift:25-33`) | "This reads the two Focus files and keeps yes or no answers only. It asks you to turn a Focus on and off, and to switch Full Disk Access for ZEUS off and on." |
| Focus, tool part | None | "This starts a small system tool that tries to list one protected folder, and keeps only whether it could." |
| Sound output, switch part | None | "This moves the Mac's sound to your earbuds for five seconds and puts it back." |
| Sound output, network part | Local Network (macOS 15 and later) | "Next, macOS will ask to let ZEUS find devices on your network, so the probe can see how wireless speakers announce themselves." |
| Music position | None | "This watches the notices Music posts while you play, pause, skip and scrub." |

- A marked build carries two usage strings that the repo's `Info.plist` does not have (`Resources/Info.plist:27-44`
  has neither): the Bluetooth sentence of the earbuds plan (`docs/NOTCH-EARBUDS-PLAN.md:108`) and a provisional
  Local Network sentence with `NSBonjourServices` listing `_airplay._tcp` and `_raop._tcp`. A part checks that its
  string is present before it touches the interface, because macOS ends an app that asks without one
  (`qa/closed-loop/tests/test_source_lint.py:105-107`). The Automation string exists already (`Info.plist:35-36`).
  E4 and O6 still own the rows in the repo's plist.

## The questions

Auto: the probe answers after Continue, given the items on the ready list of the runbook. Guided: the probe
measures, the owner does one thing by hand. Owner: the probe cannot measure it; the owner looks or runs something
and presses Yes, No or Not tried, so the report stays the one file. Totals: 45 questions, 12 Auto, 24 Guided, 9 Owner.

| Q | Measured | How the probe measures it | Who | Prompt | Report fields |
| --- | --- | --- | --- | --- | --- |
| P1 | A playing track is reported by the library inside the interpreter | Child `/usr/bin/perl` from `SystemSourceLaunch` (directory `/`, standard error to the null device). The library opens the media remote framework by its absolute system path with `dlopen(RTLD_NOW)`, resolves the whole table with `dlsym`, then calls `MRMediaRemoteGetNowPlayingInfo`. Three attempts, described at P5; yes when any of them sees the item. After three misses the window asks once "Is the video playing?", and a No gives one more round | Auto | None | `p1.itemSeen`, `p1.fields` (which keys were present), `p1.ownerSaysPlaying` |
| P2 | The same read from an ordinary process is empty | The same entry inside `zeus-np-plain`, a small program with Zeus's own signature and its own signing identifier | Auto | None | `p2.plainSeen`, `p2.gate` (`present`, `absent`, `unknown`) |
| P3 | Ad hoc, local identity and Developer ID builds | The running build's signing kind from `PeerSigning.captureOwnIdentity()` (`Sources/ZeusCore/PeerSigning.swift:49`) beside the P1 result | Owner: this build is Auto; the other two kinds are built and run by runbook step 9, System source row only | None | `build.signing`, `p1.itemSeen` |
| P4 | Symbols, the bundle id call, change notices in the child, CPU when polling | The missing list of the table; the client call and the pid call tried in turn; a notice awaited for 3 s after the probe's own pause and again after its play. The helper registers on its own dispatch queue, reads its input on a second thread and leaves the main thread in `CFRunLoopRun`, so a notice can be delivered while it waits. Child CPU over 30 s of 1 s polls read with `proc_pid_rusage` | Auto | None | `p4.missing`, `p4.bundleIdCall`, `p4.notifyInChild`, `p4.pollCpuMs` |
| P5 | An empty environment is enough for the service call | Attempt A: no variables. On a miss, attempt B: `HOME`, `USER` and `TMPDIR`. On a miss, attempt C: those plus `LOGNAME`, `SHELL` and a fixed `PATH`. Values are built from the account record and `confstr`, never copied from the probe's own environment | Auto | None | `p5.emptyEnvOK`, `p5.needs` (`none`, `homeUserTmp`, `sessionSet`, `unknown`) |
| P6 | The canary is seen, shows and clears, and the elected app keeps the keys | First the precondition the plan sets (`docs/NOTCH-SYSTEM-SOURCE-PLAN.md:115-117`): the probe pauses the elected app and waits until the service reports not playing; if it still plays after 2 s the owner is asked to pause; if it still plays, the probe waits out the plan's 5 s and says so. Then a `MPNowPlayingInfoCenter` entry (title "Zeus", a random token in the album field, at most 3 s); the child compares the token and never prints it. After the clear the elected app is compared with the one before, in the child's memory | Guided: look at the system's display once; press the play key once after the clear | None | `p6.precondition` (`nothingPlaying`, `pausedByProbe`, `pausedByOwner`, `stillPlaying`), `p6.seenByProbe`, `p6.msToSeen`, `p6.clearedSeen`, `p6.sameAppAfter`, `p6.shownInSystem`, `p6.keysReturn`, `restored.elected`, `restored.playState` |
| P7 | Play, pause, next, previous and seek reach the elected app | `MRMediaRemoteSendCommand` with 1 and 0 for any elected app, each read back by the child. The elapsed-time setter, and 4 and 5, only when the elected app's class is `player`; for any other class they are `notMeasured`, because a browser or a video app may load something else and cannot be put back. Next and previous are their own gated part, and next is sent only once the position reads 21 s or more (the probe waits up to 25 s) | Auto | None | `p7.electedClass`, `p7.pause`, `p7.play`, `p7.seek`, `p7.next`, `p7.previous`, `restored.*` |
| P8 | The child exits within a second of its parent being killed | In this section: the time from closing its input to its exit. In the kill test row: the probe ends itself with `SIGKILL` and the next start looks for the child with `SystemSourceLaunch.isOrphan` | Guided: start the probe again | None | `p8.msExitAfterInputClosed`, `p8.orphanAfterKill` |
| P9 | Private window, browser call, inbound stream, playback on another device | "Read now" once per case; the child gives presence, a class of app from a closed table and whether a title exists | Guided: set up each of the four cases; a case with no equipment is Not tried | None | `p9.<case>.seen`, `.appClass`, `.hasTitle`, `.playing` |
| P10 | Older releases; the real path of the running interpreter | `proc_pidpath` of the child (as `Sources/ZeusCore/Insomnia/InsomniaRestore.swift:189`), reduced to a closed code | Owner: run the probe on a 14.x and a 15.x Mac with Apple silicon (the build has one architecture, `scripts/bundle.sh:33-34`) | None | `p10.interpreterImage`, `system.version` |
| P11 | Picture formats players hand over | The first bytes of the artwork, named from a closed list, on every read | Guided: play from each app that matters, press "Read now" | None | `p11.artFormats`, `p11.mimeKeyPresent` |
| L1 | The seven space symbols resolve | `LiveLockSpace.missingSymbols()`; one more name, a removal function, is looked up in the same file and never called | Auto | None | `l1.missing`, `l1.removalCandidate` |
| L2 | A panel in a space at level 400 shows above the lock screen | `makeSpace`, `attach`, `show` on lock, each result kept | Guided: lock, look, unlock, answer | None | `l2.makeSpace`, `l2.attach`, `l2.show`, `l2.seenAboveLock` |
| L3 | A button fires on the first click; keys do not reach it | Counts of button actions, mouse-down events and key events on the panel. Counts only, never a key code | Guided: click the card once, then press Tab, Space and Return once each. Type no letters: they go to the password field, and Return may count as one failed unlock attempt | None | `l3.firstClickFired`, `l3.keyEventsReached`, `l3.becameKey` |
| L4 | After unlock clicks land everywhere; the census is empty; repeated cycles leave no fault | `CGWindowListCopyWindowInfo` census after each close; mouse events that still reach the probe outside its window for 10 s after unlock | Guided: lock and unlock 20 times, as the lock plan asks (`docs/NOTCH-LOCK-SCREEN-PLAN.md:65`); click the four corners. Fewer cycles are recorded and leave the plan open | None | `l4.cycles`, `l4.callFailures`, `l4.censusLeftover`, `l4.strayClicks`, `l4.desktopClicksOK` |
| L5 | Closing the window is enough | Census after a close with no removal call | Guided: answer whether anything stayed on screen | None | `l5.closeIsEnough`, `l5.leftoverSeen` |
| L6 | Order and delay of the lock notices against the session dictionary | A timeline of closed event codes with millisecond offsets; `CGSessionCopyCurrentDictionary` polled every 100 ms for 10 s per transition. No space and no card exist during these transitions | Guided: lock, unlock, switch user and back (needs a second account), start and stop the screensaver, sleep and wake the display | None | `l6.<transition>` (codes and ms; transitions `lock`, `unlock`, `switchOut`, `switchBack`, `saverStart`, `saverStop`, `displaySleep`, `displayWake`) |
| L7 | Which display carries sign-in; the two band heights | The probe draws a numbered ruler strip on each display while locked; it cannot see system drawing | Owner: read four numbers off the ruler and type them | None | `l7.<display>.clockBandBottom`, `.signInBandTop`, `l7.signInOn`; `<display>` is `builtIn`, `external1` or `external2` |
| L8 | Player notices arrive while locked; play, pause and next act | Before the first lock, unlocked: `AEDeterminePermissionToAutomateTarget` for each running player, first without asking (2 s limit), then, after the gated sentence, with asking (60 s limit), off the main thread. While locked: counts of `com.apple.Music.playerInfo` and the Spotify notice (`Sources/ZeusCore/TopBar/NowPlaying.swift:28-29`), and, for an allowed player only, bounded scripts through `SpotifyPlayer.osascript` (`Sources/Zeus/Intent/SpotifyPlayer.swift:98-115`, 3 s each): `playpause` twice with the state read after each, then `next track` and `previous track` once the position reads 21 s. The verbs are those of `Sources/Zeus/TopBar/TopBarServices.swift:238-240` | Guided: lock, press the card's button | Automation, unlocked only | `l8.automation.<player>` (`allowed`, `refused`, `notAsked`, `notRunning`, `timedOut`), `l8.noticesWhileLocked`, `l8.playpause`, `l8.playpauseBack`, `l8.nextTrack`, `l8.previousTrack`, `restored.*` |
| L9 | A window with `sharingType = .none` is missing from a recording | Not measurable: a capture needs a permission the probe never asks for | Owner: record the lock screen another way | None | `l9.sharingNoneSet`, `l9.hiddenFromRecording` |
| L10 | VoiceOver reaches the button; Touch ID and the password field work beside it | Not measurable | Owner: try each | None | `l10.voiceOverReaches`, `l10.touchIDWorks`, `l10.passwordWorks` |
| L11 | Whether macOS draws media controls of its own, and where | Not measurable; the ruler gives the positions | Owner: look with Music playing and a notification waiting | None | `l11.systemMediaControls`, `l11.<display>.bandTop`, `.bandBottom` |
| L12 | Kill while the card is up; the boot id reads and changes | `sysctlbyname("kern.bootsessionuuid")`. The kill test row holds the card up, ends the probe, and the next start runs the census. A mark of the boot id is kept in the journal, never in a report, and compared after the restart of runbook step 6 | Guided: start the probe again; restart the Mac once inside the sitting. Owner: Force Quit by keyboard or `killall Zeus` with the card held up after unlock | None | `l12.bootIDReads`, `l12.bootChangedAcrossRestart`, `l12.windowGoneAfterKill`, `l12.censusAfterRelaunch`, `l12.forceQuitTried`, `l12.goneAfterForceQuit` |
| E1 | What raises the Bluetooth prompt; what the classic calls do without a grant; events after it | Three steps. (a) `CBCentralManager.authorization`, which never prompts. (b) Gated: `pairedDevices()` and the connect registration under the journal, then "Did a prompt appear?". (c) Gated: one manager, never scanning, on its own queue, then "Did a prompt appear?". If (b) prompted, (c) can no longer be answered and is `notMeasured`; the runbook then repeats the section after the owner's own consent reset | Guided: two answers; put the earbuds in the case and take them out | Bluetooth | `e1.accessBefore`, `e1.classicBeforeGrant` (`quiet`, `prompted`, `refused`, `endedProcess`, `hung`), `e1.managerPrompts`, `e1.connectDelivered`, `e1.disconnectDelivered` |
| E2 | The four battery keys in three postures; the no-reading value; listing time | `instancesRespond(to:)`, `responds(to:)`, the return type encoding, then a key-value read inside `ZeusCatchObjCException` (`Sources/ZeusObjCGuard/include/ZeusObjCGuard.h:9`). The encoding and the value's class are mapped to closed codes in the loader file | Guided: both out, one in the case, lid closed | Bluetooth | `e2.<posture>.<key>.responds`, `.returnType` (`object`, `integer`, `other`, `none`), `.valueClass` (`number`, `string`, `null`, `other`, `raised`), `.level` (`inRange`, `zero`, `n255`, `other`), `e2.listPairedMs` |
| E3 | Withdrawing the grant while running | The owner presses "Start" in the window, then turns Zeus off in the pane. The class property is polled every second for 60 s from that press; the journal shows whether macOS ended the process | Guided: press Start, then turn Zeus off in the Bluetooth pane | None | `e3.changedLive`, `e3.changedWithin` (`w10s`, `w60s`, `none`), `e3.appQuit` |
| E4 | Sleep and wake with the earbuds in | A timeline of sleep, wake, connect and disconnect codes | Guided: sleep the Mac, wake it | Bluetooth | `e4.timeline` |
| E5 | The mode property, its mask, its listener, a write and its read back | `AudioObjectHasProperty` for the two selectors the loader file holds, the data size, two `UInt32` reads, settable, a listener block, one write of another allowed value, polls for 5 s, the first value written back. Every Core Audio call off the main actor with a 2 s limit | Guided: wear the earbuds; change the mode once from the system's own control | None | `e5.exists`, `e5.scope`, `e5.size`, `e5.mask`, `e5.current`, `e5.listenerFired`, `e5.writeTook`, `e5.msToReadBack`, `restored.listeningMode` |
| E6 | The audio UID holds the address; the audio name equals the Bluetooth name | Compared in memory; neither string is kept. The device's class comes from the public class-of-device minor number through a fixed table | Auto | Bluetooth | `e6.uidHasAddress`, `e6.nameEqualsBluetoothName`, `e6.deviceClass` (`headphones`, `headset`, `handsFree`, `other`) |
| E7 | The oldest release at hand | The same section on that Mac | Owner: run the probe there | Bluetooth | `system.version` |
| F1 | The two store files exist | `open(O_RDONLY)` and `fstat` on the two paths, through the reader file | Auto, with Full Disk Access already given to Zeus | None | `f1.assertionsExists`, `f1.configExists`, `f1.errno` |
| F2 | A Focus turned on changes the file within a second, with the expected keys; turning it off | Three watchers, because a folder source does not report a file rewritten in place (`docs/NOTCH-FOCUS-PLAN.md:315`): an event source on the folder, one on the file (write, extend, attribute, rename, delete; reopened after a rename or delete), and a check of the file's stamp every 250 ms with one last read when the window ends. The owner presses "Start", then turns the Focus on; the window shows the word "Changed" the moment a change is seen. Each new content is parsed to key presence | Guided: press Start, turn a Focus on in Control Center, say whether "Changed" came within about a second of the click; then the same for off | None | `f2.changeSeen`, `f2.seenBy` (`fileEvent`, `folderEvent`, `poll`), `f2.changedWithin` (`w2s`, `w10s`, `w30s`, `none`; from the press, so it includes the owner's hand), `f2.withinASecond` (the owner's answer), `f2.hasModeIdKey`, `f2.idIsConfigKey`, `f2.offShape`, `f2.fileExistsWhileOff` |
| F3 | The same for a schedule and for the phone | The same watch | Guided: start one from the phone (needs sharing across devices); a schedule is optional | None | `f3.schedule`, `f3.phone` |
| F4 | A custom Focus has a name and a symbol that is a system symbol | Counts only; each symbol name tried with `NSImage(systemSymbolName:)` and dropped | Auto, with a custom Focus already made | None | `f4.modes`, `f4.withName`, `f4.withSymbol`, `f4.symbolsResolve` |
| F5 | Replaced or rewritten in place | The inode before and after the F2 change, beside which watcher saw it | Guided: rides on F2 | None | `f5.write` (`replaced`, `inPlace`, `unknown`) |
| F6 | Without the grant: the error, no prompt, the pane listing | The `errno` of the read while Zeus has no grant | Guided: say whether a prompt appeared and whether Zeus is listed. Runs first when the grant is off at the start, and right after the owner turns it off otherwise | None | `f6.errno`, `f6.promptSeen`, `f6.listedInPane` |
| F7 | The grant and its removal take effect at once or after a reopen | One read a second for 30 s across each change. The order follows the state at the start, so the run ends as it began: off then on when the grant was on, on then off when it was off | Guided: switch the grant twice; choose Later if macOS offers to reopen Zeus | None | `f7.grantLive`, `f7.revokeLive` |
| F8 | A tool started by Zeus can read a protected place | Its own gated part. Zeus first lists the one protected folder its own check already lists (`Sources/Zeus/Onboarding/OnboardingServices.swift:228-232`); then `/bin/ls` of that folder through `BoundedSubprocess.run` (`Sources/ZeusCore/BoundedSubprocess.swift:19-21`, 5 s). Only the exit status is read; the two text fields of the result are never touched (lint), because an error line holds the home path | Auto, with the grant on | None | `f8.selfCanRead`, `f8.childCanRead` (`yes`, `no`, `noGrant`, `timedOut`) |
| F9 | Mirroring, then sleep and wake: a record with no Focus shown | The same watch | Guided: mirror (needs a second display), sleep, wake, say what Control Center shows | None | `f9.recordWhileNoFocus`, `f9.carriesModeId` |
| F10 | macOS 14 or 15 | The same section on that Mac | Owner: run the probe there | None | `system.version` |
| O1 | A picked wireless speaker appears as a device with transport `airp` | `kAudioHardwarePropertyDevices` and `kAudioDevicePropertyTransportType`, each code mapped through a closed table | Guided: pick the speaker in Control Center | None | `o1.transports`, `o1.airpSeen` |
| O2 | Name shapes and the record keys `model` and `am` | `NWBrowser` with `bonjourWithTXTRecord` for the two declared types, through the speaker browser file; nothing is resolved or connected | Auto, with a wireless speaker on the network | Local Network | `o2.states`, `o2.waitingBeforeAnswer`, `o2.airplayCount`, `o2.raopCount`, `o2.raopHexPrefixCount`, `o2.modelKey`, `o2.amKey` |
| O3 | Read back after a switch to Bluetooth headphones; whether macOS moves it back | One write of the default output, a read every 100 ms for 5 s, the first device written back | Auto, with the earbuds worn and connected; otherwise `notMeasured` | None | `o3.msToReadBack`, `o3.movedBack`, `restored.defaultOutput` |
| O4 | Today's output menu in a screen share | Not measurable: the menu belongs to the normal app and the answer needs a viewer | Owner: try it in normal Zeus, then record the answer | None | `o4.menuVisibleToViewer` |
| A2 | Whether Music posts on play, pause, a track change and a scrub | An observer on `com.apple.Music.playerInfo`; per action, posted or not within 15 s, and whether a position key is present | Guided: do the four actions in Music | None | `a2.play`, `a2.pause`, `a2.trackChange`, `a2.scrub` |

## Time limits and the watchdog

No wait in the probe is open-ended. The limits are data in `StepZeroFlow`, so they are tested without a clock.

| Effect | Limit | On expiry |
| --- | --- | --- |
| One answer line from the helper child (`read`, `cmd`, `seek`, `token`) | 5 s | The answer is `notMeasured` with the code `timedOut`; the child is stopped and started fresh for the next part |
| The Bluetooth manager reaching a state | 10 s | `e1.managerPrompts` is `notMeasured`; the manager is abandoned |
| The classic Bluetooth calls, on the main thread as E4 will call them (`docs/NOTCH-EARBUDS-PLAN.md:485`) | 15 s, held by the watchdog | The journal records `hung`; the watchdog ends the process |
| The static signature check at the gate and before a spawn | 10 s, off the main thread | Refusal |
| One Core Audio read or write | 2 s, off the main actor | The step fails; the restore is still tried once |
| An Automation check without asking; with asking | 2 s; 60 s | `timedOut` |
| One script to a player | 3 s (`SpotifyPlayer.swift:107-110`) | The verb is a no |
| A tool start (`/bin/ls`) | 5 s | `timedOut` |
| The stop and restore at the end of a part | 5 s | The watchdog ends the process; the next start offers "Put back" |
| The card and its space after a lock | 120 s; 300 s for the two looking parts (L7 with L11, and L10) | Destroyed, then the census |
| The speaker browse | 20 s | Cancelled |

`StepZeroWatchdog` is not main-actor isolated. Each running part arms one timer on a background queue, as
`PointingSelfTest` does (`PointingSelfTest.swift:30-35`). When it fires with the part unfinished it writes the step
to the journal, runs the restores that are safe off the main thread (the listening mode, the default output, stopping
the child), and exits with code 70. A window and a space cannot be closed from that thread; they end with the
process, which is what question L12 measures. Until L12 has an answer that is an assumption, so the runbook carries
the way out: `killall Zeus`, and logging out if the card still stays.

## System interfaces relied on, and where each was checked

| Interface | Kind | State |
| --- | --- | --- |
| `MRMediaRemoteGetNowPlayingInfo`, `MRMediaRemoteSendCommand` | Private | Resolve on 27.2 per the study (`docs/NOTCH-SYSTEM-SOURCE-PLAN.md:80`). Not re-checked here |
| The rest of the helper's table: `MRMediaRemoteGetNowPlayingApplicationIsPlaying`, `MRMediaRemoteGetNowPlayingClient`, `MRNowPlayingClientGetBundleIdentifier`, `MRNowPlayingClientGetParentAppBundleIdentifier`, `MRMediaRemoteGetNowPlayingApplicationPID`, `MRMediaRemoteRegisterForNowPlayingNotifications`, `MRMediaRemoteSetElapsedTime`, two notice names and the info key constants | Private | Candidate names from public header dumps, written from memory and unverified. The probe exists to say which resolve; a wrong name costs one entry in `p4.missing` |
| The interpreter, its built-in loader, an ad hoc library loading | System | Verified on 27.2 by the system source plan (`:75-78`). Not re-run here |
| Seven space functions, level 400, flag 1, selector 7 | Private | Names per `docs/NOTCH-LOCK-SCREEN-PLAN.md:333`; shapes unverified until this probe runs |
| A removal function, `SLSRemoveWindowsFromSpaces` | Private | Candidate name, unverified, looked up only, in `LockSpace.swift` |
| `responsibility_get_pid_responsible_for_pid`, looked up in the already loaded system library, in `StepZeroProbe.swift` only | Private | Name from memory, unverified. Missing or failing means refusal. It is one more private name in the Zeus executable, so decision 1 covers it |
| The parent is launchd under Launch Services; the launch service name variable begins `application.<bundle id>.`; `open --args` adds no argument of its own | System behaviour | Unverified on 27.2. Each fails toward a refusal |
| `CGSessionCopyCurrentDictionary`, the lock and screensaver notices, `kern.bootsessionuuid` | Public or undocumented | As the lock plan's table (`:103-115`) |
| `AEDeterminePermissionToAutomateTarget`, with and without asking | Public | Used today at `Sources/Zeus/App/PermissionsModel.swift:530-536`; its own comment says it can block while a consent sheet is up (`:462`), hence the limits |
| That Music counts a skip only between 2 s and 20 s of play | Vendor behaviour | From memory of the vendor's help text, unverified. The skip parts say "may count one skip" either way |
| `CBCentralManager.authorization`, one manager, `IOBluetoothDevice` registrations, `pairedDevices()`, the class-of-device numbers | Public | Header lines in `docs/NOTCH-EARBUDS-PLAN.md:86-92`. Not re-read here |
| Four battery keys; mode selectors `0x6c73746d` and `0x6c736d73` | Private, undocumented | Names per the earbuds plan (`:93-96`); unverified |
| File event sources on a folder and on a file opened for events only | Public | The Focus plan marks the header unverified (its open-source table) and states that a folder source misses an in-place rewrite (`:315`). `StepZeroFocusWatchTests` proves both on a temporary folder |
| `NWBrowser`, `kDNSServiceErr_PolicyDenied` | Public | Per `docs/NOTCH-OUTPUT-PLAN.md:129-132` |
| `SecStaticCodeCheckValidity` with the nested-code and strict flags, on Zeus's own bundle | Public | The tree validates files without resources today (`PeerSigning.swift:102-103`); the stricter call is new code and unverified |
| `proc_pid_rusage`, `proc_pidpath` | Public | The second is used at `InsomniaRestore.swift:189`; the first is unverified |
| `tccutil reset` with a Bluetooth service name, to repeat E1 from a clean state | System tool | Unverified, as the earbuds plan says (`:45-46`). Runbook only, never run by the probe |

## The report

One file per run: `~/Library/Application Support/Zeus/StepZero/step-zero-YYYYMMDD-HHMMSS.json`, built from the
account's real home (as `main.swift:11` reads it), never from the environment, although `ZeusPaths.supportDirectory`
honours `ZEUS_SUPPORT_DIR` (`Sources/ZeusCore/ZeusPaths.swift:12-18`). The folder is made with mode 0700, the file
with 0600. It stays on the Mac: the probe opens no connection, starts no upload and names no host. The owner copies
it.

Fields, complete:

| Field | Content |
| --- | --- |
| `format`, `version` | `zeus.step-zero`, 1 |
| `createdAt` | Time of the run |
| `system` | `version`, `build`, `hardware` (the Mac's model identifier) |
| `build` | `zeusVersion`, `stamp` (`ZeusBuildStamp`, `bundle.sh:39`), `signing` (`developerID`, `localIdentity`, `adHoc`), `hardenedRuntime` |
| `sections[]` | `id` (P, L, K, E, F, O, A), `state` (`done`, `partial`, `skipped`, `notRun`) |
| `answers[]` | `q` (a catalogue id), `result` (`yes`, `no`, `notMeasured`, `skipped`, `notTried`, `endedProcess`, `timedOut`), `values` (the fields of the table above) |
| `restored[]` | One entry per write: `what` (`playState`, `track`, `position`, `elected`, `canary`, `listeningMode`, `defaultOutput`, `lockSpace`, `registrations`, `children`), `ok` (`yes`, `no`, `unknown`) |
| `notPutBack[]` | Closed codes for effects the probe cannot undo: `skipCount`, `playerHistory` |
| `grantsAtStart[]` | Per grant the probe can read, its state when its section began: `bluetooth`, `fullDiskAccess`, `automationMusic`, `automationSpotify`, each `on`, `off` or `unknown`. Local Network has no read call and is always `unknown` |
| `leftOn[]` | Grants that were not on at the start and stand at the end |
| `takenOff[]` | Grants that were on at the start and are off at the end |
| `summary` | Per plan: `go`, `stop` or `open`, a closed reason list, and the counts |

A value is one of five kinds and nothing else: a flag, a count, milliseconds, a code, a list of codes. A code can
only be made from a literal in the source (`StaticString`), so no string that arrives at run time can become one;
the decoder accepts the same closed alphabet when it reads a file back. The codec has no free string.

Five tags are the only run-time text, each held to its own strict shape and withheld (written as the code `other`)
when it does not fit:

| Tag | Shape |
| --- | --- |
| `system.version` | One to three groups of one or two digits, joined by dots |
| `system.build` | Two digits, one capital letter, one to four digits, at most one small letter |
| `system.hardware` | One of a fixed list of family names (`Mac`, `MacBookPro`, `MacBookAir`, `MacBook`, `Macmini`, `MacPro`, `iMac`, `iMacPro`, `VirtualMac`), then one or two digits, a comma, one or two digits |
| `build.zeusVersion` | One to three groups of one to three digits, joined by dots |
| `build.stamp` | Fourteen digits, a hyphen, one to seven digits (the shape `bundle.sh:39` writes) |

Nothing about a device is a tag. A string of twelve hex digits, a serial-shaped string or a device name fits none
of the five shapes, and the codec tests prove each is withheld.

Never in the report, the journal, a log line or the window: a track title, artist, album or artwork; an app's
bundle id (only its class: browser, player, system, other); a device name, model name, serial number, address or
audio UID; a Focus name, the people and apps a Focus allows, or a symbol name from the store; a speaker, computer or
network name; a file's bytes; a key the owner typed; a user or account name; the boot id. Battery levels are kept as
a class, not a number. The canary token is random and is never written. The owner's earbuds model, which the builders
of E4 and E5 need, is written by the owner into the earbuds plan, not by the probe.

The last screen shows a digest of the report: the first 16 hex digits of the SHA-256 of the file. The owner puts it
in the name of the copy (`step-zero-<date>-<digest>.json`), so a builder can recompute it with `shasum -a 256` and
see that the file is the one the owner saw.

## What is written, and how each is put back

| Write | Put back | When the process ends in between |
| --- | --- | --- |
| Pause, play, seek | The play state the section began with, and the first position (within 2 s), each read back | The journal marks the step; the next start says the player may be paused and restores nothing by itself |
| Next, previous | Previous follows next at once, then the first position. The position inside a track that was skipped back to is not exact, and `restored.position` says so | The same |
| The canary entry | Cleared, and the clear is read back. Then the elected app is read: when it is the app from before, `restored.elected` is yes and a player that was playing is started again; when it is not, the window asks the owner to press play in the player, reads again and records the result | It disappears with the process (the entry belongs to it) |
| The owner's play-key press in P6 | The state is read after the press and brought back to the state the section began with | The same as pause and play |
| Player scripts on the lock screen | `playpause` is sent twice; previous follows next; the first position is written back after unlock | The journal marks the step |
| The listening mode | The first value written back and read back | The journal holds the first value as a code from 1 to 4; the next start offers "Put back", gated, and writes it after the same device checks |
| The default output | The first device written back and read back | Not restored: its identity is never stored. The next start says "Check your sound output" |
| A space and a panel | Hidden, destroyed, closed, then a census, on the first of: the unlock notice, the session dictionary reading unlocked (polled every 100 ms), a session-active or session-resigned notice, or the hard limit | They end with the process (question L12 records it) |
| Registrations, the manager, the browser, file sources, children | Released or stopped before the section ends | They end with the process; a child is looked for at the next start and stopped, inside the gated "Put back", only if it is Zeus's own |
| The journal | Deleted when the report is written | Read once at the next start |

Not put back, and said so in the sentences, in `notPutBack` and on the last screen: a skip the player may have
counted and whatever a player adds to its own listening history for a track that played for a moment.

Not put back by the probe, because the owner made them: a grant answered in a prompt or switched in System Settings,
a Focus turned on, a mirrored display. The report lists them under `leftOn` and `takenOff`, and the last screen names
both: "Still on: Bluetooth" and "Turn back on: Full Disk Access". The Focus section orders its two switches so that
Full Disk Access ends as it began. The probe changes no setting of Zeus and none of macOS.

## Security: how this could be abused, and how each way is closed

| Abuse | Closed by |
| --- | --- |
| Another program of the same user starts Zeus with the flag | A release for users has no sealed marker and exits. In the owner's marked build the gate needs Zeus to be its own responsible process, so a start through a shell or a helper is refused; through `open`, a window appears and nothing runs before a press; with normal Zeus running the start is refused; after 72 hours every start is refused |
| A marked build stays on disk after the run | The expiry. Runbook step 8 also moves the marked app and its rollback copy to the Trash: `scripts/install.sh` copies whatever it replaces into the rollback folder and never deletes it (`scripts/install.sh:4`, `:51-58`), so the marked build would otherwise live there |
| It adds the marker, or moves the date, in an installed app | The static signature check fails. Signing the bundle again loses the Developer ID identity, and with it every grant macOS holds for Zeus |
| It assembles its own bundle with the marker and an ad hoc signature | That bundle is not Zeus to macOS: it holds none of Zeus's grants. Rows that talk to the consent system are fixed at "Not run" unless the signature is a Developer ID |
| The flag arrives through a `zeus://` link, a file open, a settings import, a socket command, a hook, the bridge or a voice turn | None of them can set the arguments of a process. Links reach `application(_:open:)` in a running app (`Sources/Zeus/App/AppDelegate.swift:546-559`) and map to a closed set of cases (`Sources/Zeus/App/DeepLinks.swift:20-41`). An import reads option values only (`Sources/Zeus/App/SettingsStore.swift:305-314`). Zeus reopens itself with the bundle path and no argument (`Sources/Zeus/App/PermissionSweepRunner.swift:83-87`). The probe is decided before `AppDelegate` exists and has no entry from it. Lint: the flag string appears in one Swift file and one list |
| A program with Accessibility access presses Continue | Such a program can already drive every app. The 1.5 second arming delay and the key-window rule remove the cheap version. Named as accepted |
| The report is read by another program | It holds facts only, by construction of the codec, and is 0600 inside a 0700 folder |
| The report is replaced by another program before the owner copies it | The digest on the last screen, carried in the copy's name. No answer depends on an earlier report: the boot comparison lives in the journal |
| A planted file, link or folder at the report path makes Zeus overwrite something | A new name per run, opened with `O_CREAT`, `O_EXCL` and `O_NOFOLLOW`; the folder must be a real folder owned by the user with mode 0700, or the probe writes nothing and says so |
| A forged journal steers a restore or a kill | Only catalogue ids, closed codes, one pid and one boot mark of 16 hex digits are read; anything else discards the journal. Nothing in it acts before the owner presses Continue on "Put back". A restore re-checks the device as a first write does. A child is stopped only when `isOrphan` holds: the vendor's interpreter, parent 1, the same user, Zeus's own library path. A forged boot mark can only flip one evidence flag; named as accepted |
| A forged report misleads a builder | The report is evidence because the owner produced and copied it. A builder checks the digest, the build stamp and the date against the run the owner names |
| The library or the plain reader is swapped | Both live inside the sealed bundle; the seal is checked at the gate and the library again just before the spawn. The interpreter is a fixed system path, with constant arguments and an environment built from the account record |
| The probe as a door into Zeus's grants | It serves no socket and takes no input but button presses and the journal. `AppDelegate` never starts, so the command socket, the bridge and the agents are not running |
| The lock-screen card as a door onto a locked Mac | It shows fixed words, one button and a ruler; no text entry, nothing of the owner's. It exists only inside a lock part, never during the L6 transitions, and is closed on every way out, including a hard time limit |
| A hostile device name, service record or store file | Never stored and never drawn; the window shows words and counts. Reads are bounded (4 MB a file, 128 services, 64 bytes a record key from a closed set) |
| A listening-mode or output write without the owner | One caller each, the gated part. Lint: no `StepZero` name under `Intent/`, `Voice/`, `Chrome/`, `Agents/`, `App/DeepLinks.swift`, `App/DebugCommands.swift`, `App/CommandCenter.swift`, `App/AppDelegate.swift` or the `zeus-cli`, `zeus-bridge` and `zeus-hook` targets |
| A log line leaks what a section read | Lint over every path this plan creates, Objective-C files included (Z1). The child's standard error goes to the null device |

## Loader files: created now, and not yet

The probe is the first caller of the fail-closed loaders, so it creates them under the names the six plans fixed,
with the lowest layer only. Each feature ticket then extends its file instead of creating it. This also keeps the
lints of those plans true while the probe stays in the tree: each private name, path or call has the one home file
its plan gave it, and the probe's section files reach it only through that file.

| File | Created by | Holds now | The feature ticket adds |
| --- | --- | --- | --- |
| `Sources/ZeusCore/TopBar/SystemSourceLaunch.swift` | Z3 | `interpreter`, `program`, `arguments(libraryPath:)`, the three environments, `isVendorInterpreter`, `isOrphan` (`docs/NOTCH-SYSTEM-SOURCE-PLAN.md:289-293`) | P1b: `PreflightVerdict`, `minimumSystem`, and the one environment step zero picked |
| `Sources/ZeusNowPlayingHelper/` (`ZNPSymbols.m`, the header, `ZNPProbe.m`) | Z3 | The one table, opened by absolute path, all or nothing; a facts-only entry | P1c: the resident entry, `ZNPEncodeItem`, `ZNPDecodeCommand`, `ZNPScaleArtwork`. P1c deletes `ZNPProbe.m` or keeps it for a later run |
| `Sources/Zeus/TopBar/SystemSourceCanary.swift` | Z4 | Publish one entry, clear it | P1e: nothing; it runs it from the reducer's effect |
| `Sources/Zeus/LockScreen/LockSpace.swift`, `LockSpaceTests.swift` | Z5 | L3 as written: `LockSpaceHosting`, `LiveLockSpace`, the seven-name table, and the removal candidate as a name that is looked up and has no call site | L3: the constants step zero corrects; it binds REG-502 to the one-file lint Z5 already wrote and adds REG-503 |
| `Sources/Zeus/Earbuds/BluetoothConsent.swift` | Z6 | `current()` from the class property; one manager, power alert off, never scanning; `abandon()` | E4: the protocol and `LiveBluetoothConsent` |
| `Sources/Zeus/Earbuds/EarbudsBatteryProbe.swift` | Z6 | The four names, one guarded read, the closed codes for an encoding and a value class | E4: the protocol and `LiveEarbudsBatteryProbe` |
| `Sources/Zeus/Earbuds/ListeningModeDevice.swift` | Z6 | The two selectors; has property, size, read, settable, one checked write | E5: the protocol, the queue, the listener, `LiveListeningModeDevice` |
| `Sources/ZeusCore/Earbuds/EarbudsTypes.swift` | Z6 | `BluetoothAccess` only | E0: every other type |
| `Sources/Zeus/SystemFocus/SystemFocusStoreReader.swift` | Z7 | The folder and the two file names, and one bounded open, `fstat` and read. The folder name lives here only (`docs/NOTCH-FOCUS-PLAN.md:319-321`) | F3: the struct, the stamps, `read(ifChangedFrom:)`, `live()` |
| `Sources/Zeus/TopBar/SpeakerBrowser.swift` | Z8 | One browser per declared type, never resolving or connecting; the only file that names `NWBrowser(` (`docs/NOTCH-OUTPUT-PLAN.md:455`) | O5: `SpeakerSighting`, the state mapping, the class as the plan writes it |

Must not be created yet: `SystemSourceMachine.swift`, `SystemSourceWire.swift`, `SystemSourceRules.swift`,
`SystemNowPlayingFeed.swift`, `SystemSourceChild.swift`; `SessionPresence.swift` and its monitor, `LockSurface.swift`,
`LockContent.swift`, `LockWindow.swift`, `LockSurfaceController.swift`, `LockMedia.swift`; any other earbuds type,
`DefaultOutputWatch.swift`, both earbuds controllers; `SystemFocusStore.swift`, `SystemFocusWatch.swift`,
`SystemFocusMonitor.swift` and the Focus machine (the probe's watch takes its paths from the reader file and lives in
the section); `OutputRoutes.swift`, `OutputList.swift`, `SpeakerDiscoveryController`, `NetworkSpeakers.swift`;
`PositionReread.swift`; any setting, any settings row, any change to `AppDelegate.swift`, `SnapshotRenderer.swift`
or `Resources/Info.plist`. The probe reads the default output and the session with a few lines of its own inside its
section files; ER1 and L0 do not count them and nothing else may call them.

## The window

One ordinary titled window, 560 points wide, title "Step zero". In this mode Zeus takes the regular activation policy
so the window can be key (the app is an accessory otherwise, `Resources/Info.plist:23-24`). Its `sharingType` is
always `.none`: `ZeusWindowSharing.apply` needs the value of a setting
(`Sources/Zeus/App/ZeusWindowSharing.swift:29-32`, `:61-63`) and the probe reads none. The probe calls
`GlassFonts.register()` itself, as the settings harness does (`main.swift:78`), because it runs before the normal
call (`main.swift:94`).

- Seven rows: "System source", "Lock screen", "Kill test", "Earbuds", "Focus", "Sound output", "Music position".
  Each row has its name, a result word with a symbol, and Continue and Skip. A first row "Put back" appears only
  after a run that ended early.
- Result words: "Not run" `circle`, "Running" `arrow.triangle.2.circlepath`, "Your turn" `hand.point.up.left`,
  "Done" `checkmark.circle`, "Partly done" `circle.lefthalf.filled`, "Skipped" `forward`, "Stopped"
  `exclamationmark.triangle`. The word carries the meaning; the symbol and colour only repeat it.
- The open row shows one line at a time and nothing else: the gated sentence, or one instruction for a hand step
  ("Lock the Mac. Unlock it when the card has shown."), with Done, Start, or Yes, No and Not tried. Before a
  section's first Continue the row also lists what it needs as nouns with symbols ("Earbuds", "Second display",
  "Phone"), so the owner can choose Skip. No tagline, no helper text, no progress prose, no counts of what passed.
- The last row is "Show report", enabled when every section is done or skipped. Beside it: the grants still on, the
  grants to turn back on, what was not put back, the report's digest, and the line "Move this build to the Trash".
- Existing type roles and button styles; tabular numerals for the one timer. Reduce Motion: nothing moves. Every
  control has a VoiceOver label equal to its visible word, and Tab reaches them in reading order.
- The lock card is its own panel: the words "Zeus probe", one button named "Press", a ruler strip that ignores
  clicks. Its `sharingType` is `.none`. Nothing else can be drawn there.

## Z0. Report model

New files under `Sources/ZeusCore/StepZero/`, all `Sendable`, no system call.

- `StepZeroReport.swift`: `StepZeroQuestion` (id, plan, `who`, `prompt`, `stops`, `needs`), the catalogue of 45,
  `ProbeCode` (made from a `StaticString` only), `ProbeValue` (the five kinds), `ProbeTag` (five cases, each with its
  shape), `StepZeroAnswer`, `StepZeroReport`.
- `StepZeroCodec.swift`: `encode` and `decode` for version 1. An unknown version, an unknown question id, a value of
  the wrong kind, a code outside the alphabet, a count outside 0 to 1,000,000 or a file over 256 KB is refused whole.
- `StepZeroJournal.swift`: steps `started`, `finished` and `timedOut`, a child pid, one owed restore (a mode code from
  1 to 4), the grants at the start, one boot mark. `resume(_:)` gives the answers to mark `endedProcess`, what "Put
  back" owes and the next part.
- `StepZeroSummary.swift`: the stop rules of the six plans as data, in `combined(_ reports:)`.

| Plan | `stop` | `go` | Otherwise `open`, with a reason |
| --- | --- | --- | --- |
| System source | All three attempts of P1 miss and the owner said the item was playing (`docs/NOTCH-SYSTEM-SOURCE-PLAN.md:151`) | P1 yes on any attempt | `unanswered`. The canary is dropped only on a P6 no whose precondition was not `stillPlaying`; with `stillPlaying` it is `canaryOpen` |
| Lock screen | A no at L2, L3 or L4 (`docs/NOTCH-LOCK-SCREEN-PLAN.md:80`) | L2, L3 and L4 yes with `l4.cycles` of 20 or more, in a report from macOS 27 and in one from macOS 26 (`:57-59`) | `cycles`, `secondMac`, `unanswered`. One report alone can never give `go` |
| Earbuds | Per route: a route whose questions fail stays closed (`docs/NOTCH-EARBUDS-PLAN.md:59`) | Per route | `unanswered` |
| Focus | No change seen by any of the three watchers, or a key missing (`docs/NOTCH-FOCUS-PLAN.md:81`) | Change seen, keys present, the owner's timing answer yes | `slow` when the only miss is the owner's timing answer; `unanswered` |
| Sound output, Music position | None: their answers size constants | Answered | `unanswered` |

Tests first: `StepZeroReportTests` (45 ids, unique, 12 Auto, 24 Guided, 9 Owner; every question of the six lists has
an entry), `StepZeroCodecTests` (round trip; each refusal; no public way to put a run-time string in a value; in
every tag a title-like string, a string of twelve hex digits, a serial-shaped string such as twelve capitals and
digits, and a name with a space are each withheld; a good value of each tag passes), `StepZeroJournalTests` (a step
left `started` becomes `endedProcess`; a forged entry discards the journal; the owed restore survives; a boot mark
that is not 16 hex digits discards it), `StepZeroSummaryTests` (each stop rule; P1 yes on attempt B alone is `go`;
three misses without the owner's yes is `open`; lock with 19 cycles is `open`; lock with one report is `open`; lock
with a 27 and a 26 report is `go`; `open` on a skip; no word holds U+2014 or U+2013).

## Z1. Gate, launch mode, packaging

- `StepZeroGate.decide` is pure. It takes the arguments, the marker, the expiry and the time now, the seal, the
  responsible pid, the own pid, the parent pid, the service name, the other instances, and the console and lock
  states, and gives `notRequested`, `refused(Reason)` or `run`. `StepZeroProbe.runIfRequested()` gathers the facts
  only when the flag is present; it is the one file that names the responsibility lookup. `StepZeroSeal.intact()` is
  the static check, off the main thread, 10 s. `StepZeroReportWriter` makes the folder and the file and returns the
  digest.
- `scripts/bundle.sh`: with `STEP_ZERO_PROBE=1`, `PlistBuddy` lines after `:39` for the marker, the expiry (build
  time plus 72 hours) and the two usage strings with the service list; a refusal when `RELEASE=1` is also set.
  Signing is unchanged: a Developer ID identity already gets a time stamp and the hardened runtime without
  `RELEASE=1` (`:27-30`, `:71-75`).
- `scripts/package.sh` refuses the variable; `scripts/verify-release-signature.sh` fails on either key.
- `test_step_zero_lint.py` owns the lints that span the wave, written over the fixed list of paths this plan names,
  so each passes on the day Z1 merges and binds when a file lands (the earbuds plan uses the same method, `:309-312`).

Fail closed: any fact the gate cannot read counts as failed. A writer error leaves no partial file.

Tests first: `StepZeroGateTests` (no flag gives `notRequested` whatever else is true; the flag with any second
argument is refused; each of the seven checks refuses alone; an expiry in the past, and one more than 72 hours ahead,
refuse; a responsible pid that differs, a nil one, a parent other than 1 and a service name of another app each
refuse; all seven give `run`), `StepZeroWriterTests` in a temporary folder (a link at the path, a folder with mode
0755 and an existing file are each refused; the file is 0600; the digest matches the bytes), `test_release_scripts.py`
(a marked bundle gets the keys through the mock at `:108`; marked with `RELEASE=1` fails; packaging a marked build
fails; the release check fails on the marker), `test_step_zero_lint.py` (the flag string in one Swift file; the
responsibility name in one file; no `StepZero` name in the listed folders; no `NSLog`, `print(`, `os_log`, `Logger(`,
`fprintf` or `printf(` to standard error in `Sources/Zeus/StepZero/`, `Sources/ZeusNowPlayingHelper/`,
`Sources/zeus-np-plain/`, `Sources/Zeus/LockScreen/LockSpace.swift`, `Sources/Zeus/Earbuds/`,
`Sources/Zeus/TopBar/SystemSourceCanary.swift`, `Sources/Zeus/TopBar/SpeakerBrowser.swift` and
`Sources/Zeus/SystemFocus/SystemFocusStoreReader.swift`; `Tests/` never names a live section type or the gate's live
facts), each with a fail-first sample as `test_source_lint.py:157` does.

## Z2. Window, flow and watchdog

`StepZeroFlow.reduce(_:_:) -> (State, [Effect])` in ZeusCore: per section `notRun`, `asking(part)`, `running(part)`,
`yourTurn(step)`, `done`, `partial`, `skipped`, `stopped`. Events: `continuePressed`, `skipPressed`, `armed`,
`partFinished`, `partTimedOut`, `handAnswered`, `resumed(journal)`. Effects: `arm(1.5)`, `run(part, limit)`,
`journal(step)`, `writeReport`. `run` is emitted only by `continuePressed` on an armed gated part, and always carries
the limit of the table above. A build whose signing is not `developerID` can reach only the System source parts.
`StepZeroSession` (main actor, `@Observable`) holds one state and runs effects through `protocol StepZeroSection`,
with no live default. `StepZeroWatchdog` is the background timer.

Tests first: `StepZeroFlowTests` (no `run` without a `continuePressed`; a press before `armed` is dropped; Skip
records skipped and moves on; a section with a prompt shows its sentence state first; a resumed journal with an owed
restore shows "Put back" first and emits nothing before its Continue; every part has a limit; `partTimedOut` for each
row of the limits table records `timedOut`, journals and moves on or stops as that row says; an ad hoc build cannot
reach a part outside System source), `StepZeroSessionTests` with fake sections (a fake's `run` is never called before
Continue; a fake that never finishes is ended by the limit; every result word has a symbol that resolves; the hosted
view holds no string outside the fixed list; the window's `sharingType` is `.none`).

## Z3. System source: library and launch rules

A new Objective-C target `ZeusNowPlayingHelper` (as `ZeusObjCGuard`, `Package.swift:25`), a dynamic library product
made from it, and a small executable target `zeus-np-plain` that depends on that target (two targets cannot share
source files, so it links the target, not the files) and holds only `main.m`. `ZNPSymbols.m` resolves every name of
the table or keeps none. `ZNPProbe.m` registers for notices on its own dispatch queue, reads short commands (`read`,
`cmd <n>`, `seek`, `token <hex>`, `poll <seconds>`) on a second thread and runs `CFRunLoopRun` on the main thread; it
prints lines made of digits and closed words only, to standard output, and writes nothing to standard error. It
compares titles and the token in its own memory and prints yes or no. `StepZeroHelperLine.decode` accepts those
shapes, at most 256 bytes a line, and nothing else.

In a marked build `bundle.sh` copies the library into `Contents/Frameworks` and the reader into `Contents/MacOS`, and
signs each before the app with its own identifier (`app.zeus.mac.nowplaying-helper`, `app.zeus.mac.np-plain`). They
stay out of `Contents/Helpers`, which peer identity reads (`Sources/ZeusCore/PeerSigning.swift:34`). The builder
confirms that `codesign --verify --deep --strict` (`bundle.sh:76`) and the gate's strict check both accept the
layout. The build has the host's architecture only (`bundle.sh:33-34`), like the rest of Zeus.

Tests first: `SystemSourceLaunchTests` (the launch half of the cases in the system source plan, `:315-318`; each of
the three environments holds only its listed names and no value from the caller's environment),
`StepZeroHelperLineTests` (each line shape; a line with a letter outside the closed words is bad; an oversized line),
`StepZeroHelperTests` in `ZeusAppTests` with an injected lookup (one missing name gives no table and names it; a fake
register function that delivers on the helper's queue while the input thread is blocked is seen within the wait). No
test starts the interpreter, loads the framework or calls the live entry (`test_step_zero_helper_lint.py`).

## Z4 to Z8 and ZK. The section tickets

Each replaces its stub, takes its loaders by injection, journals every risky step before it runs, runs under the
limits of the table, and has an App or Core suite that uses fakes only.

| Ticket | Behaviour beyond the question table | Tests first |
| --- | --- | --- |
| Z4 | Order: P1 with the attempts of P5, P2, P4, P7 (pause and play; seek for a player), P6 with its precondition, the skip part, P11, P9, then P8's timing. Three misses at P1 skip P4 to P9. Every command is followed by its restore before the next. The child's standard error is the null device | `StepZeroSystemSourceTests`: a fake child that reports nothing sends no command; a miss on attempt A and a hit on B records P1 yes and `homeUserTmp`; next, previous and seek are never sent when the class is not `player`; next is not sent before 21 s; the canary is not published while the fake still reports playing unless the 5 s wait ran, and the precondition is recorded; the canary is cleared on every path; after the clear a changed elected app asks the owner and records `restored.elected`; the play state ends as it began after the key press; a child that never answers gives `timedOut`; no line from the child reaches an answer except through the decoder |
| Z5 | The panel uses L5's style (`docs/NOTCH-LOCK-SCREEN-PLAN.md:407`). A space exists only inside a lock part and is destroyed on the first of the four ways out, with the census after each. No space is made for L6. A `false` from any call ends the part with the step named. The player part reads and asks Automation before the first lock and sends nothing to a player that is not allowed. `test_step_zero_lock_lint.py` holds the lock plan's `test_space_functions_are_named_in_one_file` now, plus: the removal name appears only in `LockSpace.swift` and only inside the name table | `StepZeroLockTests`: a fake host that fails `attach` leaves no window; unlock always destroys; with no unlock notice ever, the dictionary poll destroys; with neither, the hard limit destroys; a session-resigned notice destroys; no `makeSpace` during an L6 transition; the key counter stores counts only; a player whose check is `refused`, `notRunning` or `timedOut` gets no script; `LockSpaceTests` as L3 writes them |
| Z6 | Order: E1 (a), (b), (c) with a hand answer after each gated step, E2, E6, E4, E5, then E3 last. Nothing classic is touched while the class property says denied. The classic calls stay on the main thread, under the watchdog | `StepZeroEarbudsTests`: a fake consent that is denied touches no device; a prompt at step (b) makes `managerPrompts` `notMeasured`; a manager that never reports a state ends at 10 s; the mode write is followed by the restore even when the read back fails or times out; a mask that disagrees with the value writes nothing; an encoding outside the table becomes `other` |
| Z7 | Three fields decoded per record, the bytes dropped at once; the history lists are never decoded (`docs/NOTCH-FOCUS-PLAN.md:122-124`). The grant's state is read when the section begins and sets the order of F6 and F7. F8 is its own gated part. `test_step_zero_focus_lint.py`: the folder name in one file; the section never reads the tool result's text fields | `StepZeroFocusFactsTests` with synthetic JSON and invented names: no name survives into a fact; a missing key is a no, not an error; 4 MB cap. `StepZeroFocusWatchTests` on a temporary folder, real event sources, no store path: a file rewritten in place is seen by the file source; a replaced file is seen and the source is reopened; with both sources disabled the 250 ms check still sees the change; a grant that was on at the start ends on |
| Z8 | The browser is cancelled when the part ends or after 20 s. The switch part needs a connected Bluetooth output or is `notMeasured`. `test_step_zero_output_lint.py`: `NWBrowser(` in one file, which never names `NWConnection`; each browsed type is one of the two declared | `StepZeroSoundFactsTests`: transport codes outside the table become `other`; a name with the 12-hex prefix is counted and never kept; record keys outside the two are ignored |
| ZK | Runs after the System source and Lock screen rows are done or skipped. Variant one: it starts the helper child, asks the owner to lock, shows the card, and after 5 s ends the process with `SIGKILL`; the next start runs the census, looks for the child, and asks whether the card was gone. Variant two, for the plan's own wording (`docs/NOTCH-LOCK-SCREEN-PLAN.md:77`): the card is held for at most 60 s after unlock so the owner can Force Quit by keyboard or run `killall Zeus`; with no kill in 60 s the probe destroys the space itself and records Not tried. Then the owner restarts the Mac and starts the probe again, and the boot mark in the journal answers the last part of L12 | `StepZeroKillTests`: the journal is written before the kill; a resumed journal marks P8 and L12 from the census and the orphan rule; the 60 s hold always ends in a destroy; a changed and an unchanged boot mark give yes and no |

## Z9. The owner's runbook

Ready list. "Lost" names the questions that become Not tried or `notMeasured` without the item; the window shows the
same needs on each row before its Continue.

| Item | Needed | Lost without it |
| --- | --- | --- |
| A song in Music, playing | Required | P7's player parts, L8, A2 |
| A browser tab with a video, as the app with no scripting feed | Required | P1 as the plan words it, P11 for that app |
| Full Disk Access for Zeus, on or off; the owner switches it twice | Required for the Focus row | F1 to F9 |
| A custom Focus, made beforehand | Required for F4 | F4 |
| Earbuds, paired, worn for the mode and switch parts, with their case | Optional. With no earbuds: skip the Earbuds row and the switch part | E1 to E6, O3 |
| A second user account on this Mac | Optional | The two switch transitions of L6 |
| A wireless speaker on the same network | Optional | O1, O2, one case of P9 |
| A second device that can stream to this Mac, with the Mac's receiver on; a call in a browser tab; a private window | Optional, one per case | The matching case of P9 |
| A second display | Optional | The external numbers of L7 and L11, F9 |
| The phone, with Focus sharing across devices | Optional | F3's phone half |
| Spotify, running, if used | Optional | Its half of L8 |
| One Apple silicon Mac on macOS 26 | Required before L3 and L5 are scheduled (`docs/NOTCH-LOCK-SCREEN-PLAN.md:57-59`) | The lock plan stays open |
| An Apple silicon Mac on macOS 14 or 15 | Optional | P10, E7, F10 |

Time, on macOS 27.2: build and install 10 minutes; System source 15; Lock screen 30 (twenty cycles alone take about
10); Kill test with the restart 10; Earbuds 15; Focus 12; Sound output 5; Music position 3. About 90 minutes at the
window. What can wait for a second sitting, each with a fresh marked build: the three P9 cases that need equipment,
the Owner questions L9 to L11 and O4, F3 and F9, the two extra signatures of P3 (about 15 minutes), the macOS 26 Mac
(about 40 minutes, lock and kill rows) and the older releases. Leaving those out, the first sitting is about 60.

`<models-dir>` is `$HOME/AI-Brain-build`. `<name>` is `the Developer ID certificate common name`. `<that path>` is `the ad hoc or local Zeus.app copied in this step`.

1. In the probe worktree: `STEP_ZERO_PROBE=1 SIGN_IDENTITY="Developer ID Application: <name>" scripts/bundle.sh`.
   The build answers the flag for 72 hours.
2. Quit Zeus from its menu. `scripts/install.sh build/Zeus.app /Applications/Zeus.app`, which keeps a rollback copy of
   the normal app and refuses while Zeus runs (`scripts/install.sh:1-9`, `:23-25`). Note the rollback path it prints.
3. Start the video, then the song. Then `open -n /Applications/Zeus.app --args --step-zero-probe`. Never run the
   executable inside the bundle from a terminal, a script or a launch job: the probe refuses, because something else
   would answer for Zeus.
4. Work down the window. Read each sentence, then Continue or Skip. When a step asks, lock the Mac, wear the
   earbuds, press Start, or answer Yes or No. On the lock screen press Tab, Space and Return once each and type no
   letters.
5. If a card ever stays on the desktop, or the window stops answering: `killall Zeus` in Terminal, then the `open`
   command again. If the card still stays, log out and in.
6. Kill test: when the window says so, run the same `open` command; then restart the Mac, log in, and run it once
   more. The probe resumes from its journal each time and asks before it puts anything back.
7. Press "Show report". Copy the file to `<models-dir>/zeus-plans/step-zero/` with the digest from the last
   screen in its name. Write the earbuds model beside it by hand.
8. Quit the probe. Move `/Applications/Zeus.app` (the marked build) to the Trash, then put the normal app back:
   `ditto` the rollback copy from step 2 to `/Applications/Zeus.app`, or run `scripts/install.sh` with a normal build
   and then move the newest folder under `~/Library/Application Support/Zeus/Rollbacks/` to the Trash, because it is
   the marked build. In System Settings, act on the two lists of the last screen: grants still on, and grants to turn
   back on.
9. P3, the other two signatures. Build twice more with the marker: `SIGN_IDENTITY=-` for ad hoc, and with no
   `SIGN_IDENTITY` for the local identity when the development keychain exists (`bundle.sh:21-25`). Copy each to its
   own path, `<models-dir>/step-zero-p3/adhoc/Zeus.app` and `.../local/Zeus.app`, never to `/Applications`. With
   no Zeus running, `open -n "<that path>" --args --step-zero-probe`: only the System source row is offered. Copy both
   reports, then move both builds to the Trash.
10. The macOS 26 Mac, required for the lock plan: steps 1 to 8 there, Lock screen and Kill test rows at least. A
    copied build is quarantined; notarizing it or clearing the flag by hand is the owner's choice. The same steps on
    a 14.x or 15.x Mac answer P10, E7 and F10. O4 is tried in normal Zeus.
11. If E1 step (b) raised the prompt, repeat the Earbuds row once after the owner's own `tccutil reset` for
    Bluetooth and `app.zeus.mac` (service name unverified).

## Changes this makes to the six plans

- Their step-zero sections stay as the list of questions; "a throwaway probe outside the repo" becomes "the report
  of this probe". Results are copied from the reports into each plan before its private-route tickets start.
- P1b, P1c, P1e, L3, E0, E4, E5, F3 and O5 find their file already there and extend it (table above). P1d keeps
  `scripts/bundle.sh` and makes the library copy unconditional; P1c already planned the `Package.swift` edit.
- The lints those plans name hold with the probe in the tree, because every private name, the Focus folder name and
  `NWBrowser(` each stay in the one file its plan fixed. L3 finds its one-file space lint already written and binds
  REG-502 to it. The Focus and output plans' "new file" rows for `SystemFocusStoreReader.swift` and
  `SpeakerBrowser.swift` become "extend".
- The lock plan's step zero keeps its two Macs and its twenty cycles; the summary enforces both.

## Repo hazards that apply

- A `ZeusAppTests` suite with no `native-<Suite>` row in `qa/feature-map.json` is compiled and never run; Z1, Z2,
  Z3, Z4, Z5, Z6, Z7 and ZK each add their rows and merge in that order.
- `test_release_scripts.py` runs the real `bundle.sh` against a mock tool set (`:105-119`); Z1 and Z3 extend it or
  the release-scripts job breaks.
- A callback from Bluetooth, Core Audio, a file source or the browser must not be written in a main-actor type; it
  lives in a type that is not isolated and hops, as the earbuds plan says for E4.
- `docs/TILING-PLAN.md:188-189` reads the clean-room rule as a ban on all space calls (as the lock plan reports,
  `:337`; not re-read here); Z5 writes the exception line.
- `Automation.allowed` answers false until its first background check ends, and a finished check writes a defaults
  key (`PermissionsModel.swift:343-346`, `:476-485`, `:378-386`). The probe must not call it.

## What stays impossible to learn without the features

- How the resident helper behaves over hours: leaks, service restarts, idle cost, and the canary in real doubt cases.
- The real lock card: artwork, lyrics, the two-second meeting refresh, days of lock cycles, the sign-in window after
  a restart, and whether every capture interface honours `sharingType`.
- Other earbuds models, two pairs at once, late battery reads over many sessions, and what a mode sounds like.
- A Focus on an account that never used one, schedule edge cases, and long-lived agents under the grant.
- The exact delay between a click in Control Center and the store changing: the probe cannot see the click, so that
  answer is the owner's eye and an upper bound from a button press.
- Whether a switch of output holds through a working day, and speakers from other makers.
- Whether notarization accepts a build that names private symbols: the marked build is signed, not notarized.
- What a later macOS closes. The probe can be run again after an update, with a fresh marked build; it cannot predict
  one.
- Releases and processors the owner has no Mac for. Their floor stays the lowest release with a report, and an Intel
  Mac needs a universal build that no ticket here makes.

## Decisions the owner owes

Before the build:

1. The written exceptions. The probe is the first code to make the private calls, so the approval lines owed by the
   lock plan (decision 8) and the system source plan (decision 6) are owed before Z3 and Z5 merge. One more private
   name is new here and needs the same line before Z1 merges: the responsibility lookup in the gate.
2. The Local Network part. It asks for that permission before decision D5 of the output plan is made. Skipping it
   leaves O2 to the two Terminal commands of that plan.
3. The wording of the two usage strings in a marked build; a prompt will show them.
4. The kill test: the probe ends itself while the card is up, and holds the card for up to a minute after unlock for
   the owner's own Force Quit. The other choice: drop the hold and answer only the self-kill.
5. Keep or remove. Planned: the probe stays in the tree, inert without a sealed marker younger than 72 hours, to run
   again after each macOS update. The other choice: each wave deletes its section when its feature ships.
6. The skip parts. They may add one skip to a track's count in the player's library, which cannot be undone. The
   other choice: skip those parts and leave "next" and "previous" unanswered in P7 and L8.

After the reports, as inputs and trade-offs, not verdicts:

7. System source: go or stop on P1; the environment P5 found; the canary on P6 (decision 2); bundling only if an own
   helper cannot work (decision 7); the floor from P10 (decision 9); what P9 shows for a call in a browser tab
   (decision 8).
8. Lock screen: go or stop on L2 to L4, from both Macs; the version gate (decision 4); placement from L7 (decision
   6); what to do beside the system's own media controls (decision 9).
9. Earbuds: adaptive as a choice (decision 2); name only if the battery keys are closed (decision 3); the floor of
   the mode row (decision 8).
10. Focus: build F1 to F5 or not (decision 1), including what to do when the change is seen but the owner judged it
    slower than a second; a schedule that leaves no record (decision 4); the reach of the grant from F8 (decision 6);
    versions (decision 7).
11. Sound output: D5 with O2's facts; the usage string (decision 3). Music position: the mode A2 ships with.
12. Which other Macs get a run, and whether an Intel Mac matters enough for a universal build.

## Verification for this wave

1. Tests are committed before the code and shown failing on the base.
2. `swift build --build-tests`, then `swift test --filter` for each suite named above: ten in `ZeusCoreTests`, nine
   in `ZeusAppTests`.
3. `python3 -m unittest discover -s qa/closed-loop/tests -p 'test_*.py'`, the release-scripts tests, and
   `./tools/check.sh` in development mode from a worktree under `<models-dir>`.
4. An independent review of each diff, reading the gate, the writer, every restore, every limit and every journal
   step line by line, and a search of the built report for any string longer than a code.
5. Seen on a Mac, by the builder of Z1: an unmarked build started with the flag exits with 64 and shows nothing; a
   marked build started from a terminal refuses; started from a terminal through a double fork it refuses; started
   by a launch job it refuses; with Zeus running it refuses; with the clock past the expiry it refuses; through
   `open` it shows the window. If the responsibility lookup does not resolve on 27.2, that goes back to the owner.
6. Still owed by the owner: Z9, on macOS 27.2 first, then the macOS 26 Mac.

## Review notes

An adversarial review left 29 findings against the first version. Each was checked against the code and the six
lists. All 29 were confirmed at least in part and none was rejected whole. Three were met in another way than the
review proposed, and three were taken only in part; both groups are listed below with the reason.

Changed as found:

- Device text in the report (blocking). `e6.modelTag` is gone. The device is now a closed class from the public
  class-of-device number, and the owner writes the model by hand. The run-time tags are five, not three (the first
  version missed that the Zeus version and the build stamp are run-time text too), each with its own shape, and the
  codec tests withhold twelve hex digits, a serial shape and a name.
- F2, F5 and E3. Three watchers instead of a folder source alone, as the Focus plan itself requires (`:315`); a
  Start button starts the clock; the report holds a window code and the owner's own "within a second" answer in
  place of a millisecond figure the probe could not measure.
- P1 and P5. Three environments, P1 yes on any, the stop rule only after all miss and the owner confirms playback.
- P6. The precondition of the system source plan (`:115-117`) is met and recorded before the canary; the elected app
  and the play-key press are in the restore table.
- P7. Next, previous and seek only for a player class; next only after 21 s; the skip count is listed as not put
  back; next and previous are a gated part of their own with a sentence that says so.
- The gate. A parent of 1 is no longer taken as proof; the responsible process is checked, with two public signals
  beside it, all marked unverified, and a double-fork case at the Mac.
- L8. Confirmed in code: `Automation.allowed` is false on first call (`PermissionsModel.swift:476-485`),
  `TopBarServices.music` is private and its verbs are `playpause`, `next track` and `previous track` (`:229`,
  `:238-240`). The probe now calls the public check itself, unlocked, with limits, and sends bounded scripts. One
  thing the review did not say: `Automation` also writes a defaults key (`:378-386`), a second reason not to use it.
- The lock space now ends on the first of four ways out and is never made during L6.
- Every effect has a limit, and a background watchdog journals, restores and exits.
- The helper keeps a run loop on its main thread, with a test.
- E1 is three steps with an answer after each.
- Full Disk Access: the state at the start is recorded, the order of F7 follows it, and `takenOff` exists.
- F8 has its own gated sentence and closed result codes.
- The lock plan's two Macs and twenty cycles are in the summary and the runbook.
- The marked build expires after 72 hours, the runbook trashes it and its rollback copy, and L12's restart is inside
  the sitting.
- P3 has a runbook step at separate paths, and a build without a Developer ID can run only the System source row.
- The ready list, the time estimate (about 90 minutes), the parallel-ticket file claim, field closure, the gated
  "Put back", the kill test as its own row with the owner's Force Quit, the L3 key instruction, the logging lint
  over every created file with the child's standard error discarded, the window's fixed `sharingType` and its own
  font registration, the reader target and its signing, the report digest and the completed consent sentences.

Changed, but not as the review proposed:

- Lints of the sibling plans. No allow-list was added to those plans. The probe's reads moved behind the home files
  the plans fixed: Z7 now creates the lowest layer of `SystemFocusStoreReader.swift` and Z8 that of
  `SpeakerBrowser.swift`, and the removal candidate lives in `LockSpace.swift` under a lookup-only lint. The browse
  of an undeclared service type is dropped: no step-zero list asks for it, and the output plan declares both keys
  whatever the answer.
- F8's target. The review kept the bookmarks file and asked for an existence check. The probe now uses the one
  protected folder Zeus's own check already lists (`OnboardingServices.swift:228-232`), which always exists, so no
  personal file is named or opened and the missing-file case cannot arise.
- The backstop check reads the file's stamp every 250 ms and the content only when the stamp moved, with one last
  read at the end, in place of a full read four times a second.

Rejected, with reasons:

- "Run Bluetooth off the main thread." Half taken. The manager has its own queue and a 10 s limit. The classic calls
  stay on the main thread because that is where E4 will make them (`docs/NOTCH-EARBUDS-PLAN.md:485`) and the question
  is how they behave there; the watchdog bounds them.
- "Build a universal binary for P10." Not taken. The whole app is built for the host's architecture
  (`scripts/bundle.sh:33-34`), not only the helper, so the fix would be a build-system change far outside this
  wave. The limit is stated instead: older releases need an Apple silicon Mac, and an Intel run is decision 12.
- "Commercial products are named (Spotify, Safari)." Not taken for the player: the rule bans naming products of the
  probe's own kind, the six plans and the code name this player throughout (`NowPlaying.swift:29`,
  `SpotifyPlayer.swift:98`), and a consent sentence must use the name the system prompt will show. The browser's name
  left the plan with the change to F8.

One reading of this plan's own, not asked by the review: the Focus stop rule is kept, but a no that rests only on
the owner's judgment of one second gives `open` with the reason `slow`, not `stop`. It is put to the owner in
decision 10.

Not verified in this session: anything marked unverified above, every behaviour of macOS, and every licence. All
code citations were read on `3757de2`; plan citations were read in `docs/` on the same commit. The plan file sits in
an untracked folder of `<models-dir>` and no Zeus worktree was touched.
