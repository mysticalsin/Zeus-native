# Native acceptance

A click-by-click script for a packaged Zeus app on a Mac. It accepts the machines in `target.md`. It does not accept a unit-test run, a SwiftUI preview, or an offscreen render.

One person, or a driver that sends the same clicks, runs it from the top. Do not skip a step because a later step would pass. After every step, compare the screen to the visible result and compare the newest flight-recorder line to the log result. A mismatch fails the step. The run never clicks a control that asks macOS for a new permission.

## Before the first click

The app under test is a packaged `Zeus.app` that is not already running. Quit any copy first. Keep a rollback of the installed app. Do not sign, notarize, or replace the installed copy as part of this script.

Prepare a disposable preferences domain and a disposable chat folder. Point the app at them for this run, and delete them at the end. The domain starts from the shipped defaults, then the fixture sets only these:

| Key | Value |
| --- | --- |
| Chat shortcut | Control-Option-C |
| `shortcut.answerKeys` | on |
| Agent sound master | off |
| `sound.agentStart` | off |
| `notify.errors` | on |
| `notify.system` | on |
| `privacy.details` | on |
| `general.meetingMode` | off |
| Notch open | Click, so a hover cannot open the panel between steps |

The acceptance fixture is a local process on the app's own socket. It is not a window. It sends sessions named Agent A and Agent B, project Fixture, with the ids in the steps. It can pin a session's start time so the first painted clock reads `0:05`. It can mark a destination as able to take typed text, or not. It answers a typed reply with success or failure. It never runs a real command and never contains a secret.

Reduce Motion is off, and VoiceOver is off, for steps 1 through 93. Step 94 and step 95 are a second launch with Reduce Motion on. Step 96 is a third launch with VoiceOver on and Reduce Motion off.

### Permissions that are already granted

The run does not click Allow, does not open System Settings, and does not turn a feature on that would call a request API. If any consent sheet appears, the run fails.

Already granted to Zeus, before launch:

| Permission | Why this run needs it already |
| --- | --- |
| Accessibility | The agent picker, the answer keys, and the global chat shortcut. |
| Automation, for the fixture terminal only | Open brings that terminal forward. The grant already exists, so the click does not ask. |
| Notifications | Banners for a failure and a finish. Authorization is already `authorized`. The script does not toggle the notifications switch. |

Already granted to the driver's own terminal, not to Zeus: Accessibility, so the driver can click. Screen Recording for that terminal only if the driver takes the comparison screenshot. Zeus itself does not hold Screen Recording, Microphone, Speech recognition, Camera, Calendar, Reminders, Location, Full Disk Access, Input Monitoring, or Local Network for this run, and the script never asks for them.

### Log line

The line is `FlightRecorder.line` (`Sources/ZeusCore/Diagnostics/FlightRecorder.swift:106-109`). Comparison drops the ISO-8601 timestamp and the space after it. The rest is the source padded to 8, one space, the stage padded to 12, one space, and the detail. Each step names that tail. The newest matching line is enough. Older lines stay.

Copy the visible log from Settings, Diagnostics, Logs, filter Agents, with Copy log. Settings steps use filter All, because their source is `settings`. Do not click Export, Choose folder, or Restart.

### What must never appear

No window titled Zeus Chat. No consent sheet. No card painted above the page. No empty sentence that names a product. The closed peek never shows a clock, a reply field, or Deny and Approve.

## Hub screen

The socket is down when the app launches.

### 1. Launch

Action: open the packaged app and do not click.

Visible: the closed bar only, 185 by 32 pt or the hardware notch. No panel. No Zeus Chat window.

Log: `hub      screen       connectionError`

### 2. Open onto the connection error

Action: click the closed bar once.

Visible: the panel is open on Agents. Centered in the 236 pt page: the bolt-in-a-circle glyph, the sentence "Agents aren't connected.", and a button "Try again". The empty sentences "Nothing running" and "Start a chat and it shows up here." are absent. No session row.

Log: `hub      screen       connectionError`

### 3. Try again, still down

Action: click Try again.

Visible: the same page. The line under the glyph is "Connecting…". There is no spinner traveling across the page. Within the same second the sentence returns to "Agents aren't connected." and Try again is back. The page never shows "Nothing running" in between.

Log: `hub      screen       loading`

### 4. Socket opens with no sessions

Action: start the fixture socket with no sessions, then click Try again.

Visible: "Nothing running", "Start a chat and it shows up here.", and a text button "New chat". Try again is gone. No product name anywhere in the page.

Log: `hub      screen       empty`

### 5. New chat leaves the empty page without a window

Action: click New chat.

Visible: the Chat tab is selected. The New chat form is open inside the panel: a folder menu, a text field, and a Start button drawn at 40% opacity. The field is empty. No Zeus Chat window.

Log: `hub      screen       empty`

### 6. Back to an empty Agents page

Action: click the Agents tab.

Visible: the empty Agents page from step 4. The panel did not close.

Log: `chat     tab          agents`

## One session, every session state

Fixture session `s1`, display name Agent A, project Fixture, start pinned so the first running frame reads `0:05`.

### 7. Announced, not yet working

Action: fixture sends announce for `s1`.

Visible: one group header, 28 pt, dot in the quiet color, "Agent A", count `1`, chevron open. One row, 58 pt. Status word "Running" is absent. The row reads Agent A, Fixture, and no elapsed clock yet. The page is no longer the empty sentence.

Log: `session  loading      s1`

### 8. Prompt starts the clock

Action: fixture sends a prompt "count the files" for `s1`.

Visible: status word Running in the accent color. Elapsed `0:05`. The task line is "count the files". The five-bar wave is beside the clock. The group header shows the same `0:05`.

Log: `session  running      s1`

### 9. A tool event does not reset the clock

Action: before the clock paints `0:06`, fixture sends a tool event "read notes" for `s1`. Capture that frame.

Visible: still one row. Status Running. Task line "read notes". Elapsed still `0:05`, not `0:00`.

Log: `session  running      s1`

### 10. Waiting for input

Action: fixture sends a question "Which file?" with two choices, Left and Right. Click the Agent A row.

Visible: status word "Waiting for input" in the accent color. The clock is still counting from `0:05`, not reset. No Deny button and no Approve button. The detail shows the question "Which file?" and the choices Left and Right.

Log: `session  waitingForInput s1`

### 11. Approval remembers the waiting state

Action: fixture sends an approval request, tool "Run", command "list files", low risk, timeout two seconds, for `s1`.

Visible: the row grows under the 58 pt summary. Tool "Run". Command "list files". Buttons Deny, then Approve, inside the row. Caption "2 s left, then it's denied." No second card above the page. Status word "Needs approval" in ember. The clock keeps counting.

Log: `session  needsApproval s1`

### 12. Deny returns to waiting

Action: click Deny.

Visible: Deny and Approve are gone. The row is 58 pt again. Status "Waiting for input". The question "Which file?" is still in the detail. The clock was not reset.

Log: `approval deny         s1`

### 13. An accepted answer returns to running

Action: fixture accepts the answer Left.

Visible: status Running. Task line no longer the question. Wave is back. Clock not reset to `0:00`.

Log: `session  running      s1`

### 14. A second approval, previous state running

Action: fixture sends the same approval request again.

Visible: "Needs approval", Deny and Approve inside the row, same command "list files".

Log: `session  needsApproval s1`

### 15. Approve returns to running

Action: click Approve.

Visible: the buttons are gone. Status Running. Wave visible. Clock not reset.

Log: `approval allow        s1`

### 16. Ask is a key, not a button

Action: fixture sends the approval again. Do not click. Press Control-Option-O.

Visible: before the key, the row has Deny and Approve and no Ask button. After the key, the buttons are gone and the status is Running, because the stored previous state was running.

Log: `approval ask          s1`

### 17. Timeout uses the deny path

Action: fixture sends the approval again, with a two-second timeout. Do not click. Wait until the caption reaches zero.

Visible: the row leaves "Needs approval" without a click. Status Running. The buttons are gone.

Log: `approval timeout      s1`

### 18. Quiet error freezes the clock

Action: fixture sends quiet-for-the-limit. The reason is exactly "No activity for 2 min".

Visible: status Error in danger. The task line is "No activity for 2 min". The wave is gone. The elapsed time is frozen on the value it held at the transition, not blank and not reset to `0:00`. There is no amber Quiet chip.

Log: `session  error        quiet s1`

### 19. Activity clears a quiet error and does not restart the clock

Action: fixture sends a tool event "read notes".

Visible: status Running. The reason line is gone. Elapsed continues from the frozen value. It does not jump back to `0:00`.

Log: `session  running      s1`

### 20. A new prompt restarts the clock

Action: fixture sends a prompt "count again", and pins the start so the frame reads `0:00`.

Visible: status Running. Task "count again". Elapsed `0:00`.

Log: `session  running      s1`

### 21. Finish freezes the clock

Action: fixture sends finished, summary "Counted 3 files".

Visible: status Done in leaf. Task "Counted 3 files". Elapsed frozen. Wave gone. No Approve button.

Log: `session  done         s1`

### 22. The session ends

Action: fixture sends ended for `s1`.

Visible: no row and no group header. The empty page is back: "Nothing running" and "Start a chat and it shows up here."

Log: `session  absent       s1`

## Hard errors, and the ends of the other states

### 23. A hard failure stays until dismiss

Action: fixture announces `s2` as Agent A and sends a prompt, then sends failed with reason "The service had an error".

Visible: one row, Agent A, status Error, task "The service had an error", clock frozen. The detail has Dismiss and, because a destination exists, Open.

Log: `session  error        failed s2`

### 24. A later tool event does not clear a hard failure

Action: fixture sends a tool event "read notes" for `s2`.

Visible: status is still Error. The task line is still "The service had an error".

Log: `session  error        failed s2`

### 25. Dismiss keeps the reason and marks the row done

Action: click Dismiss.

Visible: status Done. The clock stays frozen. The detail transcript's last line is "The service had an error", in plain danger text, not as a heading or a list.

Log: `session  done         s2`

### 26. A new prompt clears a hard failure

Action: fixture sends failed again, then sends a prompt "try once more" pinned at `0:00`.

Visible: status Running. Elapsed `0:00`. Task "try once more". The error line remains above it in the transcript.

Log: `session  running      s2`

### 27. Loading can end without ever running

Action: fixture announces `s3` as Agent B, and before any prompt sends ended.

Visible: Agent B's row appears with no Running word and no clock, then the row and its header are gone. Agent A's row is unchanged.

Log: `session  absent       s3`

### 28. Waiting for input can fail

Action: fixture puts `s2` into waiting for input, then sends failed with reason "The service had an error".

Visible: status Error. Reason on the task line. No question choices left as the status.

Log: `session  error        failed s2`

### 29. Waiting for input can finish

Action: fixture puts `s2` into waiting for input, then sends finished with summary "Answered".

Visible: status Done. Task "Answered". Clock frozen.

Log: `session  done         s2`

### 30. Waiting for input can end

Action: fixture puts `s2` into waiting for input, then sends ended.

Visible: the Agent A row is gone.

Log: `session  absent       s2`

### 31. An approval can end

Action: fixture creates `s4`, Agent A, prompts it, and sends an approval. Then fixture sends ended while Deny and Approve are on screen.

Visible: the row disappears. The buttons disappear with it. No card remains above the page.

Log: `session  absent       s4`

### 32. A finished row can end

Action: fixture creates `s5`, prompts it, finishes it, then sends ended.

Visible: the Done row appears, then disappears. Empty page if nothing else is left.

Log: `session  absent       s5`

### 33. An error row can end without dismiss

Action: fixture creates `s6`, prompts it, fails it, then sends ended. Do not click Dismiss.

Visible: the Error row appears, then disappears. Dismiss was not required.

Log: `session  absent       s6`

## Two approvals, and a session that cannot ask

### 34. The second approval waits

Action: fixture creates `s7` and `s8`, both Agent A, both running. It sends an approval for `s7` with command "list files", then an approval for `s8` with command "show the diff".

Visible: `s7` reads "Needs approval" and shows Deny and Approve and "list files". `s8` stays Running. It does not show buttons and it does not show "show the diff".

Log: `approval queued       s8`

### 35. Closing the first shows the second

Action: click Deny on `s7`.

Visible: `s7` is Running. `s8` now reads "Needs approval", with Deny and Approve and the command "show the diff". One pair of buttons on the whole page.

Log: `approval showing      s8`

### 36. An observe-only session never grows buttons

Action: click Deny so the page has no approval. Fixture creates `s9`, name Agent B, from a family that cannot ask for a decision, then sends a prompt and a tool event.

Visible: a second group, Agent B, status Running, with Open if a destination exists. The row does not grow, and it has no Deny and no Approve, after the tool event.

Log: `session  running      s9`

## Groups

Fixture leaves `s7` Agent A running, and `s9` Agent B running. Clear every other session first.

### 37. First load expands only the most urgent group

Action: click the closed bar to close the panel, then click it again to open Agents.

Visible: the group with the more urgent row is expanded. The other header is collapsed: dot, name, count `1`, chevron, and that row's elapsed time. The collapsed row's task line is not visible.

Log: `group    expanded     Agent A`

The more urgent group is Agent A only when the two rows tie on Running. If a later build breaks the tie differently, the expanded header is the one the urgency table names, and the other is collapsed. A tie stays Agent A, the earlier session.

### 38. Collapse and expand

Action: click the expanded header, then click it again.

Visible: after the first click the header is collapsed and its row is hidden. After the second click the row is back. The other header does not change.

Log: `group    collapsed    Agent A`

### 39. Removing the last row removes only that header

Action: fixture ends `s9`.

Visible: the Agent B header is gone. The Agent A header is still expanded, and its row is still there.

Log: `group    removed      Agent B`

### 40. The last session returns the page to empty

Action: fixture ends `s7`.

Visible: the empty Agents page. No header left.

Log: `hub      screen       empty`

## Quick reply

Fixture creates `s10`, Agent A, running, destination able to take text. Select that row.

### 41. An empty reply does not ask

Action: click Send with the reply field empty.

Visible: the field stays empty. The caption reads "Type something first." Status stays Running. No Deny and no Approve.

Log: `reply    empty        s10`

### 42. A destination that cannot take text never asks

Action: fixture marks `s10` unable to take text. Type "hello" and click Send.

Visible: the draft "hello" stays. The caption says to open the session. No approval row.

Log: `reply    unsupported  s10`

### 43. A capable destination asks inline

Action: fixture marks `s10` able to take text again. Click Send.

Visible: the row shows Deny and Approve. The command text is the draft "hello". Status "Needs approval". The draft is still in the field.

Log: `reply    awaitingDecision s10`

### 44. Deny keeps the draft

Action: click Deny.

Visible: status Running. The field still contains "hello". The caption is "Not sent."

Log: `reply    declined     s10`

### 45. Approve sends and clears the draft

Action: click Send, then click Approve.

Visible: the field is empty. The caption is "Sent." Status Running. The buttons are gone.

Log: `reply    sent         s10`

### 46. A failed script keeps the draft

Action: fixture will fail the next reply. Type "again", click Send, click Approve.

Visible: the field still contains "again". The caption tells the person to open the session. Status Running.

Log: `reply    failed       s10`

### 47. Open does not ask for Automation

Action: click Open on the `s10` row.

Visible: the fixture terminal comes forward. Zeus's panel is still the only Zeus window. No consent sheet.

Log: `session  jump         s10`

## Transcript and Zeus chat

The Chat tab. No session is selected. Sound master is still off.

### 48. The shortcut opens the panel, not a window

Action: press Escape so the panel is closed. Press Control-Option-C.

Visible: the panel is open, the Chat tab is selected, and the composer is focused. The window list has no Zeus Chat window.

Log: `chat     tab          chat`

### 49. A blank send stays idle

Action: click Send with the composer empty.

Visible: no new bubble. The composer stays empty.

Log: `chat     idle         current`

### 50. Streaming shows markdown as it arrives

Action: type "Show a sample" and click Send. The fixture streams three deltas: "# Title", then a line "- One", then a fenced code block whose body is `print(1)`.

Visible: a user bubble "Show a sample". The agent bubble grows in place. Before the first delta, the small level bars sit in the bubble. After the last delta the bubble shows a heading "Title", a list row "One", and a code block with the body `print(1)` and a Copy button. The text is inside the 236 pt page, in the column to the right of the 270 pt list.

Log: `chat     settled      current`

### 51. Copy does not leave the panel

Action: click Copy on that code block.

Visible: the button shows its pressed dim, then returns. The panel stays. No window appears. The pasteboard text is exactly `print(1)`.

Log: `chat     copy         current`

### 52. Stop before the first token

Action: click Send on "Stop this". The fixture sends no delta. Click Stop.

Visible: the agent bubble reads "Stopped." It is not a heading and not a code block.

Log: `chat     stopped      current`

### 53. An empty finish is a failed line

Action: click Send on "Fail empty". The fixture finishes the stream with no text.

Visible: the agent line is "No answer came back." in the danger color, as plain text. It is not parsed as markdown.

Log: `chat     failed       current`

### 54. A thrown failure is plain danger text

Action: click Send on "Fail hard". The fixture fails the stream with the text "The reply did not finish."

Visible: that sentence, danger color, plain text, one bubble.

Log: `chat     failed       current`

### 55. History is grouped, and a click does not open a window

Action: click a row under Today in the 270 pt list.

Visible: the list shows the headings that have chats, in this order, skipping any that are empty: Pinned, Today, Yesterday, Previous 7 days, Older. The clicked row is selected. The transcript changes. No Zeus Chat window.

Log: `chat     select       current`

### 56. The transcript click stays in the bar

Action: click the transcript body.

Visible: the composer keeps focus or takes it. The panel stays. No Zeus Chat window.

Log: `chat     tab          chat`

### 57. A non-empty chat is on disk

Action: quit is not required. Read the disposable chat folder.

Visible: one JSON file for the current conversation. It contains "Show a sample" and `print(1)`. It does not contain an empty draft conversation.

Log: `chat     saved        current`

## Sound and banners

### 58. A finish is silent while sound is opted out

Action: return to Agents. Fixture creates `s11`, prompts it, and finishes it in under 20 seconds.

Visible: the row reads Done. No chime. The system sound that used to play on finish does not play either.

Log: `sound    suppressed   done s11`

### 59. Opting in arms the switch

Action: open Settings from the menu-bar item "Settings…". On Sounds, turn Sound feedback on, turn "Chime when an agent starts working" off, and leave "Play the Completion chime" on. Close the window. This is the one settings change the hub steps make. The domain is disposable.

Visible: the Sounds toggle "Sound feedback" shows on. The start-chime toggle shows off.

Log: `sound    armed        master`

### 60. A short finish still does not chime

Action: fixture finishes a new session `s12` in under 20 seconds.

Visible: Done row. No chime.

Log: `sound    suppressed   done s12`

### 61. A long finish chimes once

Action: fixture finishes `s13` after more than 20 seconds of running.

Visible: Done row. One completion chime. Not two.

Log: `sound    playing      done s13`

### 62. A second cue inside three seconds is silent

Action: within three seconds, fixture finishes `s14` after more than 20 seconds.

Visible: Done row. No second chime.

Log: `sound    suppressed   done s14`

### 63. An approval chimes only when armed

Action: fixture raises an approval on `s13`.

Visible: "Needs approval". One request chime.

Log: `sound    playing      approval s13`

### 64. Turning sound off stops a later cue

Action: open Sounds and turn Sound feedback off. Close Settings. Fixture raises an approval on a new running session.

Visible: the row shows "Needs approval". No chime.

Log: `sound    silent       master`

### 65. A failure banner, and no banner for an approval

Action: fixture fails `s13` with reason "The service had an error".

Visible: a macOS banner whose body contains that reason and does not add a second project line beyond Fixture. The approval row from step 64 did not post a banner. The waiting-for-input row, if fixture sets one on `s14`, does not post a banner either.

Log: `notify   banner       failed s13`

## Keyboard, the closed peek, and the budgets

### 66. Closed peek has a word and no clock

Action: with `s14` running, press Escape until the panel is closed. Fixture sets the peek.

Visible: the closed bar shows the word Running. It does not show `0:05` or any `m:ss`. It does not show Deny, Approve, or a reply field.

Log: `hub      peek         running`

### 67. The picker wins over the list

Action: press the agent-picker shortcut. Press Down once. Press Return.

Visible: the panel opens on Agents. One row is highlighted. Down moves the highlight and wraps if there is one row. Return jumps to that session's terminal, the same as Open. Escape is not required after Return, because the picker closes itself.

Log: `session  jump         s14`

### 68. Escape clears a selection, then closes

Action: open Agents, click the `s14` row, press Escape, press Escape again.

Visible: the first Escape clears the selection and leaves the panel open. The second Escape closes the panel to the closed bar.

Log: `hub      screen       ready`

### 69. Tab order on an approval

Action: fixture puts `s14` into needs approval and focuses the page. Press Tab from the group header and write down each focused control.

Visible, in this order: the group header, the row, Deny, Approve, the transcript, the reply field, Send, Open. Shift-Tab reverses that order. Focus never lands on a control outside the panel.

Log: `a11y     order        s14`

### 70. Open is under 100 ms, and idle is under one percent

Action: with the panel closed and no approval showing, click Agents and time the first frame that shows the list. Then leave the panel closed for ten seconds and sample the process.

Visible: the list is on screen in under 100 ms from the click. The closed bar shows no clock. Over the ten seconds the process stays under 1% of one core. A streaming frame, taken in step 50's conditions on a second sample, stays inside 16.6 ms at 60 Hz and 8.3 ms at 120 Hz.

Log: `hub      budget       open`

### 71. A dead socket with rows still on screen

Action: stop the fixture socket while `s14` is running and the panel is open.

Visible: the connection-error sentence "Agents aren't connected." and Try again. The `s14` row is still visible under that sentence. This is not the empty page.

Log: `hub      screen       connectionError`

## Settings

Open Settings from the menu-bar item "Settings…". The window is 1080 by 780 pt. The sidebar identifier of a row is `settings.sidebar.<id>`. Click the row. Do not click Allow, Connect, Open guide, Open System Settings, Activate a license, Export, Choose folder, or Restart. Do not type into a key field. Do not turn a toggle on or off, except the sound toggles already used in steps 59 and 64, which are restored by deleting the disposable domain.

The twelve glass pages are the pages built with `GSPageHeading` in `Sources/Zeus/Settings/GlanceSettingsPages.swift`, not counting the hidden iPhone page. The sidebar shows nine more pages. Those nine are steps 84 through 92, so every shown pane is opened.

### 72. General

Action: click `settings.sidebar.general`.

Visible: page title General. Cards "Your defaults", "Day to day", "Setup", and "Keep awake". The popup "Show the notch on" reads "Built-in display". The row "Launch Zeus at login" is a toggle. The button "Open guide" is visible and is not clicked.

Log: `settings open         general`

### 73. Appearance

Action: click `settings.sidebar.appearance`.

Visible: page title Appearance. Card "Your look" shows six choices: Glass, Physical, Liquid Glass, Classic, Dashboard, Dashboard B. Exactly one has a selected check. No choice is clicked.

Log: `settings open         appearance`

### 74. Sounds

Action: click `settings.sidebar.sounds`.

Visible: subtitle "Choose your cues. Listen to each one before you begin." Card "Sound feedback" with the toggle "Sound feedback", which is off after step 64. Card "Your cues" includes "Chime when an agent starts working", and that toggle is off. No preview button is clicked.

Log: `settings open         sounds`

### 75. Notifications

Action: click `settings.sidebar.notifications`.

Visible: card "Agent notifications". The row "Permission requests" shows the status "Always on". The row "Errors and stuck agents" is a toggle. The row "Show system notifications" is a toggle and is not clicked. No button "Open System Settings" is pressed. If that button is absent, the row still shows the toggle.

Log: `settings open         notifications`

### 76. Shortcuts

Action: click `settings.sidebar.shortcuts`.

Visible: the row "Open the chat window" shows Control-Option-C. The toggle "Answer permissions from the keyboard" is on. The row "Open the agent picker" is a popup. No shortcut is recorded.

Log: `settings open         shortcuts`

### 77. Integrations

Action: click `settings.sidebar.integrations`.

Visible: subtitle "Your agents, followed from the notch." Card "Connections" and card "Available apps". Each connection row shows either "Connected" or "Connection to finish", plus a button "Check again". The offer toggles are visible. Connect is not clicked. Check again is not clicked.

Log: `settings open         integrations`

### 78. Murmure

Action: click `settings.sidebar.murmure`.

Visible: page title Murmure. The toggle "Enable dictation" is shown and is not clicked. A row "Dictation shortcut" is visible.

Log: `settings open         murmure`

### 79. Voice

Action: click `settings.sidebar.voice`.

Visible: a row "Talk to Zeus". The toggle "Listen for approval keywords" is off and is not clicked. The card "Your keywords" shows Approve, Deny, and "Open the app".

Log: `settings open         voice`

### 80. License

Action: click `settings.sidebar.license`.

Visible: subtitle "Make yourself at home." Card "Your license". On an unlicensed disposable domain the field "License key" is empty and the button "Activate a license" is disabled. The field is not typed in.

Log: `settings open         license`

### 81. Permissions

Action: click `settings.sidebar.permissions`.

Visible: subtitle "Each access is optional. Zeus asks only when you turn a feature on." The rows Accessibility, Notifications, and Automation show Allowed for the grants in the preamble. Microphone, Speech recognition, Camera, and Screen Recording do not show a pressed Allow button, and none is clicked. No sheet named after a permission appears.

Log: `settings open         permissions`

### 82. Privacy

Action: click `settings.sidebar.privacy`.

Visible: the toggle "Show project and command details" is on. The toggle "Allow command-line control of sensitive actions" is off and is not clicked. The button "Open Accessibility settings" is not clicked.

Log: `settings open         privacy`

### 83. Diagnostics

Action: click `settings.sidebar.diagnostics`.

Visible: card "Logs". The popup Show reads All. The button "Copy log" is visible. The Agents row reads Connected while the fixture socket is up, or Offline when it is not. Restart is not clicked. Export and Choose folder are not clicked.

Log: `settings open         diagnostics`

### 84. Insomnia

Action: click `settings.sidebar.insomnia`.

Visible: subtitle "Close the lid. Your agents keep working." The toggle "Keep working with the lid closed" is visible and is not clicked.

Log: `settings open         insomnia`

### 85. Polyglot

Action: click `settings.sidebar.polyglot`.

Visible: subtitle "Understand any language, live, on this Mac." The toggle "Enable Polyglot" is visible and is not clicked.

Log: `settings open         polyglot`

### 86. Dictation

Action: click `settings.sidebar.dictation`.

Visible: subtitle "Speak anywhere. Choose how it is written." The toggle "Dictation" is visible and is not clicked.

Log: `settings open         dictation`

### 87. Engine

Action: click `settings.sidebar.engine`.

Visible: subtitle "How instant commands are understood, and what it costs." A row titled Jev and a row "Monthly limit" are visible. No key is typed.

Log: `settings open         engine`

### 88. About

Action: click `settings.sidebar.about`.

Visible: the word Zeus, the line "Built by Tony Walteur", and a version line that matches the packaged bundle's short version and build. No link is clicked.

Log: `settings open         about`

### 89. Features

Action: click `settings.sidebar.features`.

Visible: subtitle "What Zeus does on its own, and how far it may go." The toggle "Fast path" is visible and is not clicked.

Log: `settings open         features`

### 90. Beamer

Action: click `settings.sidebar.beamer`.

Visible: subtitle "One keyboard and mouse across your Macs and PCs." The page's first card is on screen. No Allow button is clicked.

Log: `settings open         beamer`

### 91. Tiling

Action: click `settings.sidebar.tiling`.

Visible: subtitle "Arrange your windows from the keyboard." The toggle "Arrange my windows from the keyboard" is visible and is not clicked.

Log: `settings open         tiling`

### 92. Shelf

Action: click `settings.sidebar.shelf`.

Visible: subtitle "Send files to nearby Macs from the Shelf." The toggle "Send and receive with nearby Macs" is visible and is not clicked. No local-network sheet appears.

Log: `settings open         shelf`

### 93. The hidden page is not in the sidebar

Action: look down the sidebar.

Visible: there is no row "iPhone". The window is still 1080 by 780. Close the window with its close button. The panel, if it was open, is unchanged. No consent sheet appeared during steps 72 through 93.

Log: `settings close        settings`

## Reduce Motion, then VoiceOver

Quit the app. Turn Reduce Motion on in System Settings before the next launch. Do not change it from inside Zeus. VoiceOver stays off.

### 94. The wave does not move

Action: launch, open the socket, fixture sends one running session pinned at `0:05`, click the closed bar.

Visible: the Agents page is on screen in one frame. It does not rise and it does not scale in. The five bars beside `0:05` are a fixed silhouette for a full second. The row still reads Running.

Log: `session  running      s1`

### 95. An approval appears in one frame

Action: fixture sends an approval.

Visible: Deny and Approve are in the row on the next frame. They do not travel. Pressing Approve dims the button and does not scale it. Status returns to Running.

Log: `approval allow        s1`

Quit. Turn Reduce Motion off. Turn VoiceOver on before the next launch.

### 96. VoiceOver reads the row, and the panel stays

Action: launch, open one running session, click the closed bar, and move VoiceOver to the session row. Then move the pointer off the panel.

Visible: VoiceOver speaks "Agent A, Fixture, Running" and the elapsed time. The panel stays open while the pointer is outside it. Press VoiceOver's activate on Open. The fixture terminal comes forward. No consent sheet.

Log: `a11y     focus        s1`

## Done

Quit the app. Delete the disposable preferences domain and the disposable chat folder. Turn VoiceOver off. The installed app, if one was left in place, was not replaced.
