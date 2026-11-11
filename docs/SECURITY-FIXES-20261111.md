# Security and performance fixes, 2026-11-11

Branch `codex/security-perf-20261111`. Written without running the Swift build locally; CI is the compiler.

## H1, H2: socket peer check

Risk confirmed. `zeus.sock` (hooks, CLI) and `chrome.sock` (browser bridge) were only `chmod 0600`.
Fix: every accepted connection is checked before any byte is read (`PeerCheck`, `UnixSocketServer`).
The kernel reports the peer's uid (`getpeereid`) and pid (`LOCAL_PEERPID`); the executable path comes from `proc_pidpath`.
- `zeus.sock`: same uid only (`PeerPolicy.sameUser`).
- `chrome.sock`: same uid and the peer executable must be named `Zeus` (`ChromeSocketPeers`).
- An unidentified peer is refused. A refusal is logged with the reason and pid.
Not done: code-signature validation of the peer, and defence against pid reuse between accept and lookup. The file name check is not a signature check; it stops casual and cross-user clients, not a same-user attacker who renames a binary.

## H3: client-supplied hook fields

Risk confirmed, smaller than feared. A hook payload never chooses a command or path to run: the app only shows hook text. Two fields did reach behaviour:
- `terminal.bundleID` selected which app "jump to terminal" activates or launches. Now it must be a well-formed bundle ID, and an app that is not running is launched only if it is a known terminal or editor (`HookClientInput`).
- `risk` was trusted by the trusted-chat auto-approve and the card badge. The app now takes the higher of the claim and its own `CommandRisk` assessment. Shell commands were already judged from the real command text.

## H4: model-proposed actions

Confirmed gaps, now closed (`ModelActionApproval`):
- `terminal.agent` started a coding agent with a model-written prompt and no card. A model-originated one now asks first. The same words spoken or typed in the CLI behave as before.
- `panel.open` with a prompt and `delegate.dust` sent text to ChatGPT, Claude or Dust with no card. They now ask, like `delegate.chrome`.
- A page click whose label sends, deletes or buys now asks every time, even on a site allowed earlier, and does not widen that allowance.
Already gated, unchanged: `terminal.run` (read-only commands run, the rest ask via `ShellRiskClassifier`), Mac driving (drive autonomy setting), page changes (per-site card), browser agent. No model action writes files or runs AppleScript directly.

## M7: update feed

Risk confirmed: the feed address could be http, file or an app scheme, and the feed's download link was opened whatever its scheme.
Fix (`UpdateFeedPolicy`): HTTPS only, no credentials in the URL, redirects that leave HTTPS are refused, 256 KB cap, status 200 required, and the download link is dropped unless HTTPS (checked again before opening).
Not done: the feed format has no signature or hash. Zeus never installs the download; it only opens the link in the browser. A signed feed with a pinned key needs a format change and a publishing step.

## Performance

- `SystemHUDMonitor`: the 10 Hz repeating timer is gone. One one-shot timer re-arms after each read: 0.1 s for 2 s after a known event (media key, level change, wake), otherwise 1 s, and none while no brightness or keyboard HUD is on or the displays sleep (`SystemHUDPollPolicy`). macOS has no public notification for brightness, so a timer remains for that one case. A brightness change made without a Zeus-seen key can show up to 1 s late.
- Prewarm: no Ollama, cloud or voice warm-up at launch or wake (`BrainWarmPlan.mayWarm`). The talk key going down starts the first warm-up and a 2-minute timer that stops itself after the 30-minute active window.
- Model download: `ParakeetEngine.transcribe` no longer downloads a missing model (it throws not-ready). Only `prepare`, called from the Download buttons, may download. The lint `ModelDownloadConsentLint` in `qa/closed-loop/tests/test_source_lint.py` fails if the download call appears outside `SpeechEngines.swift`, outside the explicit path, or at launch or wake. Whisper and Speaker models were already click-only.

## Tests and regressions

ZeusCoreTests: `PeerCredentialsTests`, `ClientInputPolicyTests`, `UpdateFeedPolicyTests`, `SystemHUDPollPolicyTests`, `BrainWarmPlanTests`. ZeusAppTests: `BrainWarmSchedulerTests`. Registry rows REG-248 to REG-254.
