# Stress matrix v1

Hammer's Mac soak. This file is the procedure. It was not executed on the Linux host that wrote it. A row stays BLOCKED until its gap is closed. A rebuild of the app voids the run.

Integration head when this procedure was written: `2722dcb7497d5415fbc1fcb1f65c49629966a281`.

## Build under test

```sh
SHA8=$(git rev-parse --short=8 HEAD)
SIGN_IDENTITY=- scripts/bundle.sh --skip-extension
APP="$HOME/Desktop/Zeus-latest-${SHA8}.app"
ditto build/Zeus.app "$APP"
```

`scripts/install.sh` stays unused. Do not copy the app to `/Applications`. `--skip-extension` is the packager flag that records `extension: skipped` and does not run npm. On a tree that still runs npm from `bundle.sh`, do not run that script.

`HEAD.txt` in the evidence root, written once:

```sh
EVIDENCE="$HOME/Library/Logs/Zeus/stress-v1-${SHA8}"
mkdir -p "$EVIDENCE"
{
  echo "sha8=$SHA8"
  echo "full=$(git rev-parse HEAD)"
  codesign -dv "$APP" 2>&1
  shasum -a 256 "$APP/Contents/MacOS/Zeus"
} > "$EVIDENCE/HEAD.txt"
shasum -a 256 "$EVIDENCE/HEAD.txt" >> "$EVIDENCE/HEAD.txt"
```

Any later rebuild voids the run. Compare `codesign -dv` and the binary hash with `HEAD.txt` before each case. If either differs, stop.

## Global rules

- At least 6 GiB free on the volume that holds `$EVIDENCE` before the first case: `df -g "$EVIDENCE"`.
- Launch with `open -n -a "$APP"`. Record the PID from that launch:

```sh
open -n -a "$APP"
sleep 2
PID=$(ps -ax -o pid=,comm= | awk -v app="$APP/Contents/MacOS/Zeus" '$2==app {print $1; exit}')
echo "$PID" > "$EVIDENCE/pid.txt"
```

- Kill only that PID. `kill -TERM "$PID"`; if it is still alive after 5 seconds, `kill -KILL "$PID"`. No `pkill`. No `killall`.
- A watchdog samples every 5 seconds. Abort the case when RSS or elapsed time crosses that case's cap.

```sh
watchdog() {
  local cap_s="$1" cap_kib="$2" peak=0
  while kill -0 "$PID" 2>/dev/null; do
    local rss cpu
    rss=$(ps -o rss= -p "$PID" | awk '{print $1}')
    cpu=$(ps -o %cpu= -p "$PID" | awk '{print $1}')
    echo "$(date -u +%H:%M:%S),$rss,$cpu" >> "$EVIDENCE/$ROW/metrics.csv"
    if [ "${rss:-0}" -gt "$peak" ]; then peak=$rss; fi
    if [ "$SECONDS" -gt "$cap_s" ] || [ "${rss:-0}" -gt "$cap_kib" ]; then
      echo "ABORT cap s=$SECONDS rss_kib=$rss" >> "$EVIDENCE/$ROW/RESULT.md"
      kill -TERM "$PID"
      return 2
    fi
    sleep 5
  done
  echo "peak_kib=$peak" >> "$EVIDENCE/$ROW/RESULT.md"
}
```

RSS from `ps` is kibibytes. 1.5 GiB is 1572864. 2 GiB is 2097152. 1 GiB is 1048576.

- Provider traffic goes only to a stub on `127.0.0.1`. Real APIs are banned. If the build has no endpoint override, the case is BLOCKED and the gap below is the record.
- Synthetic keyboard or pointer input only when Accessibility is already granted. If a case would raise a new TCC or microphone prompt, it is BLOCKED. Do not click the prompt.
- Synthetic WAV input only through a test or loopback input when one exists. There is no loopback input on this head. `Zeus --transcribe <file.wav>` feeds one file through dictation and does not drive barge-in.
- `leaks` and `footprint` at T0, after the warm-up named in the case, and at the end. `vmmap --summary "$PID"` at the end.
- Each case writes `metrics.csv`, `footprint`, `leaks`, `log.txt`, `RESULT.md`, and `SHA256SUMS` under `$EVIDENCE/$ROW/`.

```sh
(cd "$EVIDENCE/$ROW" && shasum -a 256 metrics.csv footprint leaks log.txt RESULT.md > SHA256SUMS)
```

`log.txt` is `log show --last 2m --predicate 'process == "Zeus"' --style compact` taken at the end, or the abort line if the process is already gone.

## Testability gaps on this head

| Gap | Why the case cannot run | Where |
| --- | --- | --- |
| No provider endpoint override | The local engine URL and the cloud engine URL are fixed in `Sources/Zeus/Brain/Providers/OpenAICompatProvider.swift`. Nothing reads a debug stub URL. Z5 is BLOCKED. A DEBUG-only, off-by-default override is a separate change. | Z5 |
| No loopback audio input | `SpeechInput` uses the selected or system microphone (`Sources/Zeus/Voice/SpeechInput.swift:660`). No test device and no debug file injector for start, stop, or barge-in. Z4 is BLOCKED. | Z4 |

## Cases

### Z1 — 2 hour soak, one chat every 5 minutes

Cap 2 h 10 min (7800 seconds) and 1.5 GiB. Warm up 15 minutes with the notch closed and no chat. Then one short local chat every 5 minutes. The chat must hit the 127.0.0.1 stub. If the override is absent, mark Z1 BLOCKED rather than call a real API.

Pass: RSS at the end is under 15% above the footprint taken at 15 minutes. `leaks` at the end reports 0 new leaks against T0. Idle CPU in the last 10 minutes of `metrics.csv` stays under 2%. No main-thread hang over 5 seconds. If a sample of the main thread exceeds 5 seconds, that sample file is the repro and the case FAILs.

### Z2 — sessions open and close

50 sessions, then 75, close all, repeat the pair three times. Cap 30 min and 2 GiB.

Pass: after the last close, RSS is within 10% of the T0 footprint. Open latency p95 under 500 ms, taken from the timestamps in `metrics.csv` around each open. `leaks` reports 0 new leaks.

On this head there is no debug injector for 75 sessions, so Z2 is BLOCKED until a seeder exists. Record that in `RESULT.md`.

### Z3 — pointer and modifier spam

500 hover or click events, 300 Right Command taps at 5 Hz, 300 Right Option holds at 2 Hz, then 100 interleaved. Cap 20 min and 1 GiB. Post the events only when Accessibility is already granted. Otherwise BLOCKED.

Pass: the visible state matches the last input (chord up, one bar, no extra overlay). 0 duplicate overlays. CPU under 2% within 10 seconds of the last event.

Right Command and Right Option are read by `HotkeyMonitor` (`Sources/Zeus/Voice/HotkeyMonitor.swift`). Sleep interrupts an open turn (`HotkeyMonitor.swift:241-247`). This case stays awake.

### Z4 — voice start, stop, barge-in

200 start/stop cycles and 100 barge-ins against the stub. Cap 30 min and 1.5 GiB.

BLOCKED on this head. No loopback input. Do not grant the microphone from the test.

Pass, once a loopback exists: thread count at the end is the T0 count plus or minus 2. Nothing is left listening. `leaks` reports 0 new leaks. A barge-in stops the previous turn in under 300 ms.

### Z5 — provider faults

For each HTTP provider, 20 rounds of: HTTP 500, a hang past 45 seconds, a hang past 20 seconds, a connection reset, and a trickle. Cap 40 min and 1.5 GiB. The stub is the only peer.

BLOCKED on this head. No endpoint override. The local engine timeout in source is 8 seconds and the cloud engine timeout is 20 seconds (`OpenAICompatProvider.swift:117`). Do not point the cloud URL at a real host.

Pass, once the debug override is on and aimed at `127.0.0.1`: the 45 second and 20 second timeouts fire within 2 seconds of those marks, the UI shows an error or a fallback, the next request succeeds, there is no retry storm, and `lsof -p "$PID" -a -iTCP` returns to the T0 socket count.

### Z6 — sleep and wake

Operator step. 10 cycles. `pmset sleepnow` with no sudo. The person wakes the Mac.

Pass: the menu bar and the hotkeys answer within 3 seconds of wake. No duplicate bars. The notch refreshes on wake (`Sources/Zeus/Notch/NotchController.swift:111-114`).

### Z7 — display hot-plug

Operator step. 10 cycles of unplug and replug.

Pass: exactly one bar on each connected display. No orphan window. `NotchController` refreshes on `didChangeScreenParametersNotification` (`Sources/Zeus/Notch/NotchController.swift:104-108`).

### Z8 — energy

During Z1 and Z3, sample with `top -l 2 -s 5 -pid "$PID" -stats pid,cpu,power`. No `powermetrics`.

Pass: idle energy under 5, and idle CPU is not sustained above 20%. A single sample above 20% is recorded and is not a fail. Two consecutive idle samples above 20% fail.

## Report

Fill this after a Mac run. This host did not run it. BLOCKED rows are filed from the source, not from a soak.

| Case | Head | Result | Peak RSS | Growth | Leaks | p95 | CPU idle |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Z1 | `2722dcb7` | BLOCKED | | | | | |
| Z2 | `2722dcb7` | BLOCKED | | | | | |
| Z3 | `2722dcb7` | NOT RUN | | | | | |
| Z4 | `2722dcb7` | BLOCKED | | | | | |
| Z5 | `2722dcb7` | BLOCKED | | | | | |
| Z6 | `2722dcb7` | NOT RUN | | | | | |
| Z7 | `2722dcb7` | NOT RUN | | | | | |
| Z8 | `2722dcb7` | NOT RUN | | | | | |

Z1 is BLOCKED because the soak chat would leave the machine if it cannot be forced onto `127.0.0.1`. Z2 is BLOCKED because there is no session seeder. Z4 is BLOCKED because there is no loopback input. Z5 is BLOCKED because there is no provider endpoint override. Z3, Z6, Z7, and Z8 need the operator at the Mac and were not started here.

A FAIL writes the repro into that case's `RESULT.md`: the command, the PID, the first bad sample from `metrics.csv`, and the `leaks` or `sample` excerpt. No FAIL was produced here.
