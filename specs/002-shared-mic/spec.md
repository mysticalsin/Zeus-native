# Feature Specification: One microphone, one speech engine

**Feature Branch**: `002-shared-mic`

**Created**: 2026-11-19

**Status**: Draft

**Input**: User description: "One shared microphone owner and speech-engine registry for Murmur, Scribe, and Zeus. Tony, 2026-11-19. Aligned with the Explain hold: Right Option talks, Right Command dictates, Scribe stays manual."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - The microphone is already warm (Priority: P1)

Zeus talks by holding Right Option. The microphone and the speech engine are already running before that press. The press does not cold-start them. The first captured audio is under 100 ms after the press.

**Why this priority**: A cold start makes the beginning of the sentence disappear.

**Independent Test**: With the shared engine already warm and a synthetic capture clock, the timestamp of the first captured buffer minus the Right Option key-down is under 100 ms. A second hold does not construct another engine.

**Acceptance Scenarios**:

1. **Given** Zeus is idle and the shared engine is warm, **When** Right Option goes down, **Then** capture is already running and the first buffer is marked less than 100 ms after the press.
2. **Given** the engine is warm, **When** Right Option is held again later, **Then** no new engine is built for that press.
3. **Given** the engine is not warm yet, **When** Right Option is held, **Then** the turn is the loading state from slice 001 and the release does not process a request that was never captured.

---

### User Story 2 - Murmur uses the same engine (Priority: P1)

Holding Right Command dictates with Murmur on the same shared engine. The press does not rebuild an audio engine, read accessibility on the main thread before capture, redraw the top bar on the main thread for every buffer, start a second speech recognizer, spawn a command-line process per dictation, or sleep a fixed time while inserting text.

**Why this priority**: Those six costs are the reason dictation feels late. They are not six engines.

**Independent Test**: A scripted Right Command hold records, for each of the six, a count and a time before the change and after it. The after count for rebuilds, main-thread accessibility reads before capture, per-buffer main-thread top bar redraws, extra recognizers, command-line spawns, and fixed insertion sleeps is zero.

**Acceptance Scenarios**:

1. **Given** a Right Command hold, **When** capture starts, **Then** the audio engine already in the registry is used. The press builds none.
2. **Given** a Right Command hold, **When** capture starts, **Then** no accessibility read runs on the main thread before the first buffer.
3. **Given** buffers are arriving, **When** the top bar shows level, **Then** it does not redraw on the main thread once per buffer.
4. **Given** a dictation, **When** speech is recognized, **Then** one recognizer from the registry is used. A second recognizer is not created for that dictation.
5. **Given** a dictation, **When** it runs, **Then** no command-line process is spawned for that dictation.
6. **Given** recognized text is inserted, **When** the insertion runs, **Then** it does not wait on a fixed sleep.

---

### User Story 3 - Scribe is manual and uses the same owner (Priority: P1)

Scribe takes the microphone from the same owner. It stays manual. A prompt can appear for 10 s. Recording starts only when Tony taps. Nothing starts a recording by itself. The leftover automatic mode is gone.

**Why this priority**: An automatic recording would take the shared microphone without a tap.

**Independent Test**: A scripted meeting signal shows the prompt and does not record. A tap records. The prompt is gone at 10 s if it was not tapped. No mode remains that counts down and records on its own.

**Acceptance Scenarios**:

1. **Given** a meeting signal and the manual choice, **When** the prompt appears, **Then** the microphone is not captured until Tony taps.
2. **Given** the prompt is up, **When** Tony taps it, **Then** Scribe records through the shared owner.
3. **Given** the prompt is up and Tony does not tap, **When** 10 s pass, **Then** the prompt leaves and no recording starts.
4. **Given** the old automatic choice, **When** the same signal arrives, **Then** there is no countdown and no recording. That mode is not offered.

The 45 s slow-start of a capture that has already begun, and any other timeout this slice does not name, stay as they are.

---

### User Story 4 - Only one capture (Priority: P1)

Zeus, Murmur, and Scribe never capture at the same time. The owner has one order. A Zeus hold during a Scribe recording is defined and does not open a second capture.

**Why this priority**: Two captures on one microphone drop audio for both.

**Independent Test**: Scripted overlaps. At every instant the owner reports at most one capturer.

**Acceptance Scenarios**:

1. **Given** nobody is capturing, **When** Right Option or Right Command is held, **Then** that hold captures and the other does not.
2. **Given** one of Zeus or Murmur is already capturing, **When** the other key is held, **Then** the second hold does not capture. The state is mic busy. The first capture continues.
3. **Given** both keys go down at the same instant and Scribe is not recording, **When** the owner chooses, **Then** Zeus takes the microphone and Murmur does not capture.
4. **Given** Scribe is recording, **When** Right Option is held, **Then** Zeus does not capture, Scribe keeps recording, and the Zeus hold reports mic busy. Releasing Right Option does not stop Scribe and does not process a Zeus request.
5. **Given** Scribe is recording, **When** Right Command is held, **Then** Murmur does not capture and Scribe keeps recording.
6. **Given** a Zeus or Murmur hold is capturing, **When** Tony taps the Scribe prompt, **Then** Scribe does not start a second capture. The prompt says the microphone is busy. The hold keeps the microphone until it ends. A tap after that hold has ended can start Scribe.

Scribe, once Tony has started it, outranks a later talk or dictation hold. Between Zeus and Murmur, the hold that started first keeps the microphone. A tie goes to Zeus.

---

### User Story 5 - Partial transcripts reach the overlay (Priority: P2)

While Right Option is held, the shared engine streams partial transcripts to the overlay and to the proactive Zeus turn. The turn does not wait for the release to know what is being said. The release still commits the request, as slice 001 says.

**Why this priority**: The overlay and the turn should follow the words as they arrive.

**Independent Test**: A scripted hold emits two partial transcripts and then a final one on release. The overlay shows the partials in order. The processed request is the final text.

**Acceptance Scenarios**:

1. **Given** Right Option is held, **When** the engine emits a partial transcript, **Then** the overlay shows it and the proactive turn can use it.
2. **Given** a later partial arrives, **When** the overlay updates, **Then** it replaces the previous partial. It does not stack a second copy.
3. **Given** Right Option is released, **When** the final transcript arrives, **Then** that final text is what Zeus processes. A partial is not processed as a second request.

---

### User Story 6 - Motion, VoiceOver, and the three failures (Priority: P2)

Reduce Motion and VoiceOver cover the shared owner. Mic denied, mic busy, and engine failure are distinct, announced, and recoverable.

**Why this priority**: A refused microphone that looks like listening will drop the sentence.

**Independent Test**: Scripted denied, busy, and failed engines. Each is announced in words. Reduce Motion does not add a new animation. A later successful hold works after recovery.

**Acceptance Scenarios**:

1. **Given** the microphone permission is denied, **When** Right Option or Right Command is held, **Then** the state is mic denied, nothing is captured, and VoiceOver says the microphone is off.
2. **Given** the owner is busy with another capturer, **When** a hold asks for the microphone, **Then** the state is mic busy, VoiceOver says so, and the current capturer is not stopped.
3. **Given** the engine fails, **When** the failure is reported, **Then** the state is engine failure, capture stops for that turn only, VoiceOver names the failure, and the next hold can try again.
4. **Given** Reduce Motion is on, **When** any of these states appear, **Then** the change is immediate or a short fade. Nothing bounces. The top bar's existing motion is unchanged.

---

### Edge Cases

- A hold that loses the microphone mid-phrase ends as engine failure or mic busy, and the release does not process a partial as if it were complete.
- Scribe's prompt can sit on screen while Zeus or Murmur holds the microphone. The prompt does not capture until a tap, and that tap waits if the hold still has the microphone.
- Removing the automatic mode does not remove the manual prompt, the tap to record, or the 45 s allowance for a capture that has already begun.
- The top bar still shows dictation and recording. It does not gain a per-buffer main-thread redraw.
- Slice 001's overlay rules stay: one click-through overlay, torn down when the Zeus turn ends.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: One microphone owner and one speech-engine registry MUST serve Zeus, Murmur, and Scribe.
- **FR-002**: The engine MUST be warm before a Right Option press. The first captured audio MUST be under 100 ms after that press. The press MUST NOT cold-start the engine.
- **FR-003**: A Right Command hold MUST dictate through that same engine.
- **FR-004**: A dictation MUST NOT rebuild the audio engine, read accessibility on the main thread before capture, redraw the top bar on the main thread per buffer, create a second recognizer, spawn a command-line process, or wait on a fixed insertion sleep.
- **FR-005**: Scribe MUST use the same owner, MUST stay manual, MUST show its prompt for 10 s, and MUST record only after Tony's tap. The automatic mode MUST be removed.
- **FR-006**: At most one of Zeus, Murmur, and Scribe MAY capture at a time. Scribe, once started, outranks a later hold. Otherwise the earlier hold keeps the microphone, and a tie goes to Zeus.
- **FR-007**: A Right Option hold during a Scribe recording MUST NOT capture, MUST NOT stop Scribe, and MUST NOT process a Zeus request on release. It MUST report mic busy.
- **FR-008**: Partial transcripts MUST stream to the Zeus overlay and the proactive turn during the hold. Only the final transcript on release is processed.
- **FR-009**: Mic denied, mic busy, and engine failure MUST be distinct, announced to VoiceOver, and recoverable by a later hold. Reduce Motion MUST apply. The top bar's visuals and animations MUST stay.
- **FR-010**: The slice MUST NOT use private APIs, MUST NOT capture without the person's own OS consent, and MUST NOT log audio or transcripts.

### Key Entities

- **Microphone owner**: The single grant of capture. It names the current capturer or says the microphone is free, denied, or busy.
- **Engine registry**: The one warm speech engine. Zeus and Murmur both borrow it. It emits partials and one final.
- **Capturer**: Zeus (Right Option), Murmur (Right Command), or Scribe (after the manual tap).

## Success Criteria *(mandatory)*

### Measurable Outcomes

Measurements use the turn's own timestamps on Tony's Mac. Do not invent a before number. Each removal task records the before count on the parent and the after count on the implementation head.

- **SC-001**: On 20 warm Right Option presses, every first captured buffer is under 100 ms after the press.
- **SC-002**: On 20 Right Command dictations, the after counts are zero for engine rebuilds, main-thread accessibility reads before the first buffer, per-buffer main-thread top bar redraws, extra recognizers, command-line spawns, and fixed insertion sleeps.
- **SC-003**: On 20 meeting signals with no tap, zero recordings start. On 20 taps, 20 recordings start through the shared owner.
- **SC-004**: On 20 scripted overlaps, the owner never reports two capturers. On 20 Zeus holds during a Scribe recording, Scribe is still recording at the end and Zeus processed nothing.

## Assumptions

- Slice 001's hold, release, overlay, and approval rules stay. This slice supplies the microphone and the engine underneath them.
- "Warm" means the engine was started earlier and is idle, not constructed on the key-down.
- The 10 s figure is the manual Scribe prompt. It is not the 45 s slow-start.
- The six removals are measured one by one. A task that only deletes a sleep without a before and after count is not done.
- No third-party application is named. The recognizer and the command-line process are described by what they do.
