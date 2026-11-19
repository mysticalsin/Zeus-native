---

description: "Red-first tasks for the shared microphone and speech engine"
---

# Tasks: One microphone, one speech engine

**Input**: Design documents from `/specs/002-shared-mic/`

**Prerequisites**: plan.md, spec.md, and slice 001's hold (release still processes the request)

**Tests**: Required. Each task names the test that is written first and why it fails before the change. The six removals also name the before/after measurement. Do not invent the before numbers.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: US1 through US6

## Phase 1: Setup

- [ ] T001 Create empty suites `Tests/ZeusCoreTests/SharedMicOwnerTests.swift`, `Tests/ZeusCoreTests/ScribeManualOnlyTests.swift`, and `Tests/ZeusAppTests/DictationWarmStartTests.swift`. No production edits.

---

## Phase 2: User Story 1 - Warm microphone (Priority: P1)

**Goal**: Right Option does not cold-start the engine. First captured audio is under 100 ms after the press.

### Tests

- [ ] T002 [P] [US1] Write `aWarmPressDoesNotBuildAnEngine` in `Tests/ZeusCoreTests/SharedMicOwnerTests.swift`. It fails because a Right Option press still has no shared registry, so the test cannot observe a reused engine.
- [ ] T003 [P] [US1] Write `firstCapturedAudioIsUnder100msAfterPress` in `Tests/ZeusAppTests/DictationWarmStartTests.swift`. It fails on the current dictation path, which builds recognizers and engines on use (`Sources/Zeus/Dictation/SpeechEngines.swift` and `DictationController.swift`) instead of stamping a first buffer against a warm clock.

### Implementation

- [ ] T004 [US1] Make T002 and T003 pass. Record the before and after time from press to first buffer on Tony's Mac. The budget is under 100 ms. Do not invent the before number.

**Checkpoint**: A second press builds nothing. The first buffer is inside the budget.

---

## Phase 3: User Story 2 - Six dictation costs (Priority: P1)

**Goal**: Right Command dictates on the shared engine, without the six per-press costs.

Each test is red on the parent because that cost still happens. The implementation task is done only when the after count is zero and the before count is written down from a real run.

### Tests

- [ ] T005 [P] [US2] Write `aDictationDoesNotRebuildTheAudioEngine` in `Tests/ZeusAppTests/DictationWarmStartTests.swift`. It fails while a Right Command press constructs an engine. Measurement: engine builds per dictation, before and after.
- [ ] T006 [P] [US2] Write `captureDoesNotReadAccessibilityOnTheMainThreadFirst` in the same file. It fails while an accessibility read happens on the main thread before the first buffer. Measurement: those reads per dictation, before and after.
- [ ] T007 [P] [US2] Write `buffersDoNotRedrawTheTopBarOnTheMainThread` in the same file. It fails while each buffer schedules a main-thread top bar redraw. Measurement: those redraws per buffer, before and after. The top bar's visuals and animations stay.
- [ ] T008 [P] [US2] Write `aDictationUsesOneRecognizer` in the same file. It fails while `DictationController.swift` can build an `SFSpeechRecognizer` beside the registry. Measurement: recognizers created per dictation, before and after.
- [ ] T009 [P] [US2] Write `aDictationSpawnsNoCommandLineProcess` in the same file. It fails while a dictation starts a process. Measurement: processes spawned per dictation, before and after.
- [ ] T010 [P] [US2] Write `insertionDoesNotUseAFixedSleep` in the same file. It fails while insertion waits on the fixed sleeps in `DictationController.swift` (the 40 ms, 50 ms, 200 ms, and 400 ms waits on that path). Measurement: fixed sleeps taken per insertion, before and after.

### Implementation

- [ ] T011 [US2] Make T005 through T010 pass, one cost at a time, each with its before and after numbers in the implementation notes. Do not delete a sleep or a recognizer without that pair of counts.

**Checkpoint**: All six after counts are zero. The top bar still looks the same.

---

## Phase 4: User Story 3 - Scribe stays manual (Priority: P1)

**Goal**: The same owner, a 10 s prompt, recording only on Tony's tap. Automatic mode is gone.

### Tests

- [ ] T012 [P] [US3] Write `aMeetingSignalShowsAPromptAndDoesNotRecord` in `Tests/ZeusCoreTests/ScribeManualOnlyTests.swift`. It fails because `ScribeAutoStart.swift` still has an automatic mode that can count down and start.
- [ ] T013 [P] [US3] Write `thePromptLeavesAtTenSecondsUnlessTonyTaps` in the same file. It fails because the prompt lifetime is `askTimeout` of 20 s, not 10 s, and a tap is not the only way a recording starts.
- [ ] T014 [P] [US3] Write `thereIsNoAutomaticMode` in the same file. It fails while `ScribeAutoStartMode.automatic` still exists and can record.

### Implementation

- [ ] T015 [US3] Make T012, T013, and T014 pass. Recording uses the shared owner. The 45 s slow-start of a capture already underway stays. Do not add a new automatic path.

**Checkpoint**: No tap, no recording. A tap records. The prompt is 10 s.

---

## Phase 5: User Story 4 - One capture (Priority: P1)

**Goal**: The owner never lends the microphone twice. A Zeus hold during Scribe is mic busy.

### Tests

- [ ] T016 [P] [US4] Write `twoHoldsNeverCaptureTogether` in `Tests/ZeusCoreTests/SharedMicOwnerTests.swift`. It fails because there is no owner, so a Right Option hold and a Right Command hold are not refused against each other.
- [ ] T017 [P] [US4] Write `aTieGoesToZeusAndTheEarlierHoldKeepsTheMic` in the same file. It fails until the owner can say which hold started first, and that a same-instant pair gives the microphone to Zeus.
- [ ] T018 [P] [US4] Write `aZeusHoldDuringScribeDoesNotCaptureOrStopTheRecording` in the same file. It fails until a Scribe recording outranks Right Option: Zeus must not capture, Scribe must keep recording, and the release must process nothing.

### Implementation

- [ ] T019 [US4] Make T016, T017, and T018 pass. Scribe outranks a later hold. Otherwise the earlier hold wins. A tie goes to Zeus.

**Checkpoint**: Scripted overlaps report one capturer. Scribe survives a Zeus hold.

---

## Phase 6: User Story 5 - Partial transcripts (Priority: P2)

**Goal**: The overlay and the proactive turn see partials during the hold. Release processes the final text once.

### Tests

- [ ] T020 [P] [US5] Write `partialsStreamInOrderAndOnlyTheFinalIsProcessed` in `Tests/ZeusCoreTests/SharedMicOwnerTests.swift`. It fails because the engine does not emit partials to a subscriber, so the overlay cannot show them and a partial can be mistaken for a second request.

### Implementation

- [ ] T021 [US5] Make T020 pass. Partials replace one another on the overlay. The release processes the final transcript once.

**Checkpoint**: Two partials, then one processed final.

---

## Phase 7: User Story 6 - Denied, busy, failure (Priority: P2)

**Goal**: The three failures are distinct, announced, and recoverable. Reduce Motion adds no bounce.

### Tests

- [ ] T022 [P] [US6] Write `deniedBusyAndFailureAreDistinctAndAnnounced` in `Tests/ZeusCoreTests/SharedMicOwnerTests.swift`. It fails because those three states are not separate outcomes of the owner, so VoiceOver cannot hear them apart.
- [ ] T023 [P] [US6] Write `aFailureLetsTheNextHoldTryAgain` in the same file. It fails until engine failure stops only that turn and a later hold can capture.
- [ ] T024 [P] [US6] Write `reduceMotionDoesNotAnimateTheMicStates` in `Tests/ZeusAppTests/DictationWarmStartTests.swift`. It fails if a denied, busy, or failure state introduces a moving animation. The top bar's existing motion is unchanged.

### Implementation

- [ ] T025 [US6] Make T022, T023, and T024 pass.

**Checkpoint**: Denied, busy, and failure are spoken and recoverable. Nothing new bounces.

---

## Dependencies & Execution Order

- T001 starts immediately.
- US1 blocks US2, because Murmur joins the warm engine.
- US3 can be written beside US1. It meets the owner in US4.
- US4 waits until the owner exists (T004) and Scribe is manual (T015).
- US5 waits until the engine emits transcripts (US1).
- US6 can be written beside US4.
- Before/after numbers are recorded on the Mac during T004 and T011. A docs head does not contain them.

### Within each story

- The tests are committed red before the implementation task.
- A removal without its before and after count is not done.

## Implementation Strategy

1. Owner and warm engine, red then green.
2. The six dictation costs, one red test and one measurement each.
3. Scribe manual-only.
4. Arbitration, including the Zeus hold during a recording.
5. Partials, then the three failure states.

Slice 001 is not reimplemented here. This list only supplies the microphone and the engine under that hold.
