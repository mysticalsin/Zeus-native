# Mac end-to-end: orb persona

A second person runs this on a Mac, in a detached clone. It does not install Zeus, and it does not start `/Applications/Zeus.app`.

There is no `.xcodeproj` and no XCUITest target in this repository, so this procedure does not use XCUITest. Playwright does not drive the native app. `scripts/e2e.sh` uses Playwright only for its Chrome extension block; do not run that script for this proof.

The native driver is the one the repo already has:

- `scripts/bundle.sh` builds `build/Zeus.app` inside the clone.
- The clone's own binary launches that app. `scripts/e2e.sh` starts it the same way.
- `Zeus debug open-settings` talks to that process over its socket (`Sources/Zeus/App/DebugForward.swift`, `Sources/Zeus/App/CommandCenter.swift`).
- `Tests/e2e/axtree.swift` reads and presses the settings window. `scripts/e2e.sh` compiles that file with `swiftc`.
- `Zeus --voice-selftest` feeds a generated wav and a transcript. It does not open the microphone and does not call a model (`Sources/Zeus/Voice/VoiceSelfTest.swift`).
- `Zeus --orb-proof` writes one PNG per orb state and `frame-times.csv`. The audio is the injected bands below, not a capture device and not a provider.
- `scripts/check-perf-budget.sh` samples CPU with `top`.

Quit any Zeus you already have open before you start. This procedure uses your real `app.zeus.mac` preferences for the persona key, saves them, and restores them. It does not change the system Reduce Motion checkbox.

## 0. Detached clone

```sh
git clone https://github.com/mysticalsin/Zeus-native.git "$HOME/zeus-orb-mac-clone"
cd "$HOME/zeus-orb-mac-clone"
git fetch origin zeus-bot/companion-persona-orb
git switch --detach origin/zeus-bot/companion-persona-orb
git rev-parse --abbrev-ref HEAD
git rev-parse HEAD
```

Expected:

```
HEAD
```

and one 40-character commit id. `HEAD` means the checkout is detached. Record both lines in the evidence folder created below.

## 1. Evidence folder

```sh
EVIDENCE="$HOME/AI-Brain-build/zeus-orb-mac/$(date +%Y%m%d-%H%M%S)"
mkdir -m 700 -p "$EVIDENCE"
git rev-parse HEAD > "$EVIDENCE/sha.txt"
pwd > "$EVIDENCE/clone-path.txt"
```

Expected: `echo "$EVIDENCE"` prints a path under `$HOME/AI-Brain-build/zeus-orb-mac/`, not under the clone and not under `/Applications`.

## 2. Build

From the clone root:

```sh
scripts/bundle.sh
echo "bundle_exit=$?"
```

Expected: the command exits 0, and the last line is:

```
Built build/Zeus.app
```

A machine that already has the local signing identity also prints `Signing with Zeus Local Dev` earlier. That is still success.

Do not run `scripts/install.sh`. Do not copy the bundle to `/Applications`.

```sh
BIN="$PWD/build/Zeus.app/Contents/MacOS/Zeus"
case "$BIN" in
  /Applications/*) echo "REFUSED installed path"; exit 1 ;;
esac
test -x "$BIN" && echo "BINARY_OK $BIN"
```

Expected:

```
BINARY_OK /Users/<you>/zeus-orb-mac-clone/build/Zeus.app/Contents/MacOS/Zeus
```

The path is inside the clone.

`scripts/qa-startup-launch.sh` is not the launch. Its `--exec` flag is refused:

```sh
bash scripts/qa-startup-launch.sh "$PWD/build/Zeus.app" --exec
echo "qa_startup_exit=$?"
```

Expected: exit 78, and stderr contains:

```
qa-startup-launch: --exec is refused: launching the app needs independent OS isolation that does not exist
```

## 3. Classic is the default

Run this before the app is launched and before any command in this file writes the persona key.

```sh
if defaults read app.zeus.mac companion.persona > "$EVIDENCE/persona-before.txt" 2> "$EVIDENCE/persona-before.err"
then
  echo "KEY_PRESENT $(cat "$EVIDENCE/persona-before.txt")"
else
  echo "KEY_ABSENT"
fi
```

Pass: the line is `KEY_ABSENT`, or `KEY_PRESENT classic`.

`KEY_ABSENT` means this Mac has never stored the key. The app then uses Classic (`MascotPersona.id`, `classic`). The error file contains `does not exist`.

`KEY_PRESENT orb.jarvis` is a previous choice, not this build's default. Record it, do not call the default check passed, and still restore that value at the end.

## 4. Launch the clone's app

```sh
export ZEUS_SUPPORT_DIR="$(mktemp -d /tmp/zeus-orb-mac.XXXXXX)"
echo "$ZEUS_SUPPORT_DIR" > "$EVIDENCE/support-dir.txt"
"$BIN" > "$ZEUS_SUPPORT_DIR/app.log" 2>&1 &
APP_PID=$!
echo "$APP_PID" > "$EVIDENCE/app.pid"
for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30
do
  if [ -S "$ZEUS_SUPPORT_DIR/zeus.sock" ]; then echo SOCKET_OK; break; fi
  sleep 0.5
done
ps -p "$APP_PID" -o pid=,comm=
```

Expected:

```
SOCKET_OK
```

and `ps` prints `$APP_PID` and a path ending in `zeus-orb-mac-clone/build/Zeus.app/Contents/MacOS/Zeus`.

If `SOCKET_OK` does not appear, stop. Read `$ZEUS_SUPPORT_DIR/app.log`. Do not start `/Applications/Zeus.app`.

## 5. Open Appearance in that process

Keep `ZEUS_SUPPORT_DIR` exported, so this second invocation uses the clone's socket and not another Zeus.

```sh
"$BIN" debug open-settings appearance > "$EVIDENCE/open-settings.txt" 2>&1
echo "open_settings_exit=$?"
cat "$EVIDENCE/open-settings.txt"
```

Pass: exit 0 and the file is exactly:

```
Settings opened at appearance.
```

If the file is:

```
Refused: this command can use the microphone, screen or input, open Zeus's panels, or launch agents. Turn on 'Allow command-line control' in Zeus Settings ▸ Privacy to allow it.
```

turn that switch on yourself in the running app, then run the same command again. Do not write the Keychain item from this procedure. The retry must print `Settings opened at appearance.`

## 6. Read the persona control

The terminal needs Accessibility for the user you are logged in as. This compile is the one in `scripts/e2e.sh`. It is not a package or CI change.

```sh
swiftc -O Tests/e2e/axtree.swift -o "$ZEUS_SUPPORT_DIR/axtree"
echo "axtree_exit=$?"
"$ZEUS_SUPPORT_DIR/axtree" "Zeus Settings" > "$EVIDENCE/ax-classic.txt"
echo "ax_exit=$?"
grep -n "Persona and mascot" "$EVIDENCE/ax-classic.txt"
grep -n "Classic" "$EVIDENCE/ax-classic.txt"
```

Expected: `axtree_exit=0`, `ax_exit=0`, the first line of the dump is `WINDOW Zeus Settings`, one line contains `Persona and mascot`, and one line contains `Classic`. No line contains `Orb (Jarvis)` yet.

If `ax_exit` is 1 and the file is `not running`, the launched process is gone. Stop.

## 7. Switch to Orb (Jarvis)

`axtree` presses an `AXButton` whose title or description equals the argument (`Tests/e2e/axtree.swift`).

```sh
"$ZEUS_SUPPORT_DIR/axtree" "Zeus Settings" "Persona and mascot" > "$EVIDENCE/ax-press-menu.txt"
echo "press_menu_exit=$?"
cat "$EVIDENCE/ax-press-menu.txt"
"$ZEUS_SUPPORT_DIR/axtree" > "$EVIDENCE/ax-menu-open.txt"
grep -n "Orb (Jarvis)" "$EVIDENCE/ax-menu-open.txt"
"$ZEUS_SUPPORT_DIR/axtree" "-" "Orb (Jarvis)" > "$EVIDENCE/ax-press-orb.txt"
echo "press_orb_exit=$?"
cat "$EVIDENCE/ax-press-orb.txt"
sleep 1
defaults read app.zeus.mac companion.persona > "$EVIDENCE/persona-after.txt"
echo "persona_after_exit=$?"
cat "$EVIDENCE/persona-after.txt"
"$ZEUS_SUPPORT_DIR/axtree" "Zeus Settings" > "$EVIDENCE/ax-orb.txt"
grep -n "Orb (Jarvis)" "$EVIDENCE/ax-orb.txt"
```

Pass:

- `ax-press-menu.txt` contains `PRESS true`
- `ax-menu-open.txt` contains `Orb (Jarvis)`
- `ax-press-orb.txt` contains `PRESS true`
- `persona-after.txt` is exactly `orb.jarvis`
- `ax-orb.txt` contains `Orb (Jarvis)`

If a `PRESS` line is `PRESS false`, or `Orb (Jarvis)` never appears, stop. Do not write the preference with `defaults write` and call that a settings pass.

## 8. Fake audio, no model

Generate a one-second tone in the evidence folder. Nothing is recorded from the microphone.

```sh
python3 -I - "$EVIDENCE/tone.wav" <<'PY'
import math, struct, sys, wave
path = sys.argv[1]
frames = bytearray()
for i in range(24000):
    sample = int(8000 * math.sin(2 * math.pi * 220 * i / 24000))
    frames += struct.pack("<h", sample)
with wave.open(path, "w") as handle:
    handle.setnchannels(1)
    handle.setsampwidth(2)
    handle.setframerate(24000)
    handle.writeframes(frames)
print("TONE_OK", path)
PY
```

Expected: `TONE_OK` and the wav path under `$EVIDENCE`.

The self-test still requires a wav path. `--transcript` replaces recognition. The fast path for this sentence does not call a model, and `--speak` is omitted so no voice provider is asked to play it.

```sh
"$BIN" --voice-selftest "$EVIDENCE/tone.wav" --transcript "hey zeus what time is it" > "$EVIDENCE/voice-selftest.txt" 2>&1
echo "voice_selftest_exit=$?"
grep -n "fast via" "$EVIDENCE/voice-selftest.txt"
grep -n "not executed" "$EVIDENCE/voice-selftest.txt"
```

Expected: `voice_selftest_exit=0`, one line contains `fast via`, and one line contains `(not executed)`.

The file must not contain `no wake phrase`, `ClaudeCLI`, `http://`, or `https://`. This process is exempt from the single-instance guard, so it does not replace the app you launched.

## 9. PNGs, frame times, and the five states

Quit is not required. `--orb-proof` is its own process. It draws idle, listening, thinking, speaking, and compacting. Speaking uses injected bands `bass 0.35` and `mid 0.55`. The other states are silent. No provider is constructed.

```sh
"$BIN" --orb-proof "$EVIDENCE/orb" > "$EVIDENCE/orb-proof.log" 2>&1 &
PROOF=$!
top -l 4 -s 1 -pid "$PROOF" -stats cpu > "$EVIDENCE/cpu-encode.txt" 2>&1 || true
wait "$PROOF"
echo "orb_proof_exit=$?"
cat "$EVIDENCE/orb-proof.log"
ls -1 "$EVIDENCE/orb"
```

Expected: `orb_proof_exit=0`, and the log contains these lines:

```
reduce-motion: false
png: idle.png listening.png thinking.png speaking.png compacting.png
frame-log: frame-times.csv
rows: 150
frame-budget: PASS
providers: none
audio: speaking bass 0.35 mid 0.55, other states silent
```

`max_encode_ms:` is present and its number is below `8.3`.

`ls` prints:

```
compacting.png
frame-times.csv
idle.png
listening.png
speaking.png
thinking.png
```

`frame-times.csv` begins with `state,frame,encode_ms`. Each `encode_ms` is the Metal encode for that frame, not a display-link gap. The command prints `frame-budget: PASS` only when all 150 rows are under 8.3 ms, which fits one 120 Hz frame (8.3 ms) and one 60 Hz frame (16.7 ms). A row at or above 8.3 ms is a 120 Hz miss. A row at or above 16.7 ms is a 60 Hz miss. Either one makes the command exit 1 and print `frame-budget: FAIL`.

`cpu-encode.txt` is the `top` sample of that process. Pass for the animating encode is every numeric CPU sample in that file strictly under 5. A sample at or above 5 fails the core budget even if `frame-budget` is `PASS`. If the file has no numeric sample because the process had already exited, the encode CPU sample is inconclusive and is not a pass. Section 11 does not replace it.

## 10. Reduce Motion

Do not run `defaults write` on `com.apple.universalaccess`. The app ignores `ZEUS_HARNESS_REDUCE_MOTION` unless the native test host has set `ZEUS_MOTION_HARNESS_ACTIVE`, and this procedure does not set either variable.

This command freezes the orb's tumble, camera drift, and electrons, and keeps the opacity breathe. It is the same proof path as section 9.

```sh
"$BIN" --orb-proof "$EVIDENCE/orb-reduced" --reduce-motion > "$EVIDENCE/orb-reduced.log" 2>&1
echo "reduced_exit=$?"
cat "$EVIDENCE/orb-reduced.log"
```

Expected: `reduced_exit=0`, and the log contains:

```
reduce-motion: true
png: idle.png listening.png thinking.png speaking.png compacting.png
rows: 150
frame-budget: PASS
providers: none
```

The five PNGs are in `$EVIDENCE/orb-reduced/`. The particles do not travel in this run. The opacity breathe is the only motion the simulation applies.

To see that policy on the live buddy, turn on Reduce Motion yourself in System Settings, then look at the orb. This procedure does not flip that checkbox.

## 11. CPU while the launched app is up

The orb view pauses while the buddy is hidden, so this sample can be near zero and still pass. The animating budget is section 9. This sample is the launched clone, with the persona already set to Orb.

```sh
PID="$APP_PID" CPU_BUDGET=5 SECONDS_IDLE=10 LOG="$EVIDENCE/cpu-live.log" scripts/check-perf-budget.sh
echo "cpu_live_exit=$?"
grep "idle CPU avg" "$EVIDENCE/cpu-live.log"
```

Expected: the grep line matches:

```
idle CPU avg: <number>% (budget < 5%)
```

with `<number>` strictly under 5. That is the orb core threshold.

The script also requires resident memory under 150 MB and no `ollama` or `kev` helper. Those are the existing idle gate in `scripts/check-perf-budget.sh`, not the orb threshold. `cpu_live_exit` can be 1 because of memory or a helper while the CPU line still passes. Record both. The orb CPU pass is the CPU line alone.

## 12. Stop, and put the persona key back

```sh
kill "$APP_PID"
wait "$APP_PID" 2>/dev/null || true
if [ -s "$EVIDENCE/persona-before.txt" ]; then
  defaults write app.zeus.mac companion.persona "$(cat "$EVIDENCE/persona-before.txt")"
  echo "RESTORED $(defaults read app.zeus.mac companion.persona)"
else
  defaults delete app.zeus.mac companion.persona 2>/dev/null || true
  echo "RESTORED_ABSENT"
fi
```

Expected: `RESTORED classic` or `RESTORED orb.jarvis` when section 3 printed `KEY_PRESENT`, or `RESTORED_ABSENT` when it printed `KEY_ABSENT`. Section 3 creates an empty `persona-before.txt` when the key is missing, so the restore looks at a non-empty file, not at whether the file exists.

## Pass

All of these are true:

- `bundle_exit=0` and the binary path is inside the clone.
- Section 3 passed.
- `open_settings_exit=0` and the settings text is `Settings opened at appearance.`
- The AX dump showed `Classic` before the switch and `orb.jarvis` after it.
- `voice_selftest_exit=0` with `fast via` and `(not executed)`, and without a provider URL.
- `orb_proof_exit=0` and `reduced_exit=0`, each with `frame-budget: PASS`, `rows: 150`, `providers: none`, and the five PNGs.
- Every `encode_ms` is under 8.3, and every CPU sample in `cpu-encode.txt` is under 5.
- The launched app's `idle CPU avg` line is under 5.
- The persona key is restored.

A missing PNG, `frame-budget: FAIL`, a `PRESS false`, or a provider URL in `voice-selftest.txt` is a fail. Linux cannot run this file. A green Linux test is not this pass.
