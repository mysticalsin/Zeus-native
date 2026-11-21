# Chat and agent hub, build plan

This plan is the build that follows `inventory.md` and `target.md`. It does not include product code. A later PR that implements a row from this plan is the first time `Sources/` or `Tests/` change for this work.

Constraints for every PR in the plan:

- No new window. The floating chat window stays in the tree because existing tests construct it. The hub stops opening it.
- No edit to `Package.swift`, CI, or the toolchain.
- New Swift files live in directories the existing targets already compile. `ZeusCoreTests` and the app target include their trees without a package edit.
- No secrets, tokens, or live home-directory paths in tests. Tests use a temporary directory.
- No external product name in new copy, comments, or test names.
- The closed bar, the tab row, and the existing springs are not restyled.
- Each PR owns the files in its row and no other file. Two PRs that need the same existing file are one PR.

## Shape

Four layers. Each layer is a type the next one can call. A view never reads a socket. A socket never draws.

| Layer | Owns | Must not |
| --- | --- | --- |
| Vocabulary | The status, cause, screen, and event enums. | Behavior, views, or existing files. |
| Machines | The transition tables in `target.md`, as pure functions. | AppKit, SwiftUI, sockets, sound playback. |
| Views | Rows, transcript, and the inline decision, using the existing button, type, and markdown views. | Knowing how a hook arrives. |
| Wiring | One existing file each, calling the machines and the views. | A second existing file. |

The machines are written so a test can feed `(state, event)` and read the next state. The tables in `target.md` are the oracle. A pair missing from the table is a failed test if the function changes state anyway.

## Order

PR 1 merges first. After it, PRs 2 through 10 compile against PR 1 only and are file-disjoint, so they can proceed together and merge in any order. PRs 11 through 15 wait for the machines and views they call. They are also file-disjoint with each other and can proceed together once those dependencies are in. PR 16 is last and only checks that the set still builds. It owns no product file.

No PR stacks on another PR's branch. Each one targets the integration branch this spec is based on, after PR 1 is in that branch. Until PR 1 is in, the later PRs are specified, not opened.

## PR breakdown

| PR | Branch | Owns these files and no others | Depends on |
| --- | --- | --- | --- |
| 1 Vocabulary | `zeus-bot/hub-01-types` | `Sources/ZeusCore/AgentHub/HubTypes.swift`, `Tests/ZeusCoreTests/AgentHub/HubTypesTests.swift` | none |
| 2 Session machine | `zeus-bot/hub-02-session` | `Sources/ZeusCore/AgentHub/SessionMachine.swift`, `Tests/ZeusCoreTests/AgentHub/SessionMachineTests.swift` | 1 |
| 3 Transcript | `zeus-bot/hub-03-transcript` | `Sources/ZeusCore/AgentHub/HubTranscript.swift`, `Tests/ZeusCoreTests/AgentHub/HubTranscriptTests.swift` | 1 |
| 4 Decision and reply | `zeus-bot/hub-04-decision` | `Sources/ZeusCore/AgentHub/HubDecision.swift`, `Tests/ZeusCoreTests/AgentHub/HubDecisionTests.swift` | 1 |
| 5 Screen and groups | `zeus-bot/hub-05-screen` | `Sources/ZeusCore/AgentHub/HubScreen.swift`, `Tests/ZeusCoreTests/AgentHub/HubScreenTests.swift` | 1 |
| 6 Sound opt-in | `zeus-bot/hub-06-sound` | `Sources/ZeusCore/AgentHub/HubSound.swift`, `Tests/ZeusCoreTests/AgentHub/HubSoundTests.swift` | 1 |
| 7 Experience contract | `zeus-bot/hub-07-experience` | `Sources/ZeusCore/AgentHub/HubExperience.swift`, `Tests/ZeusCoreTests/AgentHub/HubExperienceTests.swift` | 1 |
| 8 Session list view | `zeus-bot/hub-08-list` | `Sources/Zeus/Agents/Hub/SessionListView.swift` | 1 |
| 9 Transcript view | `zeus-bot/hub-09-transcript-view` | `Sources/Zeus/Agents/Hub/HubTranscriptView.swift` | 1 |
| 10 Decision row | `zeus-bot/hub-10-decision-view` | `Sources/Zeus/Agents/Hub/HubDecisionRow.swift` | 1 |
| 11 Agents page | `zeus-bot/hub-11-agents-page` | `Sources/Zeus/Notch/NotchView.swift` | 2, 5, 8, 9, 10 |
| 12 Chat in the bar | `zeus-bot/hub-12-chat-page` | `Sources/Zeus/TopBar/ChatPage.swift` | 3, 9 |
| 13 Hook adapter | `zeus-bot/hub-13-events` | `Sources/Zeus/Agents/AgentEventServer.swift` | 2, 6 |
| 14 Bar entry and chimes | `zeus-bot/hub-14-entry` | `Sources/Zeus/App/AppDelegate.swift` | 3, 6 |
| 15 Reply gate | `zeus-bot/hub-15-reply` | `Sources/Zeus/Agents/AgentHub.swift` | 4 |
| 16 Bound suites | `zeus-bot/hub-16-bind` | `qa/feature-map.json`, `qa/regressions.json` | 2–7, and the wiring PRs that add a regression |

PRs 8, 9, and 10 take plain values from PR 1 (name, status word, elapsed text, lines). They do not import PRs 2 through 7, so they do not wait for those machines. PR 11 is the one that passes machine output into the views.

Owning a large existing file means that PR is the only one allowed to edit it, not that the file is rewritten. PR 11 changes the Agents page and the height that page adds. PR 12 changes the Chat page's list, transcript, and composer. PR 13 changes event handling and removes the extra finish sound. PR 14 changes the chat shortcut, where `openWindow` points, and the chime call. PR 15 changes the reply gate. None of them restyle the closed shape, the tab row, or an unrelated page.

Files that must not be edited by any of these PRs: `Package.swift`, anything under `.github/`, `Sources/Zeus/Chat/ChatWindow.swift`, `Sources/Zeus/Chat/ChatModel.swift`. The window and the model stay. PR 12 stops sending the person there. PR 14 points the shortcut and `openWindow` at the open panel. Leaving `ChatModel.swift` untouched keeps the existing send, stop, and save behavior. The hole where a save error is discarded (inventory C9) is a follow-up that would own `ChatModel.swift` alone, and it is not in this set.

`Sources/Zeus/Agents/AgentCardsUI.swift` is not in this set. The inline row reuses the existing button and diff views. It does not move them.

## Red first

Each machine PR adds the test file and watches it fail to compile, because the type does not exist yet. Then it adds the type. The assertions below are the ones that must fail against an empty or permissive implementation. One assertion per row is the minimum. The rest of the target table is the same shape and belongs in the same test.

| PR | First failing assertion |
| --- | --- |
| 1 | A session status round-trips through its stored label, and the five visible words are Running, Waiting for input, Needs approval, Done, and Error. |
| 2 | `running` plus quiet-for-the-limit becomes `error` with cause `quiet`, and the clock freezes. A later activity returns to `running`. `error` failed plus activity does not. Denied returns `previous`, not a hardcoded idle. |
| 3 | A delta replaces the open agent line and does not write the file. Finish writes one JSON file. A second launch of the store reads that line back. A failed line is stored with `failed` set and is not parsed as markdown by the render helper. An empty conversation is not written. |
| 4 | A second approval queues. Approve on the first shows the second. A typed reply with a capable destination moves to awaiting-decision and does not produce a script until approved. Deny keeps the draft. A destination that cannot take text never asks. Trust does not skip the reply approval. |
| 5 | No sessions and a failed socket is `connectionError`, not empty. Empty copy does not contain a product title. The first load expands only the most urgent group. Removing the last session of a group removes the header and keeps the other groups' expanded flags. |
| 6 | With the master switch off, a done cue, a start cue, and an approval cue all return silence. With it on, the existing 20 second and 3 second rules still hold. A finish never returns two cues. |
| 7 | The focus order for a selected session with an approval is group header, row, Deny, Approve, transcript, reply, Send, Open. Reduce Motion requests zero offset and scale 1. The idle budget predicate is false when a one-second timer is scheduled while the panel is closed. |

View PRs 8 through 10 have no logic test. Their red line is a preview or a test host that fails until the view's accessibility label matches the contract in PR 7. They do not add a snapshot as proof of motion.

## Mac checklist

Linux cannot run these. Each PR is done only after the named command on a Mac, plus the walk for that PR. Keep a rollback copy before replacing an installed app. Do not sign, notarize, or install as part of the checklist. Use a disposable vault and synthetic sessions. Do not approve an OS permission prompt from the test.

The command for PRs 1 through 7 is `swift test --filter <Suite>` for the suite that PR added. The command for a wiring PR is that filter plus the existing suites its file already touches: `AgentStatusTests` for PR 11, `ChatTests` for PR 12, `AgentHooksTests` for PR 13, `ChatHotkeyMonitorTests` for PR 14, `AgentHubTests` for PR 15.

| PR | Walk on a Mac |
| --- | --- |
| 1–7 | No UI change. Run the new suite. Confirm the package file and CI workflows are untouched. |
| 8 | Host the list with two synthetic groups. Keyboard: header toggles, arrows move rows. VoiceOver reads status and elapsed time. Reduce Motion: the wave does not animate. |
| 9 | A synthetic stream shows a heading, a list, and a code block, then Copy. Stop before the first token shows Stopped. Reduce Motion: the waiting bars do not move. |
| 10 | One synthetic approval. Deny and Approve are inside the row. Control-Option-Y and N fire only while it is showing. There is no second card above the page. |
| 11 | Open Agents from the tab and from Home. Empty, connecting, connection error with Try again, two groups, select, approval grows the row, error Dismiss becomes Done. Open jumps. No new window. The existing open spring is unchanged. Time the first frame under 100 ms. With the panel closed, sample idle CPU under 1% of one core. |
| 12 | Chat tab: composer sends, Stop, markdown, history sections, New chat. Clicking the transcript does not open the floating window. A save of a non-empty chat is still the existing JSON file. |
| 13 | A synthetic hook fixture drives one session through running, waiting, approval, done, and error. An observe-only fixture never grows Approve. A socket failure becomes connection error rather than the empty sentence. One finish produces one sound decision. |
| 14 | The global chat shortcut opens the panel on Chat. It does not open the floating window. With sound opted out, a finish is silent. With sound opted in, one chime, and not again inside 3 seconds. |
| 15 | Reply from the selected row asks inline, types only after Approve, keeps the draft after Deny, and refuses a destination that cannot take text. |
| 16 | The feature map points at the new suites. A regression row exists for the double finish sound and for the shortcut opening a window. Run the mapped filters once. |

PR 11's frame budget is sampled while a synthetic transcript streams: the main-thread commit stays inside 16.6 ms at 60 Hz and 8.3 ms at 120 Hz. A static screenshot is not the motion check. Record the open and the approval grow with Reduce Motion off and on. The person's own OS consent is required for any capture. The checklist does not script a permission dialog.

The packaged-app walk, one click at a time, is `native-acceptance.md`. A PR is not accepted on a Mac until the steps it owns in that script pass. The script does not replace the unit filters above.

## Acceptance

The set is complete when every target transition has a test, the five walks for PRs 11 through 15 have been done on a Mac, and the inventory rows C11, C14, C15, C17, A13 through A16, A18, A19, A21, A22, and A25 have moved. This plan does not by itself move them.

The background chip (inventory A29) and the rename control (C18) stay out. They are stubs with no place in the hub screens. Named helpers (A27) stay on the voice path until a later spec gives them a group. That later spec is out of this set.
