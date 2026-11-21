# Chat and agent-section inventory

Spec only. This file records what the notch Chat tab, the floating chat window, and the Agents tab do in the current source. It does not change the app.

The words below are Zeus's own. External product titles that appear in source strings are not repeated here. A row cites `file:line` instead.

## How a row got its state

| State | Meaning |
| --- | --- |
| works | The behavior is complete for the contract it claims, and a named test asserts that contract. |
| partial | The behavior exists, and a hole is visible in the source: some inputs, some terminals, a missing surface, or no test of the path a person actually hits. |
| stub | A type, view, or method exists, and the running app does not call it. A pure helper used only by a test or a self-check is not a working feature. |
| broken | The source contradicts a contract it states. |

## Proof on this machine

This VM has no Swift toolchain. `swift` is not on `PATH`, and a search of `/opt`, `/usr/local`, and the home directory found no `swift` binary. `Package.swift` declares `.macOS("14.2")` only. The suites named below were not executed. A citation is the test that already asserts the contract, not a run from this pass.

On a Mac, the same contracts are the filters `ChatTests`, `MarkdownBlocksTests`, `ChatHotkeyTests`, `ChatHotkeyMonitorTests`, `ExplanationChatLifecycleTests`, `AgentCardsTests`, `AgentChimePolicyTests`, `AgentFollowUpsTests`, `AgentHooksTests`, `AgentHubTests`, `AgentStatusTests`, `WelcomeBackTests`, and `TilingKeyClashTests`. Linux cannot establish the native application build. Nothing here is a passing receipt.

No row is **broken**. That is not a green run. It means this reading did not find a self-contradiction. UI layout, VoiceOver order, sound, and frame time were not observed.

## Counts

| State | Count |
| --- | --- |
| works | 20 |
| partial | 25 |
| stub | 2 |
| broken | 0 |

47 capabilities. Chat is C1–C18. The agent section is A1–A29.

## Chat

| ID | Capability | State | Where | Proof |
| --- | --- | --- | --- | --- |
| C1 | A conversation has user and assistant lines, a title from the first question, a short preview, and a bounded exchange list that drops failed replies and a question still waiting. Search matches the title and the lines. | works | `Sources/ZeusCore/Chat.swift:4-114` | `Tests/ZeusCoreTests/ChatTests.swift` `titleComesFromFirstQuestion`, `exchangesSkipFailuresAndPendingQuestions`, `searchLooksAtTitleAndMessages` |
| C2 | History groups into Pinned, Today, Yesterday, Previous 7 days, and Older. | works | `Sources/ZeusCore/Chat.swift:117-148` | `ChatTests.sectionsGroupByDay` |
| C3 | Conversations are JSON files on this Mac. An empty unlinked draft is not written. A visual-only link survives reload without invented lines. A legacy file without that link still decodes. | works | `Sources/ZeusCore/Chat.swift:151-194` | `ChatTests.storeRoundTripsAndSkipsEmpty`, `visualOnlyLinkSurvivesStoreReloadWithoutInventingChatMessages`, `legacyConversationWithoutVisualLinkStillDecodesAndUnlinkedEmptyStaysUnsaved` |
| C4 | A message already on screen can have its text replaced while a reply streams. | works | `Sources/ZeusCore/Chat.swift:75-78` | `ChatTests.updateReplacesStreamingText` |
| C5 | Markdown is parsed into headings, lists, task items, fenced code, quotes, and rules. | works | `Sources/ZeusCore/MarkdownBlocks.swift:6` | `Tests/ZeusCoreTests/MarkdownBlocksTests.swift` |
| C6 | The floating panel hides, closes, miniaturizes, and Escape tells the conversation to stop. Deleting a chat does not undo a late save. | works | `Sources/Zeus/Chat/ChatWindow.swift:51-61` | `Tests/ZeusAppTests/ExplanationChatLifecycleTests.swift` `ownedPanelHideCloseMiniaturizeAndEscapeSynchronouslyNotifyStop` and the deletion cases in that file |
| C7 | The global chat shortcut is a stored choice, defaults to Control-Option-C, and its signature answers only itself. The monitor drops the old key before registering the new one. | works | `Sources/ZeusCore/ChatHotkey.swift:5-44`, `Sources/Zeus/Chat/ChatHotkeyMonitor.swift:56-87` | `Tests/ZeusCoreTests/ChatHotkeyTests.swift`, `Tests/ZeusAppTests/ChatHotkeyMonitorTests.swift` `movingChatLetsGoThenTellsTheChordThenRegisters` |
| C8 | New chat offers only the coding agents whose integration toggle is on, and two of them also require an installed CLI. The default is the saved label when it is offered, otherwise the first offered agent. An empty instruction or folder does not start. | works | `Sources/ZeusCore/NewChat.swift:12-46`, `Sources/Zeus/Agents/AgentHub.swift:87-108` | `Tests/ZeusCoreTests/AgentHubTests.swift` `offeredAgentsFollowTheIntegrationToggles`, `defaultAgentMustBeOffered`, `emptyInstructionOrFolderIsNotLaunched`, `requestBecomesTheTerminalAgentAction` |
| C9 | Sending a line streams text into the bubble, Stop keeps what arrived, and a failure is stored as a failed line. A save error on an ordinary chat is discarded. | partial | `Sources/Zeus/Chat/ChatModel.swift:142-245`, save at `:269` | No test drives `ChatModel.send`. The field replace itself is C4. |
| C10 | The floating window renders block markdown and a code block with Copy. Copy writes the pasteboard. | partial | `Sources/Zeus/Chat/MarkdownBlocksView.swift:7-113` | The parser is C5. No test renders the view or the copy button. |
| C11 | The bar shows the latest three lines, inline markdown only, and clips each line. Code blocks are not shown there. | partial | `Sources/Zeus/Chat/ChatWindow.swift:190-199`, `:258-262` | No test. The full renderer is the floating window (C10). |
| C12 | The window sidebar searches, groups by day, pins, copies, and deletes. | partial | `Sources/Zeus/Chat/ChatWindow.swift:110-178` | Grouping and search are C1 and C2. The sidebar itself has no test. |
| C13 | The Chat tab has New chat, History with a count, a Writing indicator, and an empty state. | partial | `Sources/Zeus/TopBar/ChatPage.swift:18-48` | No view test. |
| C14 | History inside the bar is a flat list with a relative time. It does not use the day sections from C2. | partial | `Sources/Zeus/TopBar/ChatPage.swift:137-171` against `Sources/ZeusCore/Chat.swift:139-147` | The section helper is tested. This list does not call it. |
| C15 | Tapping the compact transcript opens the floating window. | partial | `Sources/Zeus/TopBar/ChatPage.swift:107-109`, wired at `Sources/Zeus/App/AppDelegate.swift:211` | The window opens. The conversation leaves the bar. |
| C16 | Start builds a terminal command and runs it after an approval. The hub only stores the spoken result. | partial | `Sources/Zeus/Agents/AgentHub.swift:110-119` | The command value is tested (C8). `launch()` is not. |
| C17 | Zeus's own composer, Send, and Stop live in the floating window. The bar has no composer for that conversation. | partial | `Sources/Zeus/Chat/ChatWindow.swift:294-323` | No test of the field. The bar path is C11 and C15. |
| C18 | A conversation can be renamed in the model. No control calls that method. | stub | `Sources/Zeus/Chat/ChatModel.swift:137-139` | `ExplanationChatLifecycleTests` calls it. No view does. |

The hotkey still opens the floating window (`Sources/Zeus/App/AppDelegate.swift:218`). That is the same extra window as C15.

## Agent section

The Agents tab is the list inside the open top bar (`Sources/Zeus/Notch/NotchView.swift:838-857`). The closed notch and the tab row are shared chrome, not a second surface.

| ID | Capability | State | Where | Proof |
| --- | --- | --- | --- | --- |
| A1 | Six session states, their colors, and the rule that an approval, a failure, a session that needs you, a stall, then the peek session, then any working session, wins the halo. | works | `Sources/ZeusCore/AgentHealth.swift:4-9`, `Sources/Zeus/Notch/NotchView.swift:47-57`, `Sources/Zeus/Notch/NotchModel.swift:116-124` | `Tests/ZeusAppTests/AgentStatusTests.swift` `halosPickTheMostUrgentState`, `failedAndStalledHaveTheirOwnColours` |
| A2 | A working session becomes stalled after a configurable silence, and a later event makes it working again. | works | `Sources/ZeusCore/AgentHealth.swift:49-71`, `Sources/Zeus/Notch/NotchModel.swift:128-138`, `Sources/Zeus/Notch/NotchController.swift:236-244` | `AgentHubTests.stallNeedsAWorkingSessionAndEnoughSilence`, `stallLimitIsConfigurable`; `AgentStatusTests.workingSessionStallsAfterTheLimitWithAFakeClock`, `aNewEventResumesAStalledSession` |
| A3 | A failure payload becomes a short reason. A long detail is cut. | works | `Sources/ZeusCore/AgentHealth.swift:12-46` | `Tests/ZeusCoreTests/AgentHubTests.swift` failure cases: a known error code, an unknown code, a long detail, and a rollout error |
| A4 | A question, a plan, and a file edit become card content: parsed options, an answer object, a trimmed diff. | works | `Sources/ZeusCore/AgentCards.swift:6-157` | `Tests/ZeusCoreTests/AgentCardsTests.swift` |
| A5 | After a question is answered, the app remembers which return path the agent honored, and falls back when the next result does not contain the answer. | works | `Sources/ZeusCore/AgentFollowUps.swift:95-165`, `Sources/Zeus/Agents/AgentCardsUI.swift:55-89` | `Tests/ZeusCoreTests/AgentFollowUpsTests.swift` `answerPathsBuildTheRightDecision`, `trackerKeepsAllowWhenHonoured`, `trackerFallsBackWhenResultLacksAnswer`, `trackerFallsBackOnPromptRightAfter` |
| A6 | Trusting a chat auto-approves later requests in memory only. High risk, a plan, a question, and a shell that deletes, overwrites, or reaches the network still ask. Quit clears the trust. | works | `Sources/ZeusCore/AgentHubRules.swift:148-198`, `Sources/Zeus/Agents/TrustedChatStore.swift:4-19` | `AgentHubTests.onlyTrustedSessionsAutoApprove`, `highRiskAndRiskyCommandsStillAsk`, `plansAndQuestionsAlwaysNeedAPerson`, `offerFollowsTheSameRules`, `revokeAndClear`; `AgentStatusTests.trustedChatStoreAppliesTheRules` |
| A7 | The agent picker moves with Up and Down, wraps, Return opens, and Escape closes. An empty list only closes. The index stays in range when a session ends. | works | `Sources/ZeusCore/AgentHubRules.swift:64-101`, `Sources/Zeus/Notch/NotchController.swift:808-839` | `AgentHubTests.keyTable`, `arrowsWrapAndReturnOpens`, `emptyListJustCloses`, `staysInRangeWhenASessionEnds` |
| A8 | A finished turn becomes one trimmed line and a duration. In full screen, with quiet mode on, a peek and a completion wait, and a question or an approval still shows with no sound. | works | `Sources/ZeusCore/AgentCards.swift:212-255` | `AgentCardsTests.completionSummary`, `completionSummaryIsOneTrimmedLine`, `durationTextRoundsAcrossUnitBoundaries`, `questionsStayVisibleButSilentInFullScreen`, `quietInFullScreen` |
| A9 | A start chime is off unless its setting is on. A done chime needs 20 seconds of work. Approval and answer chimes have their own timing. At most one agent chime every 3 seconds. | works | `Sources/ZeusCore/Sound/AgentChimePolicy.swift:6-71`, called from `Sources/Zeus/App/AppDelegate.swift:1081-1084` | `Tests/ZeusCoreTests/AgentChimePolicyTests.swift` |
| A10 | Hook payloads from each connected family become one event vocabulary. Installing the hook config keeps other entries and can be repeated. | works | `Sources/ZeusCore/AgentHooks.swift:5-90`, config at `:94` | `Tests/ZeusCoreTests/AgentHooksTests.swift` |
| A11 | After 10 minutes away, the recap lists finishes, failures, and anything still waiting. A shorter absence, or an event from before the absence, produces nothing. | works | `Sources/ZeusCore/WelcomeBack.swift:19-48`, presented by `Sources/Zeus/Agents/WelcomeBackRecap.swift:23-48` | `Tests/ZeusCoreTests/ParityTests.swift` `WelcomeBackTests` |
| A12 | Banner text for a finished, failed, or stalled agent drops the project when details are hidden. | works | `Sources/Zeus/App/SystemNotificationService.swift:80-106` | `AgentStatusTests.agentAlertTextHidesTheProjectWhenDetailsAreHidden` |
| A13 | Hook events create and update an in-memory session list, and the Agents page draws one row each. The list is gone when the app quits. There is no transcript. | partial | `Sources/Zeus/Agents/AgentEventServer.swift:63-167`, `Sources/Zeus/Notch/NotchView.swift:838-857`, `Sources/Zeus/Notch/NotchModel.swift:15-26` | No test drives `AgentEventServer.process`. The row is a single task line (`NotchView.swift:893-897`). |
| A14 | A ticking elapsed time is drawn only while the row is working. A finished card can show a frozen duration. Other states show a chip and no clock. | partial | `Sources/Zeus/Notch/NotchView.swift:603-613`, `:905-909` | Duration text is A8. The ticking view has no test. The closed peek also clocks only a working session (`NotchView.swift:520-522`). |
| A15 | One approval card at a time, with Deny and Approve, a countdown, and a timeout. A second request waits. The card is pointer and voice, drawn above the page, not inside the row. | partial | `Sources/Zeus/Notch/NotchController.swift:305-356`, `Sources/Zeus/Notch/NotchView.swift:616-713` | No test of the wait, the timeout, or the buttons. Rich content is A4. |
| A16 | While a card is waiting and the setting is on, Control-Option-Y approves, N denies, and O asks. The plain card has no Ask button. | partial | `Sources/Zeus/App/AppDelegate.swift:1144-1151`, setting `shortcut.answerKeys` in `Sources/Zeus/App/SettingsCatalog.swift:122` | `Tests/ZeusAppTests/TilingKeyClashTests.swift` records the keys. Nothing asserts that Y resolves allow. |
| A17 | Open brings the session's app forward. Two terminal apps can be told the exact tab. Any other known app is only activated or launched. The control is hidden when the app is unknown. | partial | `Sources/ZeusCore/AgentCards.swift:164-207`, `Sources/Zeus/Agents/AgentCardsUI.swift:94-130`, `:592-602` | `Tests/ZeusCoreTests/AgentFollowUpsTests.swift` covers both exact-tab scripts and rejects unsafe values. `Tests/ZeusCoreTests/AgentCardsTests.swift` `terminalTargetFromEnvironment` |
| A18 | A reply can be typed into those same two terminals, only after an approval card, and only from the Chat tab. The Agents tab has no reply field. | partial | `Sources/ZeusCore/AgentReply.swift:7-105`, `Sources/Zeus/Agents/AgentHub.swift:27-49`, `Sources/Zeus/TopBar/ChatPage.swift:188-223` | `AgentHubTests.sendsAfterApproval`, `declinedFailedUnsupportedAndEmptyTypeNothingWrong`, `otherTerminalsCannotBeTypedInto`, `sanitizeKeepsOneLine` |
| A19 | Finishing can play a system sound when "Play a sound when an agent finishes" is on, which is the default, in addition to the done chime from A9. | partial | `Sources/Zeus/Agents/AgentEventServer.swift:171-176`, default at `Sources/Zeus/Agents/AgentCardsUI.swift:21` | The chime policy is A9. This second sound has no test, and both paths can run for one finish. |
| A20 | A banner is sent for a failure or a stall when that notification setting is on, and for a finish when the system-notification setting is on and no completion card was shown. Delivery still requires an authorization Zeus already has. Zeus does not ask. | partial | `Sources/Zeus/App/SystemNotificationService.swift:357-367`, finish fallback `Sources/Zeus/Agents/AgentEventServer.swift:178-183` | Copy hiding is A12. The deliver path is not tested. Two different settings gate one idea. |
| A21 | The empty Agents page is one icon and one sentence. The sentence names a single external coding agent. A dead hook socket is logged and looks the same as an empty list. There is no loading row and no recovery control. | partial | `Sources/Zeus/Notch/NotchView.swift:841-847`, `Sources/Zeus/Agents/AgentEventServer.swift:40-43` | No test. |
| A22 | The list can show a session whose hook family never asks Zeus for a decision. Only the families that set the decision flag get an approval card. | partial | `Sources/ZeusCore/AgentHooks.swift:13-14`, `:34`, `:47`, `:72` | The flag is covered by `AgentHooksTests`. The page does not say that a row cannot be approved. |
| A23 | The Home agents card shows a count summary and opens the Agents tab. | partial | `Sources/Zeus/TopBar/HomeWidgetViews.swift:559-569`, summary `Sources/Zeus/Notch/NotchView.swift:831-836` | No test. |
| A24 | A session Zeus itself is running can show Stop. Other rows cannot. The browser agent asks on the same approval card. | partial | `Sources/Zeus/Notch/NotchModel.swift:113-114`, `Sources/Zeus/Notch/NotchView.swift:910-912`, `Sources/Zeus/BrowserAgent/BrowserAgentRunner.swift:196-205` | `Tests/ZeusCoreTests/BrowserAgentLoopTests.swift` covers the loop's own approve and stop rules. The notch wiring is not in that suite. |
| A25 | Page changes and the working wave honor Reduce Motion. The agent list has no full keyboard order beyond the picker. VoiceOver is announced for a new approval and a completion, and the panel stays up while VoiceOver is on. | partial | `Sources/Zeus/TopBar/TopBarViews.swift:156`, `:528-539`, `Sources/Zeus/Notch/NotchController.swift:346-349`, `:419-421`, `Sources/Zeus/Agents/AgentEventServer.swift:186-189` | No agent-page accessibility test. The picker keys are A7. |
| A26 | Dismissing a failure card returns that session to idle and closes a peek that has nothing else to show. | partial | `Sources/Zeus/Notch/NotchController.swift:257-265`, bridge `Sources/Zeus/Agents/AgentTroubleCard.swift:9` | No test. |
| A27 | Named helpers can be addressed by voice and can remember notes. They do not appear in the Agents list. | partial | `Sources/ZeusCore/Mac/NamedAgents.swift:101-134`, called from `Sources/Zeus/App/VoiceTurnController.swift:806` | `Tests/ZeusCoreTests/MacControlTests.swift` routes and memory cases |
| A28 | A working row can show a five-bar wave. The wave pauses when Reduce Motion is on. The choice of wave versus a plain row is a setting. | partial | `Sources/Zeus/Notch/NotchView.swift:902-904`, `Sources/Zeus/TopBar/TopBarViews.swift:147-166` | No test of the agent wave. |
| A29 | A background-session model and a chip view exist. The file says nothing creates those sessions, and no other file shows the chip. | stub | `Sources/Zeus/Agents/BackgroundAgentTracker.swift:6-61` | `Tests/ZeusCoreTests/LaneETests.swift` `BackgroundAgentTests` asserts the unused move and steer helpers. The eval harness calls the same helpers. The chip is never referenced. |

Rows are not grouped. `Sources/Zeus/App/AppDelegate.swift:1100` groups names only for a diagnostics line.

## What the code does today

These are the machines the source already runs. The target machines are in `target.md`. They are not the same table.

### Session

`idle`, `working`, `needsYou`, `done`, `failed`, and `stalled` (`Sources/ZeusCore/AgentHealth.swift:4-9`). A row that is stalled is labeled Quiet (`Sources/Zeus/Agents/AgentCardsUI.swift:405-415`).

| From | Event | To |
| --- | --- | --- |
| absent | session start | idle |
| any | person submitted a prompt | working, clock restarts |
| any | a tool event with a name | working |
| any | permission request, blocked outright | failed |
| any | permission request, trusted and safe | working, no card |
| any | any other permission request | needsYou, card shown |
| needsYou | allow | working |
| needsYou | deny | idle |
| any | stop with a failure | failed |
| any | stop | done |
| any | a notice that an answer did not land | needsYou |
| any | session end | removed, trust dropped |
| working | silence at or past the stall limit | stalled |
| stalled | any later event except session end | working |
| failed | dismiss | idle |
| any | an event that is not a failure or a stall | reason cleared |

Sources: `Sources/Zeus/Agents/AgentEventServer.swift:74-166`, `Sources/Zeus/Notch/NotchController.swift:217-265`, `:288-293`.

There is no `waiting for input` distinct from `needsYou`, and no `needs approval` on the row. The approval is a separate card. Done and failed rows do not show a live elapsed time.

### Approval card

| From | Event | To |
| --- | --- | --- |
| no card | request | showing, and a second request waits |
| showing | Allow, Deny, Ask, or timeout | no card, one verdict |

Ask is a keyboard verdict (`Sources/Zeus/App/AppDelegate.swift:1151`) without a button on the plain card. Timeout defaults to deny for a reply (`Sources/Zeus/Agents/AgentHub.swift:66`) and to ask for a hook permission (`Sources/Zeus/Agents/AgentEventServer.swift:125`).

### Reply

| From | Event | To |
| --- | --- | --- |
| drafting | empty after cleaning | empty, nothing typed |
| drafting | terminal cannot take text | unsupported |
| drafting | person denies | declined |
| drafting | script does not find the tab | failed |
| drafting | script types the line | sent, draft cleared |

`Sources/ZeusCore/AgentReply.swift:100-104`, receipts at `Sources/Zeus/Agents/AgentHub.swift:39-48`.

### Zeus chat stream

| From | Event | To |
| --- | --- | --- |
| idle | send, instant local answer | settled |
| idle | send, no engine | failed line |
| idle | send, engine accepts | streaming |
| streaming | text delta | streaming, bubble replaced, not saved on every delta |
| streaming | stop or cancel | settled, or the word Stopped if nothing arrived |
| streaming | stream ends empty | failed, "No answer came back." |
| streaming | stream throws | failed, spoken error text |

`Sources/Zeus/Chat/ChatModel.swift:159-245`. The notch does not show this stream as markdown blocks (C11).

### Picker

| From | Event | To |
| --- | --- | --- |
| closed | open-notch shortcut | panel, Agents tab, a row highlighted |
| open | Up or Down | another row, wrapping |
| open | Return | jump, then close |
| open | Escape or the shortcut again | close |
| open | session count changes | index clamped |

`Sources/Zeus/Notch/NotchController.swift:808-839`.

## Left out on purpose

Display choice, notch open and close, and the rest of the top bar are shared chrome. This inventory does not grade them. Notification peeks for other apps live in `Sources/ZeusCore/AgentHubRules.swift:7-58` and are not the agent hub.
