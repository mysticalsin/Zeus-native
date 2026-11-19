# Feature Specification: Hold Right Option, then act or explain

**Feature Branch**: `001-explain-toggle`

**Created**: 2026-11-19

**Status**: Draft

**Input**: User description: "Zeus Explain slice 001. Hold Right Option to talk. The overlay is up while it is held. On release, Zeus processes the request. Tony, 2026-11-19 13:03, 13:05, and 13:12 BRT. The 13:12 ruling replaces the tap-to-toggle model."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Hold Right Option to talk (Priority: P1)

Holding Right Option alone starts the turn. While it is held, the overlay is up and the person speaks. Releasing it hands that speech to Zeus, which then acts or explains. The hold does nothing when Right Option is only a modifier, when another key goes down while it is held, or when a click happens while it is held. Esc while it is held cancels the turn, and the later release does not process anything. Control-Option hold-to-talk is unchanged.

**Why this priority**: Without this hold there is no explain turn. Every later scenario starts here.

**Independent Test**: With a synthetic key and click stream and no microphone, holding Right Option alone raises the overlay, and releasing it commits the spoken request. The same hold with another key or a click does not. Esc while held leaves nothing to process. A Control-Option hold still starts and sends the existing talk turn.

**Acceptance Scenarios**:

1. **Given** Zeus is idle, **When** Right Option goes down alone, **Then** the overlay appears and the turn is listening for as long as Right Option stays down.
2. **Given** Right Option is held and the person has spoken, **When** Right Option comes up, **Then** Zeus processes that request. The release is the commit. There is no second tap and no separate send tap.
3. **Given** Right Option is down, **When** any other key goes down before it comes up, **Then** the hold does not start a turn, the overlay is not left up, and the release processes nothing.
4. **Given** Right Option is down, **When** a mouse click happens before it comes up, **Then** the hold does not start a turn and the release processes nothing.
5. **Given** another key is already down, **When** Right Option is held, **Then** it is only a modifier. Listening does not start.
6. **Given** Right Option is held and the overlay is up, **When** Esc is pressed, **Then** the turn cancels, the overlay goes away, and releasing Right Option afterwards processes nothing.
7. **Given** the existing Control-Option hold-to-talk chord, **When** it is held and released as it is today, **Then** that talk turn still starts and sends. This slice does not change its confirm, chord, or hands-free rules.

---

### User Story 2 - Open, close, and explain on release (Priority: P1)

Zeus acts on the request as soon as the hold ends. A spoken command can open something, close something, or explain something, and each of those has visuals that match the words. It does not wait for a second prompt to do the thing that was just asked.

**Why this priority**: The hold is useful only if the release does the thing that was said.

**Independent Test**: Three scripted holds, each released with one transcript, against a synthetic screen. No live microphone.

**Acceptance Scenarios**:

1. **Given** Right Option is held, **When** the person says to open a named application and releases, **Then** that application opens. The words are generic: the test names a fixture application, not a product.
2. **Given** Right Option is held, **When** the person says to close a named application and releases, and closing it would not lose unsaved work, **Then** that application closes.
3. **Given** closing the named application would lose unsaved work, **When** the release would close it, **Then** the existing approval or confirm gate is shown and the application stays open until that gate allows the close.
4. **Given** Right Option is held, **When** the person says "explain this" and releases, **Then** Zeus answers out loud and puts a numbered mark on each relevant on-screen element.
5. **Given** any of these three, **When** the result is showing, **Then** the visuals match the command: an open shows the opened application, a close shows it gone, and an explanation shows the numbered marks while the answer is spoken.

---

### User Story 3 - Describe what is on screen (Priority: P1)

The person asks, in speech during the hold, what is on the screen. After the release, Zeus answers in speech and puts a numbered mark on each item the answer names.

**Why this priority**: A spoken answer with no marks does not show which item was meant.

**Independent Test**: A hold whose transcript is "Describe what's on my screen", released against a synthetic screen of three controls, produces one spoken answer and three numbered marks, and no click.

**Acceptance Scenarios**:

1. **Given** a hold whose transcript asks to describe the screen, **When** Right Option is released and the answer names items, **Then** the spoken answer and a numbered mark on each referenced item appear together.
2. **Given** those marks, **When** speech names item 2, **Then** mark 2 is the one called out, and the other marks stay visible and numbered.
3. **Given** the answer names nothing on screen, **Then** there are no marks and the spoken answer says so.

---

### User Story 4 - Show where to click (Priority: P1)

The person asks, during the hold, where to click to do something. After the release, a drawn pointer flies to the real on-screen control and highlights it while the speech names it.

**Why this priority**: The point of the turn is to land on the control, not to describe it from memory.

**Independent Test**: A hold whose transcript is "Show me where to click to X", released against a synthetic control frame, moves the drawn pointer to that frame and highlights it while the speech names it. No click is delivered.

**Acceptance Scenarios**:

1. **Given** a hold whose transcript asks where to click to do X, **When** Right Option is released and the control is on screen, **Then** the drawn pointer moves to that control and the highlight is on its real frame while the speech names it.
2. **Given** the pointer is in flight, **When** the person clicks the real control, **Then** the click reaches that control. The overlay does not take it.
3. **Given** Reduce Motion is on, **When** the same request runs, **Then** the flight is a fade of the highlight onto the control, not a moving pointer.
4. **Given** the control is not on screen, **Then** the pointer does not fly to a guess, the speech says it cannot see the control, and no click happens.

---

### User Story 5 - Walk through a task (Priority: P1)

The person asks, during the hold, to be walked through a task. After the release, Zeus shows one step at a time. The next step starts when the person taps, or when that step is done. That later tap only advances a walk that is already running. It is not how a turn starts.

**Why this priority**: A single highlight cannot carry a sequence.

**Independent Test**: A hold whose transcript is "Walk me through X", released with three synthetic steps, shows step 1 only, advances to step 2 on a Right Option tap, and advances to step 3 when step 2 is marked done, without a click on the person's behalf.

**Acceptance Scenarios**:

1. **Given** a walk of more than one step, **When** it starts after the release, **Then** only the current step's pointer and highlight are shown, and the speech names that step.
2. **Given** a step is showing, **When** Right Option taps, **Then** the next step shows and the previous highlight leaves.
3. **Given** a step is showing, **When** that step is done, **Then** the next step shows without waiting for a tap.
4. **Given** the last step is done, **When** nothing remains, **Then** the walk ends, the overlay is torn down, and Zeus is idle.
5. **Given** a walk is in progress, **When** Esc is pressed, **Then** the walk cancels, the overlay is torn down, and no later step runs.

---

### User Story 6 - Pointer, marks, displays, and clicks (Priority: P1)

Pointer and marks stay in time with the speech. They work on any display, including more than one display and Retina scaling. They never block clicks. A click Zeus would make for the person still waits for the existing approval gate.

**Why this priority**: A mark on the wrong display, or a click that skips approval, is a wrong turn.

**Independent Test**: The same scripted point is checked on a main display and a second display at a non-1 backing scale. The overlay hit test is empty. A scripted request that Zeus click for the person presents the existing approval card and does not click before that card allows it.

**Acceptance Scenarios**:

1. **Given** speech is naming a control, **When** the audio clock is at that phrase, **Then** the pointer and the highlight are on that control, not on the previous or next one.
2. **Given** the control is on a display that is not the main display, **When** the turn points at it, **Then** the mark uses that display's frame.
3. **Given** the display's backing scale is not 1, **When** the mark is drawn, **Then** it sits on the control's point frame, not on a 1x mis-scale of that frame.
4. **Given** the overlay is up, **When** the person clicks, drags, or types, **Then** the event reaches the app under the overlay.
5. **Given** the turn would click a control for the person, **When** that click is risky, **Then** the existing approval card is presented and the click does not happen until that card allows it. Highlighting is not a click.
6. **Given** the turn ends by a finished result, cancel, error, or the last walk step, **When** the turn leaves, **Then** the overlay and every mark are gone. No other new window was opened during the turn.

---

### User Story 7 - Right Command stays hold to dictate (Priority: P2)

Right Command stays hold-to-dictate for Murmur. A tap of Right Command is optional and off by default. This slice does not turn that tap on.

**Why this priority**: Explain must not steal dictation.

**Independent Test**: With the default settings, a Right Command hold still dictates and a Right Command tap does not start an explain hold.

**Acceptance Scenarios**:

1. **Given** default settings, **When** Right Command is held and released as Murmur does today, **Then** dictation still runs and an explain hold does not start.
2. **Given** default settings, **When** Right Command taps, **Then** an explain hold does not start and Murmur does not send.
3. **Given** the optional Right Command tap setting is off, **When** the setting is read, **Then** it is off. This slice does not add a control that turns it on.

---

### User Story 8 - VoiceOver, loading, error, and recovery (Priority: P2)

The same actions are available to VoiceOver. Loading, error, and recovery are spoken and visible as states, not only as color.

**Why this priority**: A gesture-only turn leaves VoiceOver and a failed engine with no way through.

**Independent Test**: A VoiceOver action list on the explain status includes hold, cancel, and the result. A scripted engine failure moves to error, speaks the failure, tears the overlay down, and a later Right Option hold starts a new turn.

**Acceptance Scenarios**:

1. **Given** VoiceOver is on, **When** a hold starts, a release processes, or Esc cancels while held, **Then** an announcement says which of those happened, including the mark number and the control name when a mark or pointer is showing.
2. **Given** the speech engine is not ready, **When** Right Option is held, **Then** the state is loading, the overlay does not pretend a request was captured, and the release processes nothing.
3. **Given** loading finishes ready, **When** the person holds Right Option again, **Then** listening starts and the overlay appears.
4. **Given** the engine fails during a turn, **When** the failure is reported, **Then** the state is error, the overlay is gone, nothing is processed, and the announcement names the failure.
5. **Given** error or cancel, **When** Right Option is held alone after that, **Then** a new turn starts. The failed turn cannot process later.

---

### Edge Cases

- A repeat of the Right Option key-down while a hold is already listening does not start a second turn.
- Two explain turns cannot be open. Control-Option and Right Option do not run two turns at once. The existing one-turn rule across the talk keys stays.
- A walk that is already running still advances on a Right Option tap or when the step is done. That tap does not start a new hold.
- A walk with an empty step list does not open a result overlay.
- A display going away mid-flight tears that mark down and the speech says the control is gone. It does not leave a highlight on a stale frame.
- Reduce Motion does not change when the hold starts, when the release processes, or when approval is required. It only replaces the pointer flight with a fade.
- The top bar's existing visuals, springs, and animations are not part of this slice. They keep their current motion, including their own Reduce Motion behavior.
- The 13:03 tap-to-toggle model is withdrawn. A tap does not start listening, a second tap does not send, and this slice does not add a silence rule.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: Holding Right Option alone MUST start an explain turn. While it is held, the overlay MUST be up and the turn MUST be listening. Releasing it MUST process the request that was spoken.
- **FR-002**: The hold MUST NOT fire when Right Option is used as a modifier, when another key goes down while it is held, or when a click happens while it is held. The release after any of those MUST process nothing.
- **FR-003**: Esc while Right Option is held MUST cancel the turn and tear the overlay down. The release after that cancel MUST process nothing.
- **FR-004**: Control-Option hold-to-talk MUST stay on its current rules.
- **FR-005**: Right Command MUST stay hold-to-dictate for Murmur. Its tap MUST stay optional and off by default.
- **FR-006**: On release, a request to open a named application MUST open it. A request to close one MUST close it. If that close would lose unsaved work, the existing approval or confirm gate MUST apply and the close MUST wait. A request to explain this MUST be answered out loud with a numbered mark on each relevant on-screen element.
- **FR-007**: Zeus MUST act on the spoken request when the hold ends. Open, close, and explain each MUST have visuals that match the words. The turn MUST NOT wait for a second prompt to do what was just asked.
- **FR-008**: A describe request MUST speak the answer and show a numbered mark on each referenced item.
- **FR-009**: A where-to-click request MUST fly a drawn pointer to the control's real frame and highlight it while speech names it. Reduce Motion MUST fade the highlight in instead of flying.
- **FR-010**: A walk-through MUST show one step at a time and advance on a Right Option tap or when the step is done. That tap advances the walk. It does not start a hold.
- **FR-011**: Pointer and marks MUST stay in sync with the speech that names them.
- **FR-012**: Marks MUST use the control's display, including a non-main display, and that display's backing scale.
- **FR-013**: The overlay MUST be click-through, MUST be up for the hold and for the result that follows, and MUST be torn down when the turn ends. This slice MUST NOT open any other new window.
- **FR-014**: A click Zeus performs for the person MUST go through the existing approval gate. A highlight is not a click. Approval timing and the high-risk hold MUST stay as they are.
- **FR-015**: VoiceOver MUST be able to hear hold, release, cancel, the current mark number, and the control name, and MUST be able to cancel a hold.
- **FR-016**: Loading, error, and recovery MUST be distinct states. Error and cancel MUST return to idle without processing. A later hold MUST be able to start a fresh turn.
- **FR-017**: The top bar's existing visuals and animations MUST be preserved.
- **FR-018**: The slice MUST NOT use private APIs, MUST NOT capture the screen or the microphone without the person's own OS consent, and MUST NOT log audio or transcripts.

### Key Entities

- **Explain turn**: One hold, then a release that processes, or a cancel. Holds the transcript, the step index when walking, and whether the overlay is up.
- **Mark**: A number and a frame on one display, tied to one phrase of the answer.
- **Pointer cue**: The drawn pointer and the highlight for the current control or step. Not the system cursor, and not a click.
- **Step**: One named control in a walk, done either by a tap during the walk or by the step's own completion.
- **Approval**: The existing approval or confirm gate. This slice does not define a new risk model. A close that would lose unsaved work uses that gate. A click Zeus would perform uses it too.

## Success Criteria *(mandatory)*

### Measurable Outcomes

Each figure is a p50 on Tony's Mac. The sample is 20 scripted turns of that kind, run on that Mac, using the turn's own timestamps. No room microphone and no screen recording are required for the measurement. A missing timestamp for a turn excludes that turn and the run does not report a p50 until 20 turns have timestamps.

- **SC-001**: First audio is at most 1.2 s. The clock starts when Right Option is released on a hold whose request asks Zeus to speak. It stops when the first non-silent output buffer is handed to the audio device. The p50 of those 20 intervals is the result.
- **SC-002**: Pointer is at most 1.0 s. The clock starts when the turn commits a control to point at. It stops when the highlight is on that control's frame in the overlay. The p50 of those 20 intervals is the result.
- **SC-003**: Fast action is at most 300 ms. The clock starts when the turn chooses a local action that does not need a model round trip, including an open or a close that needs no gate. It stops when that action has started, or when the existing approval or confirm gate is on screen if the action must wait. The p50 of those 20 intervals is the result. The gate's own wait is not part of the 300 ms.
- **SC-004**: In all 20 where-to-click turns, every person-initiated click during the overlay reaches the control under it. In all 20 turns that would click for the person, zero clicks happen before the existing approval card allows them.
- **SC-005**: With Reduce Motion on, all 20 pointer turns fade the highlight and none of them move the drawn pointer.
- **SC-006**: A Control-Option hold and a Right Command hold, each tried 20 times at the default settings, still complete the existing talk and dictation turns. Zero of those trials start an explain hold.

## Assumptions

- The explain key is Right Option. Choosing a different key is out of this slice.
- The overlay appears on the key-down of a clean Right Option hold and stays through the result. A modifier, another key, or a click means the hold never became a turn.
- The drawn pointer is an overlay mark. It does not warp the system cursor.
- Open, close, explain, describe, show, and walk are chosen from the speech captured during the hold. The tests use fixture names for applications. This slice does not name a third-party application.
- A walk that is already on screen still advances on a tap. That is the only tap in this slice.
- Slice 002, a shared microphone owner and speech-engine registry for Murmur, Scribe, and Zeus, is named only so this slice does not build it. See `specs/002-shared-mic/spec.md`.
- The existing on-screen explanation hold control stays as it is. This slice does not restyle it.
