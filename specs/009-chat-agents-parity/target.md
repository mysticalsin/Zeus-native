# Chat and agent hub, target

The hub lives in the open top bar Zeus already draws. The closed shape, the tab row, the page spring, the press feedback, the black panel, and the card finish stay as they are. Nothing in this target adds a window, a second bar, or a new motion style.

Two tabs carry it. **Agents** is the live sessions. **Chat** is Zeus's own conversation. Both stay inside the page that is already 236 pt tall under the tab row, in the 870 pt body, inset 18 pt (`Sources/ZeusCore/TopBar/GlanceTopBar.swift:14-58`). A selected session scrolls inside that page. The panel grows only the way an approval already grows it: the existing extra height, animated with the existing height spring.

External product names are not part of the interface. A session shows the name the session itself reported.

## What a person can do

- See every live session, grouped, with a status and an elapsed time.
- Approve or deny on that row, with the keyboard.
- Jump to the session's terminal or app.
- Read a streaming reply with markdown and code, in the bar.
- Keep the conversation, and Zeus's own chat, on this Mac.
- Reply from the bar.
- Hear a sound only after opting in.
- Recover from an empty list, a dead connection, and a failed turn.
- Do all of this with VoiceOver, the keyboard, and Reduce Motion.

## Status words

The row uses these words, in the colors the notch already uses for the matching idea (`Sources/Zeus/Notch/NotchView.swift:47-57`).

| Word | Color already in the bar | When |
| --- | --- | --- |
| Running | accent | The session is working. |
| Waiting for input | accent | It asked a question and is blocked on the answer. Not a permission. |
| Needs approval | ember | A permission is waiting on this row. |
| Done | leaf | The turn finished. The clock is frozen. |
| Error | danger | The turn failed, or it has been silent past the stall limit. The reason says which. |

Quiet, amber, and a separate stall chip go away. A silence past the limit is an Error whose reason is "No activity for N min". A new event clears that error. A hard failure does not clear until the person dismisses it or the session starts a new prompt.

Elapsed time is tabular, `m:ss`, on every row. It ticks once a second while the row is Running, Waiting for input, or Needs approval. It freezes at the transition into Done or Error. It is hidden while the panel is closed, including on the closed peek. The closed peek keeps the status word it already has.

## Screens to draw

Draw these inside the existing open panel. Do not draw a new window. Do not draw a new tab. Agents is the bolt tab that already exists. Chat is the bubble tab that already exists. The tab row is unchanged.

Shared chrome, every open screen: black panel, 22 pt bottom radius, tab capsule where it already sits, page crossfade of 8 pt and a 0.985 scale that Reduce Motion removes. Pressed controls scale 2% for 120 ms, and do not scale when Reduce Motion is on.

### 1. Closed bar

Unchanged 185 by 32 pt shape, or the hardware notch, or the drawn shape. The halo color follows the most urgent session: approval, then error, then waiting, then running. No session list, no clock, no sound.

### 2. Agents, empty

Page is empty of rows. Centered in the 236 pt page: the existing bolt-in-a-circle glyph, then "Nothing running", then "Start a chat and it shows up here." No product name. No button that leaves the bar. A text button "New chat" switches to the Chat tab and opens its new-chat form. That is the same form the Chat tab already has.

### 3. Agents, loading

Same page, for the moment the hook socket is opening and no session exists yet. The glyph stays. The line under it is "Connecting…". No spinner that travels. If Reduce Motion is on, the line is the only change. This state is not allowed to sit on screen as a delay: the open budget is under 100 ms, so a warm socket should skip this frame.

### 4. Agents, connection error

Same composition as empty. The line is "Agents aren't connected." The reason is one short sentence from the socket, with no paths that contain a secret. A button "Try again" is the only action. It is not the empty state. The two must be distinguishable without color: different sentence, and the button exists only here.

### 5. Agents, groups, nothing selected

A vertical list. Each group header is 28 pt: a 7 pt status dot in the most urgent color inside the group, the agent name, a monospaced count, and a chevron. Headers with no sessions are not drawn. The first group is expanded. The rest are collapsed. A collapsed header still shows the dot, the name, the count, and the elapsed time of its most urgent row.

An expanded group stacks the existing 58 pt row: avatar, dot, name, project, one task line, status word, elapsed time, and Open when a destination is known. The wave beside a Running clock stays the existing five bars, and only while Running. Meeting mode still hides the project and the task, and shows the status word.

### 6. Agents, a row selected

The page splits the way the Chat tab already splits: 270 pt list, then the detail. The selected row is the existing 12% white selection. The detail, top to bottom:

- Name, project, status word, frozen or live elapsed time, Open.
- A scrolling transcript. The person's lines are the existing user bubble. The agent's lines use the existing markdown blocks: headings, lists, quotes, and a code block with Copy. The newest line is at the bottom.
- While tokens are arriving, the last agent bubble grows in place. Before the first token, the existing small level bars sit in the bubble, and they are still when Reduce Motion is on.
- A reply field, 30 pt, placeholder "Reply", and Send. Send is quiet until the field has non-space text.

The list remains visible. Selecting another row swaps the detail. The panel does not navigate away.

### 7. Agents, approval inline

The selected row, or the only row that needs approval, grows downward inside the list. Under the 58 pt summary: the tool name, the risk word if it is high, the command or the question or the diff the card already knows how to draw, then Deny and Approve. Deny is the existing unfilled button. Approve is the existing ember filled button. A countdown in the existing caption sits under them: "12 s left, then it's denied."

The detail column shows the same decision, not a second copy of the buttons. One pair of buttons is on the row. The detail shows the command or the question in full, scrolling inside the page.

No card is painted above the page. The ember wash that today sits above the page is not added again.

### 8. Agents, error and recovery

An Error row uses the danger dot and the word Error. The task line is the reason. The detail adds two actions: "Dismiss" and, when a destination exists, "Open". Dismiss does not delete the transcript. The row becomes Done, the clock stays frozen, and the reason remains as the last line. A quiet error (no activity) needs no Dismiss: the next event from that session returns it to Running and clears the reason.

### 9. Chat, conversation in the bar

The Chat tab no longer opens a window when the transcript is tapped, and the global chat shortcut no longer opens one either. The shortcut opens this panel on the Chat tab.

The page uses the same split. Left, 270 pt: New chat, and History grouped as Pinned, Today, Yesterday, Previous 7 days, Older. Right: the transcript with the same markdown as screen 6, then the composer that today lives only in the floating window, including Stop while a reply is streaming. Empty copy stays "New conversation" and "Chats stay in History on this Mac."

The floating window is not on this path. This target does not draw it.

### 10. Reduce Motion

Redraw screens 5, 6, and 7 with Reduce Motion on. The page does not rise or scale. The wave is a fixed silhouette. Buttons do not scale, and they still dim when pressed. Status, selection, and the approval block change in one frame. The clock still updates once a second. Nothing travels to show a change.

### 11. VoiceOver order

Not a separate picture. On screen 6 the order is: tab row, group headers, each visible row as one element ("Agent, project, Running, 3 minutes 12 seconds"), the transcript, Copy on a code block, the reply field, Send, Open. On screen 7, Deny then Approve come after that row's summary and before the next row. Selected is a trait, not a color.

## State machines

Every machine is total. A pair that is not in the table does not change state. Guards are in the Guard column. `previous` means the session state stored when the approval began.

### Panel

Unchanged. Closed, peek, and panel stay the notch's existing presentation. This hub does not add a presentation. Opening Agents or Chat means panel plus that tab. The closed peek may name the most urgent status. It does not host the list, the transcript, the reply field, or the buttons.

### Hub screen

| From | Event | Guard | To |
| --- | --- | --- | --- |
| empty | socket opened, no sessions |  | empty |
| empty | socket opening |  | loading |
| loading | socket opened, no sessions |  | empty |
| loading | at least one session |  | ready |
| loading | socket failed |  | connectionError |
| empty | a session arrives |  | ready |
| ready | last session ends |  | empty |
| ready | socket failed | sessions may still be on screen | connectionError |
| connectionError | Try again |  | loading |
| connectionError | socket opened |  | empty or ready, from the session count |
| any | New chat | Chat tab | the Chat new-chat form, hub phase remembered |

### Session

States: `absent`, `loading`, `running`, `waitingForInput`, `needsApproval`, `done`, `error`. `error` carries a cause, `failed` or `quiet`.

| From | Event | Guard | To |
| --- | --- | --- | --- |
| absent | announced |  | loading |
| loading | prompt started |  | running, clock starts |
| loading | ended |  | absent |
| running | tool activity |  | running, clock not reset |
| running | question asked |  | waitingForInput, clock keeps going |
| running | approval requested |  | needsApproval, `previous` stored, clock keeps going |
| running | finished |  | done, clock frozen |
| running | failed |  | error failed, clock frozen |
| running | quiet for the stall limit |  | error quiet, clock frozen |
| running | ended |  | absent |
| waitingForInput | answer accepted |  | running |
| waitingForInput | approval requested |  | needsApproval, `previous` = waitingForInput |
| waitingForInput | failed, finished, or ended |  | same as from running |
| needsApproval | approved |  | running |
| needsApproval | denied or timed out |  | `previous` |
| needsApproval | ended |  | absent |
| done | prompt started |  | running, clock restarts |
| done | ended |  | absent |
| error quiet | any activity or a new prompt |  | running, clock restarts only on a new prompt |
| error failed | prompt started |  | running, clock restarts |
| error failed | dismissed |  | done, reason kept in the transcript |
| error | ended |  | absent |

Urgency, for the group dot, the halo, and which row a collapsed header represents: `needsApproval`, then `error`, then `waitingForInput`, then `running`, then `done`, then `loading`.

A session from a family that cannot ask for a decision never enters `needsApproval`. Its row does not grow buttons. If that family later sends a question event, the row can enter `waitingForInput`.

### Approval

One approval is live. A second request for another session waits. The waiting session stays in the state it already had until its request reaches the front.

| From | Event | Guard | To |
| --- | --- | --- | --- |
| idle | request | no other approval is showing | showing, bound to that session |
| idle | request | another is showing | queued |
| showing | Approve |  | idle, verdict allow, next queued request shows |
| showing | Deny or timeout | timeout action is deny | idle, verdict deny, next shows |
| showing | Ask | keyboard only, when the request allows it | idle, verdict ask, next shows |
| queued | the showing approval closes |  | showing |

Approve and Deny are the buttons. Ask stays the existing third keyboard verdict and is not given a new button. The keys are the ones already registered: Control-Option-Y, N, and O, only while an approval is showing and the setting is on.

### Transcript

One transcript per session, and one for each Zeus conversation. They do not share a store.

| From | Event | Guard | To |
| --- | --- | --- | --- |
| idle | person sends non-empty text |  | streaming, user line saved |
| idle | person sends blank |  | idle |
| streaming | delta |  | streaming, agent line replaced, not written on every delta |
| streaming | finish with text |  | settled, saved |
| streaming | finish empty |  | failed, the existing "No answer came back." |
| streaming | stop |  | settled if any text arrived, otherwise the word Stopped |
| streaming | failure |  | failed, the error line, saved |
| settled or failed | person sends |  | streaming |

The bar renders settled and streaming agent lines as markdown blocks, including code. A failed line is plain text in the danger color, not parsed as markdown.

### Quick reply

This is the reply on an agent row. Zeus's own composer is the transcript machine above, and it does not ask for an approval before talking to Zeus.

| From | Event | Guard | To |
| --- | --- | --- | --- |
| idle | text changes |  | drafting |
| drafting | send, empty after cleaning |  | idle, receipt "Type something first." |
| drafting | send | destination cannot take typed text | unsupported, receipt tells the person to open it |
| drafting | send | destination can take text | awaitingDecision, the inline approval shows |
| awaitingDecision | denied or timed out |  | idle, receipt "Not sent.", draft kept |
| awaitingDecision | approved |  | sending |
| sending | script typed the line |  | idle, draft cleared, receipt "Sent." |
| sending | script failed |  | failed, draft kept, receipt says to open the session |

A reply never types into a terminal without the approval row. Trust-this-chat does not cover a typed reply. The existing rule that a trusted chat still asks for a dangerous command stays.

### Groups

| From | Event | Guard | To |
| --- | --- | --- | --- |
| collapsed | activate header |  | expanded |
| expanded | activate header |  | collapsed |
| any | sessions change |  | membership recomputed, expanded set kept |
| any | a group loses its last session |  | header removed |
| any | first load |  | the most urgent group expanded, others collapsed |

Groups are the reported agent name, then the project inside it. A group of one is still a header, so the list does not change shape when a second session appears.

### Notification and sound

Sound is one switch, default off. Until it is on, no agent chime plays, including the start chime, the done chime, the approval chime, and the system sound that today can play on finish. Banners keep their existing settings and still require an authorization the person already gave. This hub does not request it.

| From | Event | Guard | To |
| --- | --- | --- | --- |
| silent | opt in |  | armed |
| armed | opt out |  | silent, a playing chime stops |
| armed | a cue the policy allows |  | playing |
| armed | a cue inside the 3 second window, or a finish under 20 seconds, or a start while start-chimes are off |  | armed, nothing plays |
| playing | the sound ends |  | armed |

The policy table is the one `AgentChimePolicy` already tests. The target adds only the master opt-in in front of it, default off, and removes the second finish sound.

Banner rows, separate from sound:

| Event | Banner | Guard |
| --- | --- | --- |
| failed or quiet error | yes | the existing error-notification setting, and already authorized |
| done | yes | the existing system-notification setting, and no approval is showing |
| needs approval | no banner | the row and the keyboard are the notice; a chime only if sound is opted in |
| waiting for input | no banner | the row is the notice |

### Keyboard focus

| From | Event | Guard | To |
| --- | --- | --- | --- |
| outside the page | the page opens |  | focus stays where the tab row left it |
| a group header | Activate |  | group toggles, focus stays on the header |
| a row | Activate | picker is closed, reply field is not focused | jump, focus returns to the row |
| a row | Up or Down | list is focused, picker is closed | neighboring row |
| picker open | Up, Down, Return, Escape |  | the existing picker machine, and it wins over the list |
| reply field | Return | field is non-empty | the quick-reply machine |
| approval showing | Control-Option-Y, N, or O | setting on | the approval machine |
| any | Escape | picker open | picker closes |
| any | Escape | a row is selected and the picker is closed | selection clears |
| any | Escape | nothing selected | the panel's existing dismiss |

Tab order is the order in screen 11. Shift-Tab reverses it. There is no keyboard path that opens a window.

## Time and CPU

| Budget | Measure |
| --- | --- |
| Open under 100 ms | From the click on Agents, or from the completed hover that opens the panel onto Agents, to the first frame that shows the hub screen. The closed shape's existing open spring is not this number. |
| Frame | While a transcript streams and a clock ticks, main-thread work stays inside 16.6 ms at 60 Hz and 8.3 ms at 120 Hz. A dropped frame is a miss. |
| Idle under 1% of one core | Panel closed, no approval showing, no socket read in progress. The elapsed timer is not scheduled. A display link for the wave is not running. |

The clock is one shared one-second tick for every visible row, and it is not scheduled while the panel is closed. Streaming applies deltas on the frame, not once per token on a private timer.

## What this does not change

The closed notch, tab order, tab glyphs, page spring, press scale, colors, avatars, and the approval's existing Deny and Approve labels stay. Reduce Motion and VoiceOver behavior that the bar already has stays, and the holes in the inventory are filled inside that behavior. The hub does not add a window to do any of it.
