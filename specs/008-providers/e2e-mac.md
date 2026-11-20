# Mac end-to-end: fake voice providers

Someone else runs this on a Mac, in a separate clone, with the fake provider only.
There is no real ElevenLabs key and no real Google key in this run.

This repository has no Xcode project and no XCUITest target. Do not add one for this run.
Playwright does not drive the native app. The run uses the existing Accessibility harness:

- `scripts/bundle.sh` builds `build/Zeus.app` inside the clone
- `scripts/human-qa.sh` launches that app and drives it
- `scripts/human-qa.swift` is the Accessibility driver the shell compiles with `xcrun swiftc`
- `qa/closed-loop/human_qa.py` writes the report

The fake is an in-process `URLProtocol` (`VoiceProviderFakeProtocol`), switched on only when
`ZEUS_VOICE_PROVIDER_FAKE` is `1` or `fail`. The provider path is HTTPS-only, so a plain local
HTTP server is refused and is not used. The fake never opens a socket to ElevenLabs or Google.

The fake key is the literal `zeus-e2e-fake-key`. It is not a vendor credential.
It is stored in the test-only Keychain service `app.zeus.voice-provider.e2e.elevenlabs`,
account `api-key`. The production service `app.zeus.voice-provider.elevenlabs` is not written
and must not be deleted.

One Test voice sample is not the 30-turn percentile in
`specs/007-companion-parity/perf-budgets.md`. This run passes when that one
`voice.first-audio` sample is at or under 600 ms (the voice-leg budget) and at or under
1,400 ms (the direct-stream p95).

## 0. Separate clone

Do this in a new directory. Do not use the copy of Zeus you run every day.
Do not copy the app to `/Applications`.

```sh
git clone https://github.com/mysticalsin/Zeus-native.git "$HOME/AI-Brain-build/zeus-voice-providers-src"
cd "$HOME/AI-Brain-build/zeus-voice-providers-src"
git fetch origin zeus-bot/voice-providers
git checkout zeus-bot/voice-providers
```

Expected: `git status -sb` prints `## zeus-bot/voice-providers` and a clean tree.
`pwd` prints a path under `$HOME/AI-Brain-build/zeus-voice-providers-src`, not `/Applications`.

Quit any Zeus that is already running. The harness refuses to start if one is:

```sh
if pgrep -x Zeus >/dev/null; then kill -TERM "$(pgrep -x Zeus | head -n 1)"; fi
for _ in 1 2 3 4 5 6 7 8 9 10; do pgrep -x Zeus >/dev/null || break; sleep 0.2; done
pgrep -x Zeus || echo "no Zeus process"
```

Expected: `no Zeus process`.

The terminal running the harness needs Accessibility permission
(System Settings > Privacy & Security > Accessibility). The script checks and does not prompt.
If it exits 2 with "not allowed to control the computer", turn Accessibility on for that
terminal, quit and reopen the terminal, and start again from this directory.

## 1. Build

```sh
CONFIG=debug bash scripts/bundle.sh
```

Expected, as the last line:

```text
Built build/Zeus.app
```

Confirm the binary is the one in this clone:

```sh
python3 - <<'PY'
import os
binary = os.path.realpath("build/Zeus.app/Contents/MacOS/Zeus")
root = os.path.realpath(".")
assert binary.startswith(root + os.sep), binary
assert "/Applications/" not in binary, binary
print(binary)
PY
```

Expected: one path, `$HOME/AI-Brain-build/zeus-voice-providers-src/build/Zeus.app/Contents/MacOS/Zeus`.

## 2. Add the provider, validate, pick the voice, test it

```sh
export ZEUS_VOICE_PROVIDER_FAKE=1
bash scripts/human-qa.sh "$PWD/build/Zeus.app" --from-clone --only voice-providers --yes
```

Expected while it runs:

```text
WARNING: this run uses your REAL Zeus settings domain (app.zeus.mac) for the provider selection only.
The fake key is stored under Keychain service app.zeus.voice-provider.e2e.elevenlabs.
The production service app.zeus.voice-provider.elevenlabs is not written and is not deleted.
```

Then `Zeus pid <pid>. Evidence: <dir>` and, at the end:

```text
Partial run (--only voice-providers): Zeus is left running and any setting the journey changed is not restored.
Report:  <dir>/report.md
```

`<dir>` is under `$HOME/AI-Brain-build/zeus-human-qa/`. Copy it:

```sh
EV1="$(ls -dt "$HOME/AI-Brain-build/zeus-human-qa/"20* | head -n 1)"
echo "$EV1"
```

Expected report verdict:

```sh
grep -F 'Verdict: **pass**' "$EV1/report.md"
```

Expected: a line `Verdict: **pass**`. The report lists `voice.open`, `voice.key`, `voice.validate`,
`voice.pick`, and `voice.test` as PASS. `voice.key` says `fake key entered` and does not print the key.
`voice.validate` says `ready, E2E Voice listed`. `voice.pick` says `E2E Voice selected`.
`voice.test` says `ElevenLabs is speaking`.

The app is still running. Confirm the test-only item exists, and that the command output does not
contain the key (this form of `security` prints attributes, not the secret):

```sh
security find-generic-password -s app.zeus.voice-provider.e2e.elevenlabs -a api-key >"$EV1/keychain-present.txt" 2>&1
echo "find-exit:$?"
grep -F 'app.zeus.voice-provider.e2e.elevenlabs' "$EV1/keychain-present.txt"
if grep -F 'zeus-e2e-fake-key' "$EV1/keychain-present.txt"; then echo LEAK; exit 1; else echo "key absent from keychain listing"; fi
```

Expected:

```text
find-exit:0
"svce"<blob>="app.zeus.voice-provider.e2e.elevenlabs"
key absent from keychain listing
```

The `svce` line is the attribute dump. `find-exit:0` means the item is there.

## 3. Logs must not contain the key

```sh
if grep -F 'zeus-e2e-fake-key' "$EV1/zeus-log.txt" "$EV1/report.md" "$EV1/receipt.json" "$EV1/app-stdout.txt" "$EV1/driver-main.log"; then
  echo LEAK
  exit 1
else
  echo "key absent"
fi
log show --last 20m --style compact --predicate 'process == "Zeus" AND eventMessage CONTAINS "zeus-e2e-fake-key"' >"$EV1/log-show-key.txt"
if grep -F 'zeus-e2e-fake-key' "$EV1/log-show-key.txt"; then echo LEAK; exit 1; else echo "key absent from log show"; fi
```

Expected:

```text
key absent
key absent from log show
```

## 4. Latency signposts

```sh
log show --last 20m --style compact --predicate 'subsystem == "app.zeus.voice" AND category == "provider"' >"$EV1/signpost.txt"
grep -F 'voice.first-audio' "$EV1/signpost.txt"
ms="$(grep -h 'first_audio_ms=' "$EV1/zeus-log.txt" "$EV1/signpost.txt" "$EV1/app-stdout.txt" | sed -n 's/.*first_audio_ms=\([0-9][0-9]*\).*/\1/p' | head -n 1)"
echo "first_audio_ms=$ms"
test -n "$ms"
test "$ms" -le 600
test "$ms" -le 1400
echo "voice.first-audio ${ms} ms (pass: <= 600 voice leg, <= 1400 direct-stream p95)"
```

Expected: at least one `voice.first-audio` line, then:

```text
first_audio_ms=<n>
voice.first-audio <n> ms (pass: <= 600 voice leg, <= 1400 direct-stream p95)
```

`<n>` is an integer. Both `test` commands exit 0. If `first_audio_ms` is missing, the run fails
even if the UI said the provider was speaking.

## 5. Force a failure and hear the local voice

Quit the fake-success process first. The next launch is a new process with synthesis forced to fail.
Validation still succeeds. Test voice must not stay silent: the status names the local voice, and
the Mac voice speaks the sample line.

```sh
if pgrep -x Zeus >/dev/null; then kill -TERM "$(pgrep -x Zeus | head -n 1)"; fi
for _ in 1 2 3 4 5 6 7 8 9 10; do pgrep -x Zeus >/dev/null || break; sleep 0.2; done
pgrep -x Zeus || echo "no Zeus process"
export ZEUS_VOICE_PROVIDER_FAKE=fail
bash scripts/human-qa.sh "$PWD/build/Zeus.app" --from-clone --only voice-providers-fail --yes
```

Expected warning mentions the same test-only Keychain service. The report ends with
`Verdict: **pass**`. Steps `voice.fail.open`, `voice.fail.key`, `voice.fail.validate`,
`voice.fail.test`, and `voice.fail.remove` are PASS. `voice.fail.test` says
`Speaking with the local voice`. You hear that line from the Mac voice. Silence is a failure
even if the report says pass.

```sh
EV2="$(ls -dt "$HOME/AI-Brain-build/zeus-human-qa/"20* | head -n 1)"
grep -F 'Verdict: **pass**' "$EV2/report.md"
grep -F 'Speaking with the local voice' "$EV2/report.md"
```

Expected: both greps print a matching line. `EV2` is a different directory from `EV1`.

## 6. The key is gone

```sh
set +e
security find-generic-password -s app.zeus.voice-provider.e2e.elevenlabs -a api-key >"$EV2/keychain-gone.txt" 2>&1
find_exit=$?
set -e
echo "find-exit:$find_exit"
test "$find_exit" -ne 0
grep -F 'could not be found in the keychain' "$EV2/keychain-gone.txt"
security delete-generic-password -s app.zeus.voice-provider.e2e.elevenlabs -a api-key >"$EV2/keychain-delete.txt" 2>&1 || true
grep -F 'could not be found in the keychain' "$EV2/keychain-delete.txt"
if grep -F 'zeus-e2e-fake-key' "$EV2/zeus-log.txt" "$EV2/report.md" "$EV2/receipt.json" "$EV2/app-stdout.txt" "$EV2/driver-main.log" "$EV2/keychain-gone.txt" "$EV2/keychain-delete.txt"; then
  echo LEAK
  exit 1
else
  echo "key absent"
fi
```

Expected:

```text
find-exit:44
could not be found in the keychain.
could not be found in the keychain.
key absent
```

`find-exit` is non-zero. 44 is the usual Security framework code for a missing item.
The second `could not be found` is the cleanup delete, which must be a no-op because Remove
already deleted the item. Do not run `security delete-generic-password` against
`app.zeus.voice-provider.elevenlabs`.

Quit the app:

```sh
if pgrep -x Zeus >/dev/null; then kill -TERM "$(pgrep -x Zeus | head -n 1)"; fi
pgrep -x Zeus || echo "no Zeus process"
unset ZEUS_VOICE_PROVIDER_FAKE
```

Expected: `no Zeus process`.

## What this run does not prove

A live call to ElevenLabs or Google. A 30-turn p50 or p95. Playback quality of a real voice.
Those stay MAC-PENDING. The opt-in live contract, which needs a real key and must not print it,
is in `specs/008-providers/spec.md` and is a different run.
