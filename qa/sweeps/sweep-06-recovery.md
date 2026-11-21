# Sweep 06 — error handling and recovery

Static reading of `codex/integration-20261111` at `2722dcb7497d5415fbc1fcb1f65c49629966a281`, plus the open `zeus-bot/*` heads fetched from origin for this pass. The bug ledger on `zeus-bot/bug-ledger` (`255e52aba94234e2b194fd81b2cf4b93e628cc93`, PR #54) was read first. A row that is already there is marked `duplicate of ZB-xxx` and is not given a new fix cluster.

This file is the only change. Nothing here is wired into `Package.swift` or CI. The 45 s and 20 s request timeouts already in the tree are flagged and left alone.

## What was read

Host: Linux, no Mac app run. `swift test` cannot compile the app target here (`import Darwin`, missing system headers). Rows below are from the source at the named sha. Each repro is a failing-test sketch, not a test that was executed on this VM.

Heads opened for this lens:

| PR | Branch | SHA |
| --- | --- | --- |
| integration | `codex/integration-20261111` | `2722dcb7497d5415fbc1fcb1f65c49629966a281` |
| #53 | `zeus-bot/voice-providers` | `16c2d697dcd479f6cbe510ad65fda731b82194fa` |
| #83 | `zeus-bot/settings-permissions` | `e4ea25d8fda6f674650cc29acfdf15bccc9e6125` |
| #77 | `zeus-bot/local-calendar` | `d8ebd6f81e32` (reader also present on #83) |
| #31 | `zeus-bot/nativehost-eof` | `d328f83ded8c15f4c6d54bd23a221f12252e04dd` |
| #58 | `zeus-bot/fix-license` | `10faecc83b32849db0a712f69e807c9317d51a96` |
| #87 | `zeus-bot/haru-companion` | `583c3dcc00e5` |
| #54 | `zeus-bot/bug-ledger` | `255e52aba94234e2b194fd81b2cf4b93e628cc93` |

The companion supervisor on #87 bounds restarts (`RESTART_LIMIT` 3 inside 10 minutes) and was not given a row. Scribe checkpoint failures, routine files, and wiki settings already keep the unreadable file and say so.

## Findings

| ID | Severity | Branch / SHA | File:line | Owning PR or area | Ledger |
| --- | --- | --- | --- | --- | --- |
| S06-01 | P1 | integration `2722dcb7497d` | `Sources/Zeus/Dictation/DictationController.swift:581-593`; `Sources/Zeus/TopBar/TopBarViews.swift:1663-1674` | Dictation | new |
| S06-02 | P1 | #83 `e4ea25d8fda6` | `Sources/Zeus/Settings/GlanceSettingsPages.swift:1173` and `:1322-1325`; `Sources/Zeus/Calendar/LocalCalendarReader.swift:19-24`; `Sources/ZeusCore/App/PermissionDesk.swift:75-84` | #83 settings permissions | new |
| S06-03 | P1 | #53 `16c2d697dcd4` | `Sources/Zeus/Voice/Speaker.swift:146` and `:151` | #53 voice providers | new; the stuck counter is duplicate of ZB-027 |
| S06-04 | P1 | integration `2722dcb7497d` | `Sources/Zeus/Voice/Speaker.swift:375-378` | Voice | new |
| S06-05 | P1 | integration `2722dcb7497d` | `Sources/Zeus/Voice/Speaker.swift:389-401` and `:430-435`; `Sources/Zeus/Voice/OpenAITTSVoice.swift:31`; the batched cloud request uses the existing 20 s timeout | Voice | new; do not change the 20 s timeout |
| S06-06 | P1 | integration `2722dcb7497d` | `Sources/Zeus/Voice/KokoroWorkerSession.swift:68` and `:103` and `:370-372`; `Sources/Zeus/Voice/Speaker.swift:447-454` | Local voice worker | new |
| S06-07 | P1 | integration `2722dcb7497d` | `Sources/Zeus/Chat/ChatModel.swift:257` and `:269` and `:275` | Chat | new |
| S06-08 | P1 | integration `2722dcb7497d` | `Sources/Zeus/App/VoiceTurnController.swift:834`; contrast `:723` | Memory | new |
| S06-09 | P1 | #31 `d328f83ded8c` | `Sources/ZeusCore/NativeMessageIO.swift:148-158` | #31 native host EOF | new |
| S06-10 | P2 | #83 `e4ea25d8fda6` | `Sources/Zeus/Settings/GlanceSettingsPages.swift:1306-1311` | #83 settings permissions | new |
| S06-11 | P2 | integration `2722dcb7497d` | `Sources/ZeusCore/Learn/LearnedShortcuts.swift:86-97` and `:193-197` | Shortcuts | new |
| S06-12 | P2 | integration `2722dcb7497d` | `Sources/ZeusCore/Mac/NamedAgents.swift:81-94`; `Sources/Zeus/App/VoiceTurnController.swift:808-810` | Named agents | new |
| S06-13 | P2 | integration `2722dcb7497d` | `Sources/ZeusCore/Hands/HandsGate.swift:282-294` | Hands log | new |
| S06-14 | P2 | integration `2722dcb7497d` | `Sources/Zeus/TopBar/TopBarServices.swift:392-407` and `:427-431` | Weather | new |
| S06-15 | P2 | integration `2722dcb7497d` | `Sources/Zeus/Pointing/PointingProviders.swift:87-91` | Pointing speech | new; do not change the 20 s request timeout |
| S06-16 | P2 | integration `2722dcb7497d` | `Sources/Zeus/Brain/Providers/ClaudeCLIProvider.swift:301-305` | Brain CLI | new |
| S06-17 | P2 | integration `2722dcb7497d` | `Sources/Zeus/Voice/KokoroWorker.swift:110-116` | Local voice setup | new |
| S06-18 | P2 | integration `2722dcb7497d` | `Sources/Zeus/App/LicenseManager.swift:163-183` | License | duplicate of ZB-024; fix is on #58 |
| S06-19 | P2 | integration `2722dcb7497d` | `Sources/ZeusCore/License/LicenseEngine.swift:69-72` | License | duplicate of ZB-025; fix is on #58 |
| S06-20 | P1 | #53 `16c2d697dcd4` | `Sources/ZeusCore/Providers/ProviderPlaybackGate.swift:20-39` | #53 voice providers | duplicate of ZB-027 |

### S06-01 — Dictation refusal has no recovery control

Severity: P1. Area: dictation.

`begin` treats every microphone status other than authorized as a hard stop. It does not ask, and it does not open the privacy pane. The notch cue is `.dictation(String)`. That case is drawn as plain text (`TopBarViews.swift:1663`). The cue that carries an Open button is `.permission` (`:1665-1674`), which the talk key uses.

Sketch: set microphone status to denied (and, separately, to not-yet-asked). Press the dictation key. Expect a cue whose only action opens the microphone privacy pane, or a system prompt when the status is still not asked. Observe a one-line cue and no prompt. Speech recognition denied while a local engine is selected still starts, because the guard is only `microphoneAllowed`. Speech denied with no local engine shows the same text cue.

### S06-02 — A denied calendar no longer opens Settings

Severity: P1. Area: #83, calendar reader shared with #77.

On integration, `PermissionsModel.request(.calendar)` opens the privacy pane when the status is already decided (`PermissionsModel.swift:239-241`). #83 replaces the calendar row's action with `deskAllow` (`GlanceSettingsPages.swift:1173`). For calendar, `deskAllow` only calls `LocalCalendarReader.ensureAccess` (`:1322-1325`). That function returns immediately when the status is denied or restricted (`LocalCalendarReader.swift:21`) and swallows a thrown request with `try?` (`:22`). `PermissionDesk.can` still labels the button Allow whenever the row is allowed to prompt (`PermissionDesk.swift:81-83`), including after a denial.

Sketch: deny calendar access, open Settings, press the calendar row and the desk's Allow button. Expect the privacy pane. Observe `ensureAccess` returning `.denied` and no pane. The same tap while the status is not asked does prompt; the bug is the denied and restricted path.

### S06-03 — The sentence pump waits forever for a provider clip

Severity: P1. Area: #53. The counter bug that leaves `depth` stuck is duplicate of ZB-027. This row is the missing deadline around the wait.

`speak(sentenceStream:)` loops while `ProviderPlaybackGate.shared.isPlaying` with only `Task.isCancelled` as an exit (`Speaker.swift:146`). The queued pump does the same through `ProviderSentencePump.holds` (`:151`). `playWithEngine` ends the gate from the file's completion callback. If that callback never runs (the player dies, or ZB-027 ignores `end` for an older token), the next sentence never starts and the Mac voice is never reached.

Sketch: `begin()` a gate token, do not call `end`, then `speak` a second sentence with the cloud provider selected. The test's wait should hit a deadline and fall through to the local voice. Today the wait has no deadline.

### S06-04 — A cut-off cloud sentence is treated as spoken

Severity: P1. Area: voice, integration.

`streamElevenLabs` on a transport error calls `feeder.finish()` when the task was not cancelled, then returns success if any audio was already scheduled (`Speaker.swift:375-378`). `speakLine` then returns that engine and does not walk the rest of the chain, so the local voice and the Mac voice never say the rest of the sentence.

Sketch: feed one PCM chunk, then fail the byte stream with a connection-lost error. Expect `speakLine` to return nil for that engine, or to hand the unheard remainder to the next engine. Observe a non-nil result and no second engine.

### S06-05 — Cloud header waits block the Mac voice

Severity: P1. Area: voice, integration. The existing 20 s request timeout on the batched cloud route stays as it is. The direct cloud request built in `OpenAITTSVoice.streamingRequest` uses 15 s (`OpenAITTSVoice.swift:31`). Do not edit those numbers in a fix for this row.

The direct cloud route cancels its task at the first-audio deadline. The other two cloud routes do not. `speakOpenAI` checks the deadline only after bytes have started (`Speaker.swift:398-400`). `speakGemini` awaits `data(for:)` for the whole 20 s request (`:430-435`) before returning nil. Until that return, `speakLine` does not try the local voice or the Mac voice.

Sketch: select the non-streaming cloud route, and make the transport accept the connection and send no body. Expect the Mac voice to start at the first-audio deadline (4 s in `VoiceTTSChain.firstAudioTimeout`). Observe silence until the existing request timeout fires. A fix adds that deadline around the wait and leaves the 15 s and 20 s request timeouts in place.

### S06-06 — A hung local worker blocks speech, and a stuck child disables it

Severity: P1. Area: local voice worker, integration.

`KokoroWorkerSession.render` waits up to `requestTimeout` (120 s, `:68`) for one line. `speakKokoro` checks the first-audio budget only after that wait returns (`Speaker.swift:447-454`), and it allows an extra 30 s. A worker that stays alive and writes nothing holds the sentence for two minutes before the Mac voice.

If `finishChild` cannot observe exit after terminate and a kill (`KokoroWorkerSession.swift:389-406`), `finishedClosing` sets `closed = true` (`:370-372`). Later `render` calls return nil at `:103` for the rest of the process. The Mac voice still runs, but the local voice does not come back when the old child finally disappears.

Sketch: install a worker double that accepts stdin and never prints a line. Time `speakLine`. Expect the Mac voice inside the first-audio budget, not after 120 s. Second sketch: make `finishChild` return false. The next `render` must be allowed to start a new worker once the old pid is gone. Observe `closed == true` and a permanent nil.

### S06-07 — A full disk drops the chat with no retry

Severity: P1. Area: chat, integration.

`upsert` and `recordExchange` ignore `store.save` (`ChatModel.swift:257`, `:269`, `:275`). The in-memory transcript updates. A failed visual-link save is remembered (`:114-116`); these three are not. Scribe shows the error and retries. Chat does not. Quit loses the turn.

Sketch: point `ChatStore` at a volume that returns a no-space error. Send one message. Expect the row to stay failed and a later retry to call `save` again. Observe a normal row and no second save. Same for `recordExchange`.

### S06-08 — A damaged memory file is spoken as if it were empty

Severity: P1. Area: memory, integration. This does not trap at launch. It drops the file's contents on the next turn.

`handleMemory` uses `loadChecked` and tells the person the file was left alone (`VoiceTurnController.swift:723-760`). The brain prompt uses `load()` (`:834`), which is `(try? loadChecked()) ?? UserMemoryStore()`. A truncated or undecodable `user-memory.json` becomes an empty prompt. The file stays on disk, and `save` still refuses to replace it, so the damage is invisible until someone says "remember".

Sketch: write a zero-byte `user-memory.json` (the persistence layer already treats that as truncated). Run a turn that is not a memory command. Expect the spoken answer to say the memory file could not be read, and expect the prompt to contain no memory block. Observe a normal prompt with an empty block.

### S06-09 — Closing the browser helper's input drops the write deadline

Severity: P1. Area: #31 native host.

`finish` is documented as flushing frames that were already accepted, while a peer that can still read keeps the enqueue deadline so a stuck pipe cannot wait forever. `write` skips that deadline whenever `finishing` is true (`NativeMessageIO.swift:158`). After stdin EOF, a pipe that stops reading and does not surface an error keeps `poll` in the 25 ms loop with no timeout. The output queue is then stuck, and later frames are rejected as closed only after something else sets `terminal`.

Sketch: enqueue one frame, call `finish`, and make the write end return `EAGAIN` forever without `POLLERR` or `POLLHUP`. Expect `Failure.timedOut` at the deadline captured in `enqueue`. Observe the write loop still running after that deadline.

### S06-10 — Denied microphone, speech, camera, and screen look unasked

Severity: P2. Area: #83.

`deskStatus` maps those four to `.allowed` or `.unknown` (`GlanceSettingsPages.swift:1306-1311`). `.denied` is never stored, except for calendar. `PermissionDesk.can` then says "Not asked" and, for a row that can prompt, "Allow". A denied microphone still reaches `VoicePermissions.ensure`, which can raise the notch cue, so this row is the wrong status, not a missing cue. Screen and accessibility still call `request`, which opens the pane when the system status is denied. The desk itself cannot tell a refusal from a first visit, so "Grant everything" (`:1342`) will ask again for rows the person already refused.

Sketch: deny microphone and screen, build `deskStatus`. Expect `.denied` and a button that opens the pane. Observe `.unknown`, the copy "Not asked", and Allow on the microphone row.

### S06-11 — Shortcut saves are not atomic, and a failed write still counts as saved

Severity: P2. Area: shortcuts, integration.

`LearnedShortcutStore.write` uses `Data.write(to:)` with no `.atomic` (`LearnedShortcuts.swift:93-97`). `LearnedShortcutDisk.save` returns `.saved` after `try? store.write` (`:197`), so a full disk or a mid-write crash still looks saved. `load` returns an empty book when the file will not decode (`:86-90`). The next successful save replaces the damaged file with that empty book.

Sketch: stub `write` to throw after creating a partial file. `save` should return a failure and leave the previous file intact. Observe `.saved`, and a following `load` of the partial bytes returning an empty store.

### S06-12 — A damaged agent memory is replaced by the next note

Severity: P2. Area: named agents, integration.

`AgentStore.memory` returns an empty value when the file will not decode (`NamedAgents.swift:81-85`). `save` then writes that value atomically over the file (`:89-94`). A "remember" turn does both (`VoiceTurnController.swift:808-810`) and ignores a thrown save with `try?`. One corrupt file plus one new note deletes the old notes. User memory refuses that overwrite; agent memory does not.

Sketch: put `{` in `<agent>.memory.json`, then `remember` one note and `save`. Expect the original bytes kept beside the file and an error spoken back. Observe a one-note file.

### S06-13 — The hands log swallows a short write

Severity: P2. Area: hands, integration.

`HandsCommandLogger.append` uses `try?` for the directory, the seek, and the write (`HandsGate.swift:282-294`). A new file is `Data.write` with no atomic replace. A crash between creating the file and finishing the bytes leaves a torn line, and a full disk leaves no line and no error. The log is the record of what was allowed to run.

Sketch: fill the volume, call `append`, then read the file. Expect a thrown error or a recorded failure. Observe a silent return and an unchanged file.

### S06-14 — One weather failure suppresses the next refresh, and the URL is force-unwrapped

Severity: P2. Area: weather, integration.

`fetchWeather` stores `lastWeatherFetch` before the request (`TopBarServices.swift:393-394`). The failure path only sets `weatherError` (`:407`). The next automatic fetch waits 20 minutes, including after the network returns. `geocode` force-unwraps `parts.url` (`:431`). `URLComponents.url` is optional; a city that cannot form a URL traps the unstructured task instead of setting `weatherError`. `URLSession.shared` is used with no timeout of its own (`:400` and `:431`).

Sketch: fail the first geocode, advance the clock five minutes, call `fetchWeather(force: false)`. Expect a second attempt. Observe an early return. Second sketch: a city for which `URLComponents.url` is nil. Expect `weatherError`. Observe a trap on `parts.url!`.

### S06-15 — Pointing speech can run far past its request timeout

Severity: P2. Area: pointing, integration. Do not change the 20 s request timeout on the speech requests (`PointingProviders.swift:315` and `:405`).

`PointingHTTP.configuration` sets `timeoutIntervalForRequest` to the caller's timeout and `timeoutIntervalForResource` to `max(timeout, 180)` (`:91`). A body that trickles bytes keeps the request timeout from firing. The resource cap is three minutes. `PointingSpeechRouter` falls back to the Mac voice only after that wait throws.

Sketch: return a 200 and one byte every 10 s. Expect the Mac voice at the first-audio budget, with the 20 s request timeout unchanged. Observe the vendor call still running until the 180 s resource cap.

### S06-16 — A failed prompt write is discarded

Severity: P2. Area: brain CLI, integration.

`StdinFeeder.feed` is `do { try handle.write } catch {}` (`ClaudeCLIProvider.swift:304`). The comment says a broken pipe is reported by the process exit. A full disk or a short write that does not kill the process is not. The turn then waits on the CLI's own silent timeout before any fallback engine.

Sketch: a pipe whose `write` throws `ENOSPC` while the process stays alive. Expect the turn to fail at once and move to the next engine. Observe an empty catch and no error on the stream until the CLI's own timeout.

### S06-17 — The local model download has no overall timeout

Severity: P2. Area: local voice setup, integration.

`KokoroWorker.downloadModelFiles` uses `URLSession.shared.download` (`KokoroWorker.swift:110`) for files that must be at least 100 MB and 5 MB. There is no `timeoutIntervalForResource` on that call. A stalled transfer sits on the shared session's defaults. A short file is rejected after the download returns (`:114`); a transfer that never returns does not.

Sketch: a download double that accepts and sends nothing. Expect a failure string within a bounded resource timeout, and no partial file left as the model. Observe the call still awaiting `download`.

### S06-18 — duplicate of ZB-024

Severity: P2. Area: license, integration `2722dcb7497d`, `LicenseManager.swift:163-183`.

Activation still writes `license.activation` before `license.key`. A failed key write leaves the proof. #58 (`10faecc83b32849db0a712f69e807c9317d51a96`) moves that pair behind `LicenseCredentialCommit.store`. The integration row stays until that head lands. No new cluster here.

### S06-19 — duplicate of ZB-025

Severity: P2. Area: license, integration `2722dcb7497d`, `LicenseEngine.swift:69-72`.

`isRevoked` returns false when the stored list is missing or will not decode. #58 keeps the last signed id list and consults it when the current list does not decode. The integration row stays until that head lands. No new cluster here.

### S06-20 — duplicate of ZB-027

Severity: P1. Area: #53 `16c2d697dcd4`, `ProviderPlaybackGate.swift:20-39`.

`end` returns without decrementing unless `token == generation`, and every `begin` bumps `generation`. Overlapping clips leave `isPlaying` true. S06-03 is the wait that then never ends. The ledger already owns the counter. No second fix cluster for the gate file.

## Counts

| Severity | New | Duplicate of the ledger | Total |
| --- | ---: | ---: | ---: |
| P0 | 0 | 0 | 0 |
| P1 | 9 | 1 (ZB-027) | 10 |
| P2 | 8 | 2 (ZB-024, ZB-025) | 10 |
| P3 | 0 | 0 | 0 |
| Total | 17 | 3 | 20 |

## Fix clusters

New rows only. Each cluster is file-disjoint from the others, so each can land as its own change. Duplicates stay on the PRs named in the ledger (#58 for ZB-024 and ZB-025, #53 for ZB-027).

| Cluster | IDs | Files | Base |
| --- | --- | --- | --- |
| Dictation denial | S06-01 | `Sources/Zeus/Dictation/DictationController.swift`, `Sources/Zeus/TopBar/TopBarViews.swift` | integration `2722dcb7497d` |
| Permission desk | S06-02, S06-10 | `Sources/Zeus/Settings/GlanceSettingsPages.swift`, `Sources/ZeusCore/App/PermissionDesk.swift`, `Sources/Zeus/Calendar/LocalCalendarReader.swift` | #83 `e4ea25d8fda6` |
| Speech fallback | S06-03, S06-04, S06-05, and the post-return check in S06-06 | `Sources/Zeus/Voice/Speaker.swift` | #53 `16c2d697dcd4` for the wait; integration `2722dcb7497d` for the cut-off sentence, the header wait, and `speakKokoro`'s check after the worker returns. Leave the existing 15 s and 20 s request timeouts. |
| Local worker lifetime | S06-06, S06-17 | `Sources/Zeus/Voice/KokoroWorkerSession.swift`, `Sources/Zeus/Voice/KokoroWorker.swift` | integration `2722dcb7497d`. The 120 s wait and the permanent `closed` flag. Not `Speaker.swift`. |
| Chat save | S06-07 | `Sources/Zeus/Chat/ChatModel.swift` | integration `2722dcb7497d` |
| Memory files | S06-08, S06-12 | `Sources/Zeus/App/VoiceTurnController.swift`, `Sources/ZeusCore/Mac/NamedAgents.swift` | integration `2722dcb7497d` |
| Shortcut file | S06-11 | `Sources/ZeusCore/Learn/LearnedShortcuts.swift` | integration `2722dcb7497d` |
| Hands log | S06-13 | `Sources/ZeusCore/Hands/HandsGate.swift` | integration `2722dcb7497d` |
| Weather refresh | S06-14 | `Sources/Zeus/TopBar/TopBarServices.swift` | integration `2722dcb7497d` |
| Pointing speech cap | S06-15 | `Sources/Zeus/Pointing/PointingProviders.swift` | integration `2722dcb7497d`. Leave the 20 s request timeout. |
| Prompt write | S06-16 | `Sources/Zeus/Brain/Providers/ClaudeCLIProvider.swift` | integration `2722dcb7497d` |
| Browser helper flush | S06-09 | `Sources/ZeusCore/NativeMessageIO.swift` | #31 `d328f83ded8c` |

S06-06 is the only row split across two clusters, and those clusters do not share a file. S06-02 and S06-10 share the permission desk files, so they are one cluster. No other cluster repeats a file.
