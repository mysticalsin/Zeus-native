# Approval sync

Status: proposal. This document changes no Swift, no socket, and no port.
Audited commit: `2722dcb7497d5415fbc1fcb1f65c49629966a281` on the integration branch (2026-11-21).

A coding agent raises an approval through `zeus-hook`. Zeus shows it on the hub decision queue. The agent's terminal and the hub are one request. When either side answers, the other side dismisses in the same turn. Silence, a missing id, a stale id, a reconnect, and a timeout all end in deny. Nothing in this path approves by itself.

## Decision

The messages are JSON lines on the Unix socket `AgentEventServer` already serves (`ZeusPaths.socket`, default `Application Support/Zeus/zeus.sock`, override `ZEUS_SOCKET`). The server stays one `UnixSocketServer` in `AgentEventServer.start`. This spec adds no listener, no TCP port, no `NWListener`, and no second socket path. The browser helper socket (`ZeusPaths.chromeSocket`) and Fling stay as they are. Peer checks stay `PeerPolicy.sameUser`.

The queue this protocol drives is the one in [PR #70](https://github.com/mysticalsin/Zeus-native/pull/70) (`zeus-bot/hub-04-decision`, head `7c000d3a`). This spec does not replace that machine.

## What PR #70 already locks

`HubDecision` in `Sources/ZeusCore/AgentHub/HubDecision.swift` on that branch:

- A second approval waits behind the one that is showing. Approving the first reveals the second.
- `approve` on the showing request yields `allow`. `deny` and `timeout` yield `deny`. `ask` yields `ask` only when that request has `allowsAsk`, and `ask` is never rewritten to `allow`.
- A pair that is not in the table leaves the queue unchanged.
- An unbound request (empty id or empty session) is not shown and is not allowed.
- The same id raised again while it is showing or waiting leaves the queue unchanged.
- Trust is not an input. A trusted session does not skip the queue.
- The typed-reply gate is a separate machine. It can report that a reply needs approval. It does not, by itself, place that approval on the queue. This spec leaves the reply gate on that rule. Reply approvals are out of scope here.

`HubDecisionTests` already covers that table. The tests in this spec call `HubDecision` and then assert the sync wrapper. They do not copy those rows.

#70 is not merged on the audited branch. Until it is, the live app has a single `NotchModel.approval` and no `HubApprovalQueue`. The protocol below is written against `HubApprovalQueue`, `HubApprovalEvent`, and `HubApprovalVerdict`. Wiring it into `AgentEventServer` is a later change.

## Audit of the live path

`AgentEventServer` (`Sources/Zeus/Agents/AgentEventServer.swift`) accepts one connection at a time on that socket. `handle` runs `ZeusCommand` when the line is a command, and otherwise decodes a `HookEvent`.

`zeus-hook` (`Sources/zeus-hook/main.swift`) reads the agent's payload on stdin, normalizes it, and writes one `HookEvent` line. For a decision it waits up to 115 s (`UnixSocket.request`, `expectReply: true`). On a `HookDecision` it prints the agent's stdout object when `decision` is `allow` or `deny`. A verdict of `ask`, a missing reply, and a Zeus that is not running all print nothing and exit 0. The hook's own comment says it never allows on its own. An empty stdout hands the prompt back to the agent, which can then allow. That is fail-open.

`HookEvent.id` is a new UUID on every send (`HookEvent.init` default). The normalizer does not copy an id from the payload. `NotchController.requestApproval` then mints a second UUID for `NotchModel.Approval` (around line 318) and does not keep the hook id.

`PermissionRequest` (`AgentEventServer.process`, the branch around lines 96–140):

| Path | Result today |
| --- | --- |
| `HandsBlocklist` matches the command | Immediate `HookDecision` deny. No card. |
| `TrustedChatStore.autoApproves` | Immediate `HookDecision` allow. No card. |
| Otherwise | `notch.requestApproval` for 100 s with `onTimeout: .ask`. |
| Card timeout | Verdict `ask`. The card note is "then your terminal asks". |
| Cancelled wait | `.deny`. |
| Person taps Approve / Deny, or the answer keys, or a voice word | The card's `finish` runs once (`finished` guard). |

A second `requestApproval` spins until `model.approval` is nil (around lines 313–315). There is no id map, so a repeat of the same logical request is a second wait, and a second tap is ignored only inside one card.

`HookDecision` of `ask` produces no stdout object. `allow` and `deny` do.

Nothing stores a pending approval across a dropped socket, a Zeus relaunch, or a second hook process. `TrustedChatStore` is memory-only. There is no undo interval on this card.

The default parameter on `requestApproval` is `onTimeout: .deny` and 120 s. The agent path does not use that default. It passes 100 s and `.ask`.

## Gaps

| This spec requires | Live behavior |
| --- | --- |
| One stable id shared by the terminal and the hub | A new UUID in the hook, and another UUID on the card |
| An answer on one side dismisses the other in the same turn | The hook blocks, or it returns `ask` and the agent draws its own prompt with no later withdraw |
| A duplicate answer is idempotent | The card has a local `finished` flag and the socket has no id memory |
| A stale answer does not allow | An unknown line is ignored or starts another card |
| A reconnect restores the open request and replays a final verdict | A new hook run is a new id |
| Timeout ends in deny | 100 s ends in `ask`, and the hook may still wait until 115 s and then print nothing |
| Undo lasts 2 s and releases the tool only after that | No undo |
| Fail closed, never auto-approve | Trusted-chat allow, timeout `ask`, empty stdout |

## Protocol

Every line is one JSON object, UTF-8, ended by `\n`, on the existing connection. `AgentEventServer.handle` branches in this order: a `ZeusCommand` (`kind` `zeus.command`), a sync line (`kind` prefixed `decision.`), then a `HookEvent`. An unknown `kind`, a line that is not JSON, and a sync line with an empty id produce no allow.

The waiting hook connection stays open until Zeus writes exactly one final `HookDecision`. Sync lines may arrive before that final line. The hook reads in a loop. The 115 s transport cap stays, and it stays above the decision deadline plus the undo window (100 + 2).

### Raise

A permission is still a `HookEvent` with `event` `PermissionRequest` and `needsDecision` true. `zeus-hook` sets `id` to a stable value:

1. The first non-empty string among the payload fields `permission_request_id`, `tool_use_id`, and `toolUseID`, prefixed by the session and a colon.
2. Otherwise `session + ":" +` the first 32 hex characters of SHA-256 over the UTF-8 of `tool`, a NUL, and the canonical JSON of `input`.

An empty session, or an id that is empty after trimming, is unbound. The hook does not send the raise. It prints a deny object and exits 0. Zeus, if it ever sees an unbound raise, applies #70's rule: the queue is unchanged and the reply is deny.

`allowsAsk` is carried on the request and defaults to false. A source the normalizer today marks `needsDecision` false stays observe-only. This spec does not add a permission event to those sources.

On a bound raise Zeus calls `HubDecision.approval(queue, .request, request)`. The hook is told `decision.shown` when that id is the showing row. A duplicate id leaves the queue unchanged and is answered with `decision.reject` / `duplicate`. No second card. No allow.

### Answers

```json
{"v":2,"kind":"decision.answer","id":"<id>","decision":"allow","source":"hub"}
```

`decision` is `allow` or `deny`. `source` is `hub` or `terminal`. `ask` is not a value of this message.

A hub Approve on the showing id is `HubDecision.approval(queue, .approve)`. A hub Deny is `.deny`. A terminal answer is a second connection, or a later line on the waiting connection, whose payload normalizes to event `PermissionResolved` with the same stable id and a verdict of allow or deny. `AgentEventServer` turns that event into `decision.answer` with `source` `terminal`.

The first verdict for an id wins. Zeus applies it only when `queue.showing?.id` is that id. In that same turn Zeus:

- clears the showing row (the queued row behind it is revealed by #70's existing rule)
- moves the id into the undo window
- sends `decision.dismiss` with reason `answered` to every connection subscribed to that id
- sends `decision.undoWindow` to those connections

The waiting hook does not print stdout yet. The tool has not run. The terminal prompt for that id is cleared by `decision.dismiss` in the same turn the hub card clears. A connection that cannot draw a prompt still records the dismiss so a later `decision.hello` does not reopen a finished prompt.

A queued id is not decided by an answer. The answer is `decision.reject` / `stale` if it is not the showing id and not already final. The queue is unchanged. The verdict is not allow.

### Undo

The window is 2.0 s, measured from the `until` timestamp Zeus sends in `decision.undoWindow` (Unix seconds, the answer time plus 2). Both sides show the verdict and an Undo control until `until`.

```json
{"v":2,"kind":"decision.undo","id":"<id>","source":"hub"}
```

An undo that arrives with `now < until` returns the id to showing, sends `decision.restore`, and drops the pending verdict. The tool has not run. The terminal prompt comes back in that same turn. A second undo, and an undo at or after `until`, are `decision.reject` / `late`. The verdict that won stays.

When `until` passes with no undo, Zeus writes one `HookDecision` (`allow` or `deny`, the winning verdict, the hook id) and then `decision.dismiss` with reason `undoClosed`. The hook prints that one object and exits. A later `decision.answer` for the id is stale.

Timeout deny and blocklist deny do not open an undo window. They are final in the turn that produces them.

### Timeout

Each request's deadline is 100 s after it becomes the showing row. Time spent queued does not consume that 100 s. At the deadline, if the id is still showing and not inside an undo window, Zeus calls `HubDecision.approval(queue, .timeout)`, which yields `deny`. The card note is "then it's denied". Zeus writes `HookDecision` deny and `decision.dismiss` reason `timeout` in that turn. There is no undo.

If the hook's 115 s cap fires first, the hook prints deny, sends `decision.answer` deny on a new connection if it still can, and exits. Zeus applies that deny if the id is still showing. If Zeus later sends allow, the allow is `opposite` or `stale` and the recorded deny stands.

A queued id whose showing predecessor is still open keeps waiting. It is not allowed by the predecessor's timeout.

### Stale

An answer, an undo, or a dismiss for an id Zeus does not know is `decision.reject` / `stale` and is not an allow.

An answer for an id that is already `final` returns the standing verdict in a `decision.snapshot` item and does not change it. A second raise of a final id returns that verdict and does not enqueue.

An answer whose `decision` differs from the verdict already in the undo window or in the final log is `decision.reject` / `opposite`. The first verdict stands. The late side dismisses to that verdict.

### Reconnect

A hook that connects again sends:

```json
{"v":2,"kind":"decision.hello","open":["<id>"]}
```

Zeus answers `decision.snapshot`. Each item is `open`, `undo`, `final`, or `unknown`.

| Zeus has | Hello lists it | Result |
| --- | --- | --- |
| `open` | yes | The same card stays. Remaining time is what is left of the 100 s. No second card. No allow. |
| `undo` | yes | The undo strip stays, with `remainingMs`. |
| `final` | yes or no | The standing verdict is replayed. The terminal dismisses. A final deny is not promoted to allow. |
| nothing | yes | The id is raised again as `open`. It is shown. It is not allowed. |
| `open` | no | The terminal is gone. Zeus denies in that turn, dismisses, and records `final` deny. |

A Zeus relaunch has an empty log. Every id in `hello` is `unknown` and is shown again. None of them is allowed. Final verdicts live in the process that decided them. This spec does not add a disk store. A decision that did not reach `final` before the process exited is asked again.

### Fail closed

These are denies, or they leave the queue unchanged. None of them is an allow.

| Situation | Result |
| --- | --- |
| Zeus is not running, the socket is missing, or the 115 s cap fires | The hook prints deny. Stdout is not empty. |
| The line is not JSON, the kind is unknown, or the id is unbound | Deny when the connection was waiting on a decision. Otherwise no reply and no allow. |
| Trusted-chat flag is set for the session | Ignored. The card still shows. #70 does not take trust as an input. |
| `HandsBlocklist` matches | Immediate final deny. No card. No undo. |
| Timeout | Final deny. |
| `ask` when `allowsAsk` is false | Queue unchanged (#70). No allow. |
| `ask` when `allowsAsk` is true | The hub dismisses and the one `HookDecision` is `ask`. The hook prints no allow object. `ask` is not rewritten to `allow`. This is a person's choice on a request that allows it, and it is not the timeout. |
| Duplicate raise | Queue unchanged. Reject `duplicate`. |
| Opposite answer | First verdict stands. |
| Undo | Restores the open request. The tool stays unreleased. |

`AgentEventServer` stops calling `TrustedChatStore.autoApproves` on this path. The blocklist deny stays in front of the queue.

## Sync machine

`DecisionSync` in `Sources/ZeusCore/AgentHub/DecisionSync.swift`. Pure. It holds the `HubApprovalQueue`, a map of sync rows, and the clock the caller passes in. It calls `HubDecision.approval` for queue changes and does not reimplement that table.

| Row state | Meaning |
| --- | --- |
| `open(showingSince)` | In the queue, waiting on a person. |
| `undo(verdict, until)` | Verdict chosen, tool unreleased, `until` is 2 s after the answer. |
| `final(verdict)` | `HookDecision` already released, or a blocklist or timeout deny. |

Events: `raise`, `answer(verdict, source, now)`, `undo(source, now)`, `timeout(now)`, `hello(openIDs, now)`, `tick(now)`.

Effects: `enqueue`, `dismiss(id, reason)`, `undoWindow(id, verdict, until)`, `restore(id)`, `release(HookDecision)`, `reject(id, cause)`, `snapshot(items)`.

`release` is the only effect that carries `allow`, and only from an `undo` row whose `until` has passed, or never for a row that went `open` → `final` by timeout or blocklist without an `allow` verdict. A test can see every `release` and its verdict.

## Messages

| `kind` | Direction | When |
| --- | --- | --- |
| `HookEvent` `PermissionRequest` | hook → Zeus | Raise. |
| `decision.shown` | Zeus → hook | That id is the showing row. |
| `decision.answer` | either way | A person chose allow or deny. |
| `decision.dismiss` | both ways | The other surface drops the prompt now. Reasons: `answered`, `timeout`, `stale`, `undoClosed`, `blocked`. |
| `decision.undoWindow` | Zeus → hook | Verdict is held for 2 s. |
| `decision.undo` | either way | Person undoes inside the window. |
| `decision.restore` | Zeus → hook | Prompt and card come back. Tool still unreleased. |
| `decision.hello` | hook → Zeus | Reconnect. `open` is the ids the terminal still shows. |
| `decision.snapshot` | Zeus → hook | One item per id: `state`, optional `decision`, `remainingMs`. |
| `decision.reject` | Zeus → hook | `duplicate`, `stale`, `opposite`, `unbound`, `late`. |
| `HookDecision` | Zeus → waiting hook | The one final line. Then the hook prints and exits. |
| `PermissionResolved` | hook → Zeus | A terminal answer after the agent reports one. Same stable id. Normalized into `decision.answer`. |

`v` is `2` on every `decision.*` line. A `decision.*` line with any other `v` is rejected and is not an allow.

## Test plan

Red first, in the style of #70. The first implementation commit adds `Tests/ZeusCoreTests/AgentHub/DecisionSyncTests.swift` and does not add `DecisionSync.swift`. `swift test --filter DecisionSyncTests` fails to compile, because `DecisionSync` is missing. The next commit adds the type. The filter then passes. `HubDecisionTests` is not edited.

The suite builds a `HubApprovalQueue` through `HubDecision` and feeds `DecisionSync`. The clock is an argument. No sleep.

| Test | Asserts |
| --- | --- |
| `aRaiseShowsOneCard` | `showing.id` is the stable id. Effect `decision.shown`. No `release`. |
| `aSecondRaiseOfTheSameIdDoesNothing` | Queue equals the queue #70 returns for a duplicate. Reject `duplicate`. No `release`. |
| `aHubAllowDismissesTheTerminalInThatTurn` | Effects include `dismiss` reason `answered` and `undoWindow`. No `release` yet. |
| `aTerminalDenyDismissesTheCardInThatTurn` | `showing` is nil. The row is `undo` deny. |
| `theSameVerdictTwiceIsIdempotent` | State unchanged. Reject `duplicate`. One verdict. |
| `theOppositeVerdictKeepsTheFirst` | Reject `opposite`. The first verdict is the only one in the row. |
| `aStaleIdIsNotAllowed` | Reject `stale`. Queue unchanged. No `release` of allow. |
| `anAnswerForAQueuedIdDoesNotDecideIt` | The queued id stays queued. No `release`. |
| `anUnboundRaiseIsDenied` | Queue unchanged. `release` deny, or the hook-side twin that prints deny without a send. |
| `undoAtOneSecondRestoresBothSides` | `restore`. Row is `open`. No `release`. |
| `undoAtTwoSecondsIsLate` | Reject `late`. `tick` at `until` emits one `release` of the original verdict. |
| `timeoutAtOneHundredSecondsDenies` | `HubDecision` verdict `deny`. Row `final` deny. Dismiss reason `timeout`. No undo window. |
| `timeoutDoesNotAsk` | The released `HookDecision.decision` is `deny`. |
| `aTrustedFlagStillShowsTheCard` | Raise with the trust flag set. Status `showing`. No allow. |
| `aBlocklistDenyIsFinal` | `final` deny. No undo. No card. |
| `askIsNotAnAllow` | With `allowsAsk` true, the released verdict is `ask` and no effect carries `allow`. With `allowsAsk` false, the queue is unchanged. |
| `helloOfAnOpenIdDoesNotDuplicate` | One showing row. Snapshot `open`. |
| `helloOfAFinalDenyReplaysDeny` | Snapshot `final` / `deny`. No enqueue. |
| `helloOfAnUnknownIdShowsAndDoesNotAllow` | New `open` row. No `release`. |
| `anOpenIdMissingFromHelloIsDenied` | `final` deny. Dismiss reason `stale`. |
| `aRelaunchShowsHelloIdsAgain` | Empty sync value plus `hello` yields `open`, not `final` allow. |
| `theHookPrintsDenyWhenTheSocketIsMissing` | Hook-side function, no server. Stdout is a deny object. It is not empty and it is not allow. |
| `theTransportCapCoversTheDeadlineAndTheUndo` | `115 >= 100 + 2`. |
| `oneServerPath` | The only socket path `AgentEventServer` is specified to open is `ZeusPaths.socket.path`. |

The socket tests that need a live `UnixSocketServer` use a temporary path in `ZEUS_SOCKET`. They bind that path and no other. They are the last commit of the implementation, after the pure suite is green, and they are out of scope for this document.

## Acceptance

- An allow exists only as a `HookDecision` released after a person's Approve survived the 2 s window, for the id that was showing.
- A deny from the person, from the timeout, from the blocklist, from a dead socket, or from a terminal that went away is the verdict the other side shows, and it shows in the turn the verdict is chosen.
- Duplicate, opposite, stale, unbound, and late inputs leave an allow that already happened as it was, and they never create one.
- `AgentEventServer` still listens once, on `ZeusPaths.socket`.
- This document's merge adds the contract and leaves the server, the hook, and the queue untouched.
