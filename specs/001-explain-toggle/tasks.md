---

description: "Red-first tasks for Explain slice 001"
---

# Tasks: Explain toggle, then show and point

**Input**: Design documents from `/specs/001-explain-toggle/`

**Prerequisites**: plan.md, spec.md

**Tests**: Required. Each behavior task lists the test that is written first and why it fails before the implementation.

**Organization**: Tasks are grouped by user story. Implementation of a story starts only after that story's tests are red.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (US1 through US7)

## Phase 1: Setup

**Purpose**: Name the test files. No production behavior.

- [ ] T001 Create `Tests/ZeusCoreTests/ExplainToggleTests.swift` and `Tests/ZeusAppTests/ExplainOverlayTests.swift` as empty Swift Testing suites. No production file changes.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: The pure turn values every story asserts. No gesture and no overlay yet.

**Critical**: No user story implementation starts until these tests exist and fail for lack of the type.

- [ ] T002 [US1] Write `explainTurnStartsIdleAndNamesListenSendCancelEmptyAndError` in `Tests/ZeusCoreTests/ExplainToggleTests.swift`. It fails because no explain-turn type exists yet. The test requires the idle, listening, loading, empty, error, and recovery states from FR-014, and a single open turn.

**Checkpoint**: The red test names the states. The type that satisfies it comes with US1, not before the test is red.

---

## Phase 3: User Story 1 - Right Option tap toggles listening (Priority: P1)

**Goal**: A lone Right Option tap toggles listening and does not fire as a modifier or through a click. Control-Option hold-to-talk stays.

**Independent Test**: Synthetic key and click events only.

### Tests for User Story 1

- [ ] T003 [P] [US1] Write `aRightOptionTapAloneTogglesListening` in `Tests/ZeusCoreTests/ExplainToggleTests.swift`. It fails on this branch: Right Option is the 0.25 s hold second talk key, and a tap inside 0.3 s does not enter explain listening.
- [ ] T004 [P] [US1] Write `rightOptionDoesNotToggleWhenAnotherKeyOrAClickHappensWhileItIsDown` in the same file. It fails once a toggle exists that treats every Right Option release as a tap. Land it in the same red commit as T003.
- [ ] T005 [P] [US1] Write `controlOptionHoldToTalkIsUnchanged` in the same file. It asserts the current Control-Option hold still starts and sends a talk turn and does not enter explain listening. It fails if US1's implementation moves that chord.

### Implementation for User Story 1

- [ ] T006 [US1] Make T003, T004, and T005 pass in the existing Right Option path (`Sources/Zeus/Voice/HotkeyMonitor.swift` and the ZeusCore key machine it drives). Do not change the 0.3 s tap maximum, the Control-Option confirm, or the top bar.

**Checkpoint**: A lone tap listens. A modifier or a click does not. Control-Option still talks.

---

## Phase 4: User Story 1b - Send, cancel, and silence (Priority: P1)

**Goal**: The second tap sends, Esc cancels, and silence never sends.

**Independent Test**: The same pure turn, with a synthetic transcript or an empty one.

### Tests

- [ ] T007 [P] [US1] Write `aSecondRightOptionTapSendsAndEscapeCancels` in `Tests/ZeusCoreTests/ExplainToggleTests.swift`. It fails because a second tap is not a send and Esc is not an explain cancel.
- [ ] T008 [P] [US1] Write `silenceNeverSends` in the same file. It fails if a second tap on an empty capture still produces a request.

### Implementation

- [ ] T009 [US1] Make T007 and T008 pass. A send with words commits one turn. A send of silence ends empty and requests nothing. Esc returns to idle without sending.

**Checkpoint**: Listen, send, cancel, and empty are distinct.

---

## Phase 5: User Story 2 - Describe what is on screen (Priority: P1)

**Goal**: "Describe what's on my screen" speaks and puts a numbered mark on each named item.

**Independent Test**: A scripted transcript and a synthetic screen of three controls. No live capture.

### Tests

- [ ] T010 [P] [US2] Write `describeTheScreenSpeaksAndNumbersEachNamedItem` in `Tests/ZeusCoreTests/ExplainToggleTests.swift`. It fails because a describe transcript does not produce numbered marks tied to the named controls.
- [ ] T011 [P] [US2] Write `speechCallsOutTheMatchingMarkNumber` in the same file. It fails because mark 2 is not the one selected while the answer names item 2.
- [ ] T012 [P] [US2] Write `aDescriptionThatNamesNothingDrawsNoMarks` in the same file. It fails if an empty answer still opens marks.

### Implementation

- [ ] T013 [US2] Make T010, T011, and T012 pass in the explain turn. Marks are data here. Drawing them is US5.

**Checkpoint**: A describe answer has one numbered mark per named item, or no marks.

---

## Phase 6: User Story 3 - Show where to click (Priority: P1)

**Goal**: "Show me where to click to X" flies a drawn pointer to the real control and highlights it while it is named. Reduce Motion fades instead.

**Independent Test**: A scripted control frame. No click is delivered.

### Tests

- [ ] T014 [P] [US3] Write `showWhereToClickFliesThePointerAndHighlightsWhileNamed` in `Tests/ZeusCoreTests/ExplainToggleTests.swift`. It fails because a where-to-click transcript does not commit that control's frame as the pointer target for the duration of the naming phrase.
- [ ] T015 [P] [US3] Write `reduceMotionFadesTheHighlightInsteadOfFlying` in the same file. It fails because the pointer cue has no fade path, so a Reduce Motion turn would still be a flight.
- [ ] T016 [P] [US3] Write `anUnseenControlDoesNotFlyAndDoesNotClick` in the same file. It fails if a missing control still gets a target frame.

### Implementation

- [ ] T017 [US3] Make T014, T015, and T016 pass. The cue is a target and a motion choice. The overlay that draws it is US5. No system-cursor warp.

**Checkpoint**: Point, fade, or refuse. Never a guessed frame, never a click.

---

## Phase 7: User Story 4 - Walk through a task (Priority: P1)

**Goal**: "Walk me through X" shows one step. The next step starts on a tap or when the step is done.

**Independent Test**: Three synthetic steps. No click on the person's behalf.

### Tests

- [ ] T018 [P] [US4] Write `aWalkShowsOnlyTheCurrentStep` in `Tests/ZeusCoreTests/ExplainToggleTests.swift`. It fails because a walk transcript does not keep a step index or hide the later steps.
- [ ] T019 [P] [US4] Write `aTapOrAFinishedStepAdvancesTheWalk` in the same file. It fails because a Right Option tap during a walk does not advance, and a finished step does not advance on its own.
- [ ] T020 [P] [US4] Write `escapeOrTheLastStepEndsTheWalk` in the same file. It fails because Esc and the last step do not both return the turn to idle with no further step.

### Implementation

- [ ] T021 [US4] Make T018, T019, and T020 pass. A tap during a walk advances. It does not open a second listen and it does not send the whole walk again.

**Checkpoint**: One step visible. Tap or completion moves forward. Esc stops.

---

## Phase 8: User Story 5 - Overlay, displays, sync, and approval (Priority: P1)

**Goal**: One click-through overlay, in sync with speech, correct on every display, torn down with the turn. A click for the person still waits for approval.

**Independent Test**: App-side tests with synthetic screens. The approval assertion uses the existing approval path.

### Tests

- [ ] T022 [P] [US5] Write `theOverlayExistsOnlyDuringTheTurnAndClicksPassThrough` in `Tests/ZeusAppTests/ExplainOverlayTests.swift`. It fails because no explain overlay is created for a turn, so there is nothing to tear down, and a click-through flag is not set. The test also fails if a second new window appears.
- [ ] T023 [P] [US5] Write `pointerAndMarksMatchThePhraseOnEveryDisplayAndScale` in the same file. It fails because a mark is not placed on a non-main display's frame at that display's backing scale while the phrase names it.
- [ ] T024 [P] [US5] Write `aClickForThePersonWaitsForTheExistingApprovalCard` in the same file. It fails if the turn can click before the existing approval card allows it. A highlight alone must not click.
- [ ] T025 [P] [US5] Write `theLatencyClocksMatchTheSpec` in `Tests/ZeusCoreTests/ExplainToggleTests.swift`. It fails because the turn does not record the three clocks in spec.md SC-001, SC-002, and SC-003. The test checks the clock definitions, not a p50 measured on this host.

### Implementation

- [ ] T026 [US5] Make T022, T023, T024, and T025 pass. One overlay, `ignoresMouseEvents` for the whole turn, frames from the control's screen, torn down on every end. The click path calls the existing approval card and does not add a gate. The p50 run on Tony's Mac is a later measurement, not this task.

**Checkpoint**: Marks and the pointer are visible only during the turn, on the right display, and they do not eat clicks. Approval is unchanged.

---

## Phase 9: User Story 6 - Right Command stays hold to dictate (Priority: P2)

**Goal**: Murmur's Right Command hold stays. Its tap stays off.

**Independent Test**: Default settings, synthetic Right Command events.

### Tests

- [ ] T027 [P] [US6] Write `rightCommandHoldStillDictatesAndItsTapDoesNotExplain` in `Tests/ZeusCoreTests/ExplainToggleTests.swift`. It fails if the Right Option work makes a Right Command tap start explain listening, or if a Right Command hold no longer dictates. On this branch the hold path is the one that must still pass after US1.

### Implementation

- [ ] T028 [US6] Make T027 pass without adding a setting control and without turning the optional tap on.

**Checkpoint**: Dictation and explain do not share a tap.

---

## Phase 10: User Story 7 - VoiceOver, loading, error, and recovery (Priority: P2)

**Goal**: The same outcomes are announced, and a failed or loading engine does not send.

**Independent Test**: Scripted VoiceOver actions and a scripted engine that is loading, then failing.

### Tests

- [ ] T029 [P] [US7] Write `voiceOverHearsListenSendCancelEmptyErrorAndTheMark` in `Tests/ZeusAppTests/ExplainOverlayTests.swift`. It fails because listening, send, cancel, empty, error, the mark number, and the control name are not announced, and VoiceOver cannot send or cancel.
- [ ] T030 [P] [US7] Write `loadingDoesNotListenAndErrorRecoversOnTheNextTap` in `Tests/ZeusCoreTests/ExplainToggleTests.swift`. It fails because a tap while the engine is loading can be mistaken for listening, and an error does not return to idle ready for a fresh tap with nothing sent.

### Implementation

- [ ] T031 [US7] Make T029 and T030 pass. Announcements name the state in words. Loading, error, and recovery match FR-013 and FR-014.

**Checkpoint**: VoiceOver can finish a turn. A broken engine cannot send.

---

## Phase 11: Polish

**Purpose**: Prove the preserved surfaces and leave the measured p50 for Tony's Mac.

- [ ] T032 [P] Record, in the implementation PR, that the top bar files were not part of the diff, and that the existing explanation hold control's tests still pass. This task does not restyle either surface.
- [ ] T033 Run the 20-turn p50 samples for SC-001, SC-002, and SC-003 on Tony's Mac and attach the timestamps. Until that run exists, the latency targets stay unmeasured. Do not invent the medians.

---

## Dependencies & Execution Order

### Phase Dependencies

- Setup (T001) starts immediately.
- Foundational (T002) is red before any story implementation.
- US1 (T003 to T006) blocks US1b and every overlay story, because there is no turn without the tap.
- US1b (T007 to T009) blocks describe, point, and walk, because those start from a send.
- US2, US3, and US4 can proceed in parallel after US1b.
- US5 draws US2, US3, and US4, so it follows their data tests.
- US6 can proceed in parallel with US1 and must be re-run after T006.
- US7 follows US1b and US5.
- T033 waits for a Mac. It does not block the red tests.

### Within Each User Story

- Tests are committed red, with the assertion that fails on the parent, before the implementation task.
- A story's implementation task is done only when its listed tests pass and no earlier story's tests regress.

### Parallel Opportunities

- T003, T004, and T005 are one red commit.
- T010, T011, and T012 can be written together.
- T014, T015, and T016 can be written together.
- T018, T019, and T020 can be written together.
- T022, T023, T024, and T025 can be written together.
- T027 can be written beside T003.

## Implementation Strategy

1. T001 and T002, red.
2. US1 and US1b, red then green. Stop and check Control-Option and Right Command.
3. US2, US3, and US4, red then green, still without a window.
4. US5, the one overlay, red then green.
5. US6 and US7.
6. T033 on Tony's Mac. The docs head is not that measurement.
