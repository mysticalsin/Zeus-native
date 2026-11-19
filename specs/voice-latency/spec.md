# Feature Specification: Voice latency

**Feature Branch**: `zeus-bot/voice-latency`

**Created**: 2026-11-19

**Status**: Draft

**Input**: Right-Command speech-to-text feels far too slow. Any command should feel instant. Measure real stage timings, then hit the stated budgets without dropping the talk cues or the right-Command tap-versus-modifier rule.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - See the real delays (Priority: P1)

A hosted macOS run records how long each stage of a push-to-talk turn takes, using a monotonic clock. The log is durations only.

**Why this priority**: Later speed work is judged against a measured baseline, not a guess.

**Independent Test**: Run the harness on the hosted macOS job. The log line has the stage durations and no audio and no transcript text.

**Acceptance Scenarios**:

1. **Given** listening is enabled, **When** the key goes down and later comes up, **Then** the log records key-down to mic-hot, key-down to the first audio frame, release to the final transcript, transcript to inserted text, and, for a command, recognized to action done.
2. **Given** a turn, **When** the log line is written, **Then** it contains no audio samples and no transcript or command text.

---

### User Story 2 - Dictation is fast enough to feel immediate (Priority: P1)

Holding the talk key transcribes while the key is held. Letting go finishes a short phrase quickly, and the text is inserted at once.

**Why this priority**: This is the delay Tony compared with the dedicated dictation app.

**Independent Test**: The harness on a short synthetic phrase. Budgets below. The model stays resident while listening is enabled. The audio engine and input node stay prepared. A press does not build a new engine.

**Acceptance Scenarios**:

1. **Given** listening is enabled, **When** the key goes down, **Then** the microphone is hot in under 50 ms.
2. **Given** the key is held, **When** audio arrives, **Then** partial text updates while the key is still down.
3. **Given** a short phrase and a warm resident model, **When** the key is released, **Then** the final transcript is ready in under 300 ms.
4. **Given** a final transcript that is dictation, **When** it is inserted, **Then** insertion finishes in under 30 ms.
5. **Given** two holds in one run, **When** the second hold records, **Then** the second hold still receives audio.

---

### User Story 3 - Common commands skip the model (Priority: P2)

"Open Spotify", quit or switch an app, play, pause, skip, volume, open a URL, and focus a window run on a local deterministic path. The language model is only the fallback, and it may start at the same time as the fast-path match.

**Why this priority**: A command should feel instant after the transcript exists.

**Independent Test**: Feed a synthetic final transcript. The fast path performs the action. A sentence that is not one of those intents does not take the fast path.

**Acceptance Scenarios**:

1. **Given** a final transcript that is one of the listed intents, **When** it is recognized, **Then** the action is done in under 100 ms from the final transcript, with no language-model call on that path.
2. **Given** a transcript that is not one of those intents, **When** it is recognized, **Then** the language-model fallback runs, and the fast-path match may already have been tried.

---

### Edge Cases

- Listening disabled: no pre-warmed engine is kept hot.
- Microphone or speech permission missing: the turn does not start, and the existing denial cue remains.
- A right-Command tap still toggles listening. A right-Command hold that is a modifier does not.
- The installed talk cue still plays on hold start and hold end. Reduce Motion does not silence it.
- A second hold in the same process still captures. A pre-warmed engine must not come back silent.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The harness MUST time the stages with a monotonic clock and log durations only.
- **FR-002**: While listening is enabled, the audio engine and input node MUST stay prepared. A press MUST NOT construct a new engine.
- **FR-003**: Partials MUST stream while the key is held.
- **FR-004**: The recognizer MUST stay resident and warm between holds while listening is enabled.
- **FR-005**: The fast path MUST cover open, quit, and switch app (workspace plus bundle id), play, pause, skip, volume, open a URL, and focus a window. Anything else goes to the language model.
- **FR-006**: The fast-path match MUST be allowed to run at the same time as the language-model fallback. A fast-path hit MUST NOT wait for the model.
- **FR-007**: Talk cue sounds and the right-Command tap-versus-modifier rule MUST stay.

### Key Entities

- **Dictation latency trace**: stage durations for one turn. No audio. No text.
- **Fast-path intent**: one of the listed local actions, or none.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Mic hot under 50 ms.
- **SC-002**: Final transcript under 300 ms after release for a short phrase with a warm model.
- **SC-003**: Insertion under 30 ms.
- **SC-004**: Fast-path action under 100 ms from the final transcript.
- **SC-005**: Baseline table from the hosted macOS run. No estimated numbers.

### Measured baseline

Not measured. The hosted macOS job has not run this harness. The table stays empty until that log exists.

| Stage | Baseline | Target |
| --- | --- | --- |
| Key down to mic hot | unmeasured | < 50 ms |
| Key down to first audio frame | unmeasured | recorded |
| Release to final transcript | unmeasured | < 300 ms |
| Transcript to text inserted | unmeasured | < 30 ms |
| Command recognized to action done | unmeasured | < 100 ms |

## Assumptions

- "Short phrase" means a few words, not a long dictation.
- The on-device recognizer is the one already used for push-to-talk.
- Linux cannot produce the baseline. Only the hosted macOS job can.

## Open questions

- Which existing cue file is the one that must play, if both the installed cue and the built-in listen sound would otherwise both fire? This spec keeps the installed cue and does not add a second sound on that path.
- Is "focus a window" limited to windows Zeus already knows, or any window the system can name? Not specified. The fast path will not guess a window it cannot identify locally.
- The 10-20x comparison has no measured "before" from the dedicated app. The targets above are the acceptance bar. The baseline column is Zeus's own harness, once the hosted run exists.
