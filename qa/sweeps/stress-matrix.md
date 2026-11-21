# Mac stress matrix

Runnable on a logged-in Mac. This host did not execute it. The build under test is an ad-hoc app on the Desktop. Do not run `scripts/install.sh`. Do not drag the app into `/Applications`. The person grants Accessibility, Input Monitoring, microphone, screen recording, and Full Disk Access in System Settings. Nothing in this matrix clicks a permission dialog.

Findings that these rows measure are in `qa/sweeps/sweep-11-packaging-stress.md`. Integration behavior below is `codex/integration-20261111` at `2722dcb7497d5415fbc1fcb1f65c49629966a281`.

## Preamble — ad-hoc app on the Desktop

From the repository root, on a Mac, with the extension either already built or `npm` on `PATH` (S11-08):

```sh
SHA=$(git rev-parse --short=8 HEAD)
SIGN_IDENTITY=- scripts/bundle.sh
ditto build/Zeus.app "$HOME/Desktop/Zeus-latest-${SHA}.app"
APP="$HOME/Desktop/Zeus-latest-${SHA}.app"
codesign --verify --deep --strict "$APP"
codesign --display --verbose=4 "$APP" 2>&1 | tee "/tmp/zeus-${SHA}-codesign.txt"
plutil -extract CFBundleShortVersionString raw -o - "$APP/Contents/Info.plist"
plutil -extract CFBundleVersion raw -o - "$APP/Contents/Info.plist"
plutil -extract LSUIElement raw -o - "$APP/Contents/Info.plist"
```

Pass for the preamble: `codesign --verify` exits 0, the display output contains `flags=` with `runtime`, `Signature=adhoc`, and `Timestamp=none`. The short version is `0.1.0` and the build is `1` until S11-07 is fixed. `LSUIElement` is `true`. Quit any other Zeus before `open "$APP"`, because the bundle id is `app.zeus.mac`.

Record the preamble next to the samples:

```sh
mkdir -p "/tmp/zeus-stress-${SHA}"
EVIDENCE="/tmp/zeus-stress-${SHA}"
open "$APP"
sleep 3
PID=$(pgrep -f "$APP/Contents/MacOS/Zeus" | head -1)
test -n "$PID"
echo "pid=$PID app=$APP" | tee "$EVIDENCE/pid.txt"
```

## Metrics captured on every row

Run this at the start, every 60 seconds during a long row, and at the end. `footprint` is preferred. `ps` rss is the fallback.

```sh
stamp=$(date +%Y%m%d-%H%M%S)
{
  echo "stamp=$stamp pid=$PID"
  ps -o rss=,%cpu=,vsz=,etime= -p "$PID"
  footprint "$PID" 2>/dev/null | awk '/phys_footprint:/{print}'
  ps -M -p "$PID" | awk 'END{print "threads=" NR-1}'
  pgrep -lf 'zeus-hook|zeus-bridge' || true
  ls "$HOME/Library/Logs/DiagnosticReports" 2>/dev/null | grep -i zeus || true
} | tee -a "$EVIDENCE/samples.log"
```

A row fails immediately if a new file appears under `~/Library/Logs/DiagnosticReports` whose name contains `Zeus`, or if `PID` is gone. Main-thread stalls use one `sample` of 3 seconds at the end of the row:

```sh
sample "$PID" 3 -file "$EVIDENCE/sample-${ROW}.txt"
```

Pass for the sample: the main thread's heaviest stack in that file is under 250 ms. The file is the evidence. Delete it after the sweep if it contains window titles from other apps. It stays on this Mac.

Idle CPU and memory budgets already in the repo are 1% average and 150 MB (`scripts/check-perf-budget.sh:8-9` and `:22`). The script's default process match is a worktree path (S11-09), so every invocation passes `PID`.

## ST-01 — rapid hotkey spam

Physical half, 30 seconds: hold and release the talk chord by hand as fast as the keys will travel. The default chord is Control-Option (`Sources/ZeusCore/Shortcut.swift:156`).

Counted half: 200 down/up pairs in about 10 seconds. Save this as `/tmp/zeus-hotkey-spam.swift` and run `swift /tmp/zeus-hotkey-spam.swift` while the Desktop app is frontmost in the background (it is a menu-bar app). The person has already granted Input Monitoring or Accessibility.

```swift
import CoreGraphics
let down = CGEventSource(stateID: .hidSystemState)
let mask = CGEventFlags(rawValue: CGEventFlags.maskControl.rawValue | CGEventFlags.maskAlternate.rawValue)
let start = Date()
for _ in 0..<200 {
    let press = CGEvent(source: down)
    press?.type = .flagsChanged
    press?.flags = mask
    press?.post(tap: .cghidEventTap)
    Thread.sleep(forTimeInterval: 0.02)
    let release = CGEvent(source: down)
    release?.type = .flagsChanged
    release?.flags = []
    release?.post(tap: .cghidEventTap)
    Thread.sleep(forTimeInterval: 0.02)
}
print(String(format: "pairs=200 seconds=%.2f", Date().timeIntervalSince(start)))
```

`HotkeyMonitor.observeSleep` drops an open turn on sleep and wake (`Sources/Zeus/Voice/HotkeyMonitor.swift:241-247`). This row stays awake.

| | |
| --- | --- |
| Pass | The process is alive. Two seconds after the last release, no capture is still running (the menu-bar state is idle, and `ps` shows no extra audio helper the app spawned for a turn). RSS delta from the row's first sample is under 40 MB. The 3-second sample's main thread stays under 250 ms. One turn is open at a time. |
| Fail | A crash report, a turn that is still listening 2 seconds after the last release, two captures at once, or an RSS delta of 40 MB or more. |
| Metrics | `samples.log` at start and end, `sample-ST-01.txt`, the Swift script's `pairs` and `seconds` line. |

## ST-02 — 1,000 notifications

The incoming mirror reads at most 40 rows (`Sources/Zeus/TopBar/TodayController.swift:237`). Turn the in-app notification mirror on. The person grants Full Disk Access first. Post 1,000 distinct banners from this Mac, then refresh the mirror by opening the alerts surface.

```sh
for i in $(seq 1 1000); do
  osascript -e "display notification \"stress $i\" with title \"Zeus stress\""
done
```

Outgoing banners from Zeus itself use a new identifier when no replacement id is set (`Sources/Zeus/App/SystemNotificationService.swift:212-221`). This row's 1,000 items are incoming, so the mirror cap is the bound under test. `AlertStack.post` itself has no cap (S11-13). The visible stack shows 3 and a hidden count (`Sources/ZeusCore/Alerts/AlertStack.swift:49` and `:69-71`).

| | |
| --- | --- |
| Pass | The process is alive. The alerts list shows at most 40 items. The capsule shows at most 3 cards, and any remainder is the hidden count. RSS delta is under 80 MB. Main-thread sample stays under 250 ms. |
| Fail | A crash report, a list longer than 40 from this mirror refresh, more than 3 cards on screen with no hidden count, or an RSS delta of 80 MB or more. |
| Metrics | `samples.log`, `sample-ST-02.txt`, a count of rows visible in the alerts surface, written by hand into `$EVIDENCE/ST-02-count.txt`. |

## ST-03 — 1,000 approvals

Integration keeps one card and the next request waits (`Sources/Zeus/Notch/NotchController.swift:305-315`). The hook helper in the Desktop app reads one JSON event on stdin and forwards it on the app's socket. The helper's default source accepts the payload shape already used in `Tests/ZeusCoreTests/AgentHooksTests.swift:10`. Permission requests wait up to 100 seconds in `Sources/Zeus/Agents/AgentEventServer.swift:124`.

Launch all 1,000 at once, as the same user as the app. Do not answer the card.

```sh
HOOK="$APP/Contents/Helpers/zeus-hook"
mkdir -p /tmp/zeus-stress
for i in $(seq 1 1000); do
  printf '%s' '{"hook_event_name":"PermissionRequest","session_id":"stress","cwd":"/tmp/zeus-stress","tool_name":"Bash","tool_input":{"command":"echo stress-'"$i"'"}}' \
    | "$HOOK" > "$EVIDENCE/hook-$i.out" 2> "$EVIDENCE/hook-$i.err" &
done
echo "launched=1000" | tee "$EVIDENCE/ST-03-launched.txt"
```

On integration the card on screen is the only one. The other helpers stay in the wait at `NotchController.swift:313`. After 150 seconds, deny or dismiss the card that is up so the line can drain. A Developer ID build may refuse a sender that is not its own signed helper. This row is specified for the ad-hoc Desktop app, where the socket accepts the same user.

On PR #14 (`c4662bf52d8b19030bc7da401171afcb0bf62b96`) the same launch fills `pendingApprovals` with no cap (S11-13). On PR #70 (`7c000d3a8d5882593e3a1bf34afd98ae4b3be2f6`) a hub queue appends with no cap. Run this row again on those heads when they are the Desktop build, and record `pending` length if the UI shows it.

| | |
| --- | --- |
| Pass | One approval card is visible on integration. Every `hook-N.out` exists. Within 150 seconds of dismissing the card, live `zeus-hook` processes return to the count from before the row. No continuation is answered twice (each output file is one decision). RSS delta is under 150 MB. |
| Fail | More than one card on integration, a helper still running 150 seconds after the last card was dismissed, a crash report, two decision lines in one output file, or an RSS delta of 150 MB or more. |
| Metrics | `samples.log` at launch, at 30 seconds, and after drain. `ls "$EVIDENCE"/hook-*.out \| wc -l`. `pgrep -c zeus-hook` at those three times. |

## ST-04 — Scribe for 2 hours

Physical. Start one Scribe session from the menu bar and leave the room. The microphone ring is 10 seconds and a stall longer than the ring drops audio (`Sources/Zeus/Scribe/ScribeLiveCapture.swift:167-169`). Pending transcription chunks are capped at 4 per source (`Sources/Zeus/Scribe/ScribeTranscriberBridge.swift:52`). The call watcher observes wake (`Sources/Zeus/Scribe/ScribeCallWatcher.swift:348`). The capture path has no sleep observer.

```sh
# every 5 minutes, for 2 hours, with PID set to the Desktop app
for n in $(seq 1 24); do
  echo "minute=$((n*5))" >> "$EVIDENCE/ST-04-samples.log"
  ps -o rss=,%cpu= -p "$PID" >> "$EVIDENCE/ST-04-samples.log"
  footprint "$PID" 2>/dev/null | awk '/phys_footprint:/{print}' >> "$EVIDENCE/ST-04-samples.log"
  sleep 300
done
```

Stop the session from the menu bar at 2 hours. Confirm a transcript file exists under the app's support directory and that its modification time is during the session.

| | |
| --- | --- |
| Pass | The process is alive at 2 hours. After the first 10 minutes, RSS growth across the remaining samples is under 200 MB. Any gap in the transcript longer than 15 seconds has a matching dropped-audio issue in the session UI (the overload sentence from `ScribeTranscriberBridge.swift:53`, or a withheld-microphone count). Stopping the session returns the menu bar to idle within 10 seconds. |
| Fail | A crash report, RSS growth of 200 MB or more after the first 10 minutes, a silent gap longer than 15 seconds with no dropped-audio issue, or a session that is still recording 10 seconds after Stop. |
| Metrics | `ST-04-samples.log` (24 rows), the transcript file's path and byte size, and a note of any dropped-audio line. |

## ST-05 — provider failure storm

The local engine URL is `http://127.0.0.1:11434/v1` and its request timeout is 8 seconds (`Sources/Zeus/Brain/Providers/OpenAICompatProvider.swift:26` and `:117`). Point that port at a process that returns HTTP 500. One hundred talk turns then each have to finish.

```sh
python3 - <<'PY' &
from http.server import BaseHTTPRequestHandler, HTTPServer
class H(BaseHTTPRequestHandler):
    def do_POST(self):
        self.send_response(500)
        self.end_headers()
        self.wfile.write(b"storm")
    def log_message(self, *args):
        pass
HTTPServer(("127.0.0.1", 11434), H).serve_forever()
PY
echo $! > "$EVIDENCE/ST-05-server.pid"
```

Physical half: hold the talk chord, say one short sentence, and release. Repeat until 20 turns have each shown a failure. Counted half: if a debug prompt can submit text without the microphone, submit the sentence `stress` 100 times. If it cannot, the 20 spoken turns are the row, and the sheet says so.

Stop the server when the row ends: `kill "$(cat "$EVIDENCE/ST-05-server.pid")"`.

| | |
| --- | --- |
| Pass | Every turn shows a failure within 12 seconds of release. Thirty seconds after the last turn, no turn is still spinning and RSS delta is under 50 MB. The menu bar is idle. |
| Fail | A turn still running 30 seconds later, a crash report, an RSS delta of 50 MB or more, or a turn that is presented as a successful answer. |
| Metrics | `samples.log` at start and 30 seconds after the last turn, a tally of failures in `$EVIDENCE/ST-05-tally.txt`, the server pid. |

## ST-06 — sleep and wake

Physical. Five cycles. Each cycle is one minute asleep and a wake by opening the lid or pressing a key. Start one Scribe session before the first sleep (the same session as ST-04, or a fresh one if ST-04 already stopped). Leave the talk chord up.

The notch refreshes displays on wake (`Sources/Zeus/Notch/NotchController.swift:111-114`). The talk monitor interrupts an open turn on sleep and on wake (`Sources/Zeus/Voice/HotkeyMonitor.swift:244-246`). Scribe capture does not subscribe to sleep.

```sh
for n in 1 2 3 4 5; do
  echo "cycle=$n sleep $(date -u +%H:%M:%S)" | tee -a "$EVIDENCE/ST-06.log"
  pmset sleepnow
  # after the Mac is awake again:
  echo "cycle=$n wake $(date -u +%H:%M:%S) pid=$(ps -p "$PID" -o pid= || echo gone)" | tee -a "$EVIDENCE/ST-06.log"
  ps -o rss= -p "$PID" >> "$EVIDENCE/ST-06.log"
done
```

`pmset sleepnow` returns after the machine is on its way to sleep. The wake line is written by hand, or by the same shell if it is still alive after wake.

| | |
| --- | --- |
| Pass | After each wake the same `PID` is alive, the menu bar icon is on the built-in display, and the talk chord is idle. The Scribe session has either stopped with a partial transcript or stayed recording and recorded a drop for the asleep interval. No window is left on a display that is gone. |
| Fail | A crash report, a missing `PID`, a talk turn that is still listening after wake without the chord held, a transcript that joins speech from before sleep to speech from after sleep with no gap, or a panel stuck off the visible display. |
| Metrics | `ST-06.log` with five sleep lines and five wake lines, RSS after each wake, a sentence on where the menu bar icon was. |

## ST-07 — display hot-plug

Physical. With the Desktop app running and the notch visible, unplug an external display, wait 5 seconds, plug it back in, and repeat once. Then drag a window from the built-in display to the external display and back. `NotchController` refreshes on `didChangeScreenParametersNotification` (`Sources/Zeus/Notch/NotchController.swift:104-108`).

```sh
for n in 1 2; do
  echo "unplug $n $(date -u +%H:%M:%S)" | tee -a "$EVIDENCE/ST-07.log"
  # unplug, wait 5 seconds, then:
  system_profiler SPDisplaysDataType | awk '/Resolution|Display Type|Connection Type/{print}' | tee -a "$EVIDENCE/ST-07.log"
  echo "replug $n $(date -u +%H:%M:%S)" | tee -a "$EVIDENCE/ST-07.log"
done
```

| | |
| --- | --- |
| Pass | After each unplug there is one notch, on a display `system_profiler` still lists. After each replug the notch is on the display under the pointer once the pointer moves there. Panels from before the unplug are gone or have moved. RSS delta is under 40 MB. |
| Fail | Two notches, a panel whose screen is disconnected, a click that opens the panel on the wrong display, a crash report, or an RSS delta of 40 MB or more. |
| Metrics | `ST-07.log`, `samples.log` before the first unplug and after the second replug, `sample-ST-07.txt`. |

## ST-08 — memory over 1 hour idle

The app is running, the notch is closed, no Scribe session, no talk turn, and the provider-storm server is stopped. Leave the Mac awake (System Settings, prevent sleep for this hour, set by the person).

```sh
PID="$PID" SECONDS_IDLE=3600 LOG="$EVIDENCE/ST-08-budget.log" scripts/check-perf-budget.sh | tee "$EVIDENCE/ST-08-budget.out"
```

That script samples once a second and compares the average CPU with 1% and the footprint with 150 MB. It exits 2 when `PID` is empty. Record the exit code.

Also keep the slope. The script prints one footprint at the end. Take the first and last `phys_footprint` from a side sample so a slow climb that stays under 150 MB is still visible:

```sh
footprint "$PID" | awk '/phys_footprint:/{print}' | tee "$EVIDENCE/ST-08-start.txt"
# after the hour, the budget log has the end value
```

| | |
| --- | --- |
| Pass | `check-perf-budget.sh` exits 0. The end footprint is under 150 MB. The end footprint is at most 20 MB above the start footprint. No crash report. |
| Fail | Exit status other than 0, an end footprint of 150 MB or more, growth of more than 20 MB, a missing `PID`, or a crash report. |
| Metrics | `ST-08-budget.log`, `ST-08-budget.out`, `ST-08-start.txt`, the script's exit code in `$EVIDENCE/ST-08-exit.txt`. |

## Order

Run the preamble once. Then ST-08 first, while the process is still cold, or ST-08 after a relaunch so the earlier rows do not set the idle baseline. Then ST-01, ST-02, ST-03, ST-05, ST-06, ST-07. ST-04 is the long session and can overlap ST-08 only if ST-08 is a different relaunch. Write one line per row, `ST-0N pass` or `ST-0N fail`, plus the evidence directory, into `$EVIDENCE/summary.txt`.

## What this matrix does not claim

A pass on the Desktop ad-hoc app is evidence for that signed bundle. It is not a Developer ID or notarization result. S11-01 still applies to this bundle, because the ad-hoc signature uses the hardened runtime and the same entitlements file. Calendar, reminders, and location during these rows can fail closed for that reason. Record the System Settings state and the in-app result when those features are touched. A failure there is S11-01, and the stress row still has its own pass line.
