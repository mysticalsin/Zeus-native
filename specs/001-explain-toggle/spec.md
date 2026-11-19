# Feature Specification: Explain toggle, then show and point

**Feature Branch**: `001-explain-toggle`

**Created**: 2026-11-19

**Status**: Draft

**Input**: User description: "Zeus Explain slice 001. A tap of Right Option alone toggles listening, then Zeus acts or explains by speaking, marking, and pointing. Tony, 2026-11-19 13:03 and 13:05 BRT."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Right Option tap toggles listening (Priority: P1)

A tap of Right Option alone starts listening. A second tap of Right Option alone sends that turn. The same tap does nothing when Right Option is only a modifier, when another key is down or goes down while it is held, or when a click happens while it is held. Control-Option hold-to-talk is unchanged.

**Why this priority**: Without this gesture there is no explain turn. Every later scenario starts here.

**Independent Test**: With a synthetic key and click stream and no microphone, a lone Right Option tap enters listening and a second lone tap commits the turn. The same stream with another key or a click while Right Option is down does not. A Control-Option hold still starts and sends the existing talk turn.

**Acceptance Scenarios**:

1. **Given** Zeus is idle and Right Option is the explain key, **When** Right Option goes down and up alone inside the existing tap maximum (0.3 s), **Then** listening starts and no talk turn starts on Control-Option.
2. **Given** Right Option is down, **When** any other key goes down before Right Option comes up, **Then** listening does not start and does not send.
3. **Given** Right Option is down, **When** a mouse click happens before it comes up, **Then** listening does not start and does not send.
4. **Given** another modifier is already down, **When** Right Option taps, **Then** listening does not start. Right Option used only to modify another key never toggles listening.
5. **Given** listening has started, **When** Right Option taps alone again, **Then** the turn sends.
6. **Given** a turn is open, **When** Esc is pressed, **Then** the turn cancels, nothing is sent, and listening returns to idle.
7. **Given** listening captured only silence, **When** the second tap arrives, **Then** nothing is sent and the turn ends as empty.
8. **Given** the existing Control-Option hold-to-talk chord, **When** it is held and released as it is today, **Then** that talk turn still starts and sends. This slice does not change its confirm, chord, or hands-free rules.

---

### User Story 2 - Describe what is on screen (Priority: P1)

The person asks, in speech, what is on the screen. Zeus answers in speech and puts a numbered mark on each item the answer names.

**Why this priority**: A spoken answer with no marks does not show the person which item was meant.

**Independent Test**: A scripted transcript "Describe what's on my screen" against a synthetic screen of three controls produces one spoken answer and three numbered marks, one on each named control, and no click.

**Acceptance Scenarios**:

1. **Given** an explain turn whose transcript asks to describe the screen, **When** the answer names items, **Then** the spoken answer and a numbered mark on each referenced item appear together.
2. **Given** those marks, **When** speech names item 2, **Then** mark 2 is the one called out, and the other marks stay visible and numbered.
3. **Given** the answer names nothing on screen, **Then** there are no marks and the spoken answer says so.

---

### User Story 3 - Show where to click (Priority: P1)

The person asks where to click to do something. A drawn pointer flies to the real on-screen control and highlights it while the speech names it.

**Why this priority**: The point of the turn is to land on the control, not to describe it from memory.

**Independent Test**: A scripted transcript "Show me where to click to X" against a synthetic control frame moves the drawn pointer to that frame and highlights it for as long as the speech names it. No click is delivered.

**Acceptance Scenarios**:

1. **Given** an explain turn whose transcript asks where to click to do X, **When** the control is on screen, **Then** the drawn pointer moves to that control and the highlight is on its real frame while the speech names it.
2. **Given** the pointer is in flight, **When** the person clicks the real control, **Then** the click reaches that control. The overlay does not take it.
3. **Given** Reduce Motion is on, **When** the same request runs, **Then** the flight is a fade of the highlight onto the control, not a moving pointer.
4. **Given** the control is not on screen, **Then** the pointer does not fly to a guess, the speech says it cannot see the control, and no click happens.

---

### User Story 4 - Walk through a task (Priority: P1)

The person asks to be walked through a task. Zeus shows one step at a time. The next step starts when the person taps, or when that step is done.

**Why this priority**: A single highlight cannot carry a sequence.

**Independent Test**: A scripted transcript "Walk me through X" with three synthetic steps shows step 1 only, advances to step 2 on a Right Option tap, and advances to step 3 when step 2 is marked done, without a click on the person's behalf.

**Acceptance Scenarios**:

1. **Given** a walk of more than one step, **When** it starts, **Then** only the current step's pointer and highlight are shown, and the speech names that step.
2. **Given** a step is showing, **When** Right Option taps alone, **Then** the next step shows and the previous highlight leaves.
3. **Given** a step is showing, **When** that step is done, **Then** the next step shows without waiting for a tap.
4. **Given** the last step is done, **When** nothing remains, **Then** the walk ends, the overlay is torn down, and listening is idle.
5. **Given** a walk is in progress, **When** Esc is pressed, **Then** the walk cancels, the overlay is torn down, and no later step runs.

---

### User Story 5 - Pointer, marks, displays, and clicks (Priority: P1)

Pointer and marks stay in time with the speech. They work on any display, including more than one display and Retina scaling. They never block clicks. A click Zeus would make for the person still waits for the existing approval gate.

**Why this priority**: A mark on the wrong display, or a click that skips approval, is a wrong turn.

**Independent Test**: The same scripted point is checked on a main display and a second display at a non-1 backing scale. The overlay hit test is empty. A scripted "click it for me" presents the existing approval card and does not click before that card allows it.

**Acceptance Scenarios**:

1. **Given** speech is naming a control, **When** the audio clock is at that phrase, **Then** the pointer and the highlight are on that control, not on the previous or next one.
2. **Given** the control is on a display that is not the main display, **When** the turn points at it, **Then** the mark uses that display's frame.
3. **Given** the display's backing scale is not 1, **When** the mark is drawn, **Then** it sits on the control's point frame, not on a 1x mis-scale of that frame.
4. **Given** the overlay is up, **When** the person clicks, drags, or types, **Then** the event reaches the app under the overlay.
5. **Given** the turn would click a control for the person, **When** that click is risky, **Then** the existing approval card is presented and the click does not happen until that card allows it. Highlighting is not a click.
6. **Given** the turn ends by send, cancel, empty, error, or the last walk step, **When** the turn leaves, **Then** the overlay and every mark are gone. No other new window was opened during the turn.

---

### User Story 6 - Right Command stays hold to dictate (Priority: P2)

Right Command stays hold-to-dictate for Murmur. A tap of Right Command is optional and off by default. This slice does not turn that tap on.

**Why this priority**: Explain must not steal dictation.

**Independent Test**: With the default settings, a Right Command hold still dictates and a Right Command tap does not start explain listening.

**Acceptance Scenarios**:

1. **Given** default settings, **When** Right Command is held and released as Murmur does today, **Then** dictation still runs and explain listening does not start.
2. **Given** default settings, **When** Right Command taps, **Then** explain listening does not start and Murmur does not send.
3. **Given** the optional Right Command tap setting is off, **When** the setting is read, **Then** it is off. This slice does not add a control that turns it on.

---

### User Story 7 - VoiceOver, loading, empty, error, and recovery (Priority: P2)

The same actions are available to VoiceOver. Loading, empty, error, and recovery are spoken and visible as states, not only as color.

**Why this priority**: A gesture-only turn leaves VoiceOver and a failed engine with no way through.

**Independent Test**: A VoiceOver action list on the explain status includes listen, send, and cancel. A scripted engine failure moves to error, speaks the failure, tears the overlay down, and a later Right Option tap starts a new turn.

**Acceptance Scenarios**:

1. **Given** VoiceOver is on, **When** listening starts, sends, cancels, or refuses silence, **Then** an announcement says which of those happened, including the mark number and the control name when a mark or pointer is showing.
2. **Given** the speech engine is not ready, **When** Right Option taps, **Then** the state is loading, listening does not pretend to have started, and nothing is sent.
3. **Given** loading finishes ready, **When** the person taps again, **Then** listening starts.
4. **Given** the engine fails during a turn, **When** the failure is reported, **Then** the state is error, the overlay is gone, nothing is sent, and the announcement names the failure.
5. **Given** error or cancel, **When** Right Option taps alone after that, **Then** a new turn starts. The failed turn cannot send later.

---

### Edge Cases

- Right Option held longer than the tap maximum, with no other key and no click, does not toggle listening. It is not a tap.
- A repeat of the Right Option key-down does not start a second listen.
- A second tap while the engine is still loading does not send.
- Two explain turns cannot be open. A tap during an open turn is send, step-advance, or cancel, never a second listen.
- Control-Option and Right Option do not run two turns at once. The existing one-turn rule across the talk keys stays.
- A walk with an empty step list ends as empty and does not open the overlay.
- A display going away mid-flight tears that mark down and the speech says the control is gone. It does not leave a highlight on a stale frame.
- Reduce Motion does not change when speech starts, when a step advances, or when approval is required. It only replaces the pointer flight with a fade.
- The top bar's existing visuals, springs, and animations are not part of this slice. They keep their current motion, including their own Reduce Motion behavior.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: A tap of Right Option alone MUST toggle explain listening. Tap means down and up with no other key and no click in between, inside the existing 0.3 s tap maximum.
- **FR-002**: Right Option MUST NOT toggle listening when it is used as a modifier, when another key is down or goes down while it is held, or when a click happens while it is held.
- **FR-003**: Control-Option hold-to-talk MUST stay on its current rules.
- **FR-004**: A second Right Option tap while listening MUST send. Esc MUST cancel. Silence MUST NOT send.
- **FR-005**: Right Command MUST stay hold-to-dictate for Murmur. Its tap MUST stay optional and off by default.
- **FR-006**: A describe request MUST speak the answer and show a numbered mark on each referenced item.
- **FR-007**: A where-to-click request MUST fly a drawn pointer to the control's real frame and highlight it while speech names it. Reduce Motion MUST fade the highlight in instead of flying.
- **FR-008**: A walk-through MUST show one step at a time and advance on a Right Option tap or when the step is done.
- **FR-009**: Pointer and marks MUST stay in sync with the speech that names them.
- **FR-010**: Marks MUST use the control's display, including a non-main display, and that display's backing scale.
- **FR-011**: The overlay MUST be click-through for the pointer and the marks, MUST exist only during an explain turn, and MUST be torn down when the turn ends. This slice MUST NOT open any other new window.
- **FR-012**: A click Zeus performs for the person MUST go through the existing approval gate. A highlight is not a click. Approval timing and the high-risk hold MUST stay as they are.
- **FR-013**: VoiceOver MUST be able to hear listening, send, cancel, empty, error, the current mark number, and the control name, and MUST be able to send and cancel.
- **FR-014**: Loading, empty, error, and recovery MUST be distinct states. Error and cancel MUST return to idle without sending. A later tap MUST be able to start a fresh turn.
- **FR-015**: The top bar's existing visuals and animations MUST be preserved.
- **FR-016**: The slice MUST NOT use private APIs, MUST NOT capture the screen or the microphone without the person's own OS consent, and MUST NOT log audio or transcripts.

### Key Entities

- **Explain turn**: One listen, then a send, cancel, or empty end. Holds the transcript, the step index when walking, and whether the overlay is up.
- **Mark**: A number and a frame on one display, tied to one phrase of the answer.
- **Pointer cue**: The drawn pointer and the highlight for the current control or step. Not the system cursor, and not a click.
- **Step**: One named control in a walk, done either by a tap or by the step's own completion.
- **Approval**: The existing approval card. This slice does not define a new risk model.

## Success Criteria *(mandatory)*

### Measurable Outcomes

Each figure is a p50 on Tony's Mac. The sample is 20 scripted turns of that kind, run on that Mac, using the turn's own timestamps. No room microphone and no screen recording are required for the measurement. A missing timestamp for a turn excludes that turn and the run does not report a p50 until 20 turns have timestamps.

- **SC-001**: First audio is at most 1.2 s. The clock starts when the second Right Option tap commits a non-silent turn. It stops when the first non-silent output buffer is handed to the audio device. The p50 of those 20 intervals is the result.
- **SC-002**: Pointer is at most 1.0 s. The clock starts when the turn commits a control to point at. It stops when the highlight is on that control's frame in the overlay. The p50 of those 20 intervals is the result.
- **SC-003**: Fast action is at most 300 ms. The clock starts when the turn chooses a local action that does not need a model round trip. It stops when that action has started, or when the existing approval card is on screen if the action would click. The p50 of those 20 intervals is the result. The card's own wait is not part of the 300 ms.
- **SC-004**: In all 20 where-to-click turns, every person-initiated click during the overlay reaches the control under it. In all 20 turns that would click for the person, zero clicks happen before the existing approval card allows them.
- **SC-005**: With Reduce Motion on, all 20 pointer turns fade the highlight and none of them move the drawn pointer.
- **SC-006**: A Control-Option hold and a Right Command hold, each tried 20 times at the default settings, still complete the existing talk and dictation turns. Zero of those trials start explain listening.

## Assumptions

- The explain key is Right Option. Choosing a different key is out of this slice.
- "Tap" uses the tap maximum already in `VoiceKeyMachine` for a hold key, 0.3 s. This slice does not add a second tap window.
- The drawn pointer is an overlay mark. It does not warp the system cursor.
- Describe, show, and walk are chosen from the sent transcript. This slice does not add a new grammar beyond those three requests plus an ordinary spoken answer.
- Slice 002, a shared microphone owner and speech-engine registry for Murmur, Scribe, and Zeus, is named only so this slice does not build it. See `specs/002-shared-mic/spec.md`.
- The existing on-screen explanation hold control stays as it is. This slice does not restyle it.
