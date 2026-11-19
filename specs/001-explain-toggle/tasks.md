---

description: "Red-first tasks for Explain slice 001"
---

# Tasks: Hold Right Option, then act or explain

**Input**: Design documents from `/specs/001-explain-toggle/`

**Prerequisites**: plan.md, spec.md

**Tests**: Required. Each behavior task lists the test that is written first and why it fails before the implementation. Tony's 13:12 ruling replaced the tap-to-toggle model. Do not add a test that a second tap sends, or that silence never sends.

**Organization**: Tasks are grouped by user story. Implementation of a story starts only after that story's tests are red.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (US1 through US8)

## Phase 1: Setup

**Purpose**: Name the test files. No production behavior.

- [ ] T001 Create `Tests/ZeusCoreTests/ExplainToggleTests.swift` and `Tests/ZeusAppTests/ExplainOverlayTests.swift` as empty Swift Testing suites. No production file changes.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: The pure turn values every story asserts. No gesture and no overlay yet.

**Critical**: No user story implementation starts until this test exists and fails for lack of the type.

- [ ] T002 [US1] Write `explainTurnIsIdleUntilACleanHold` in `Tests/ZeusCoreTests/ExplainToggleTests.swift`. It fails because no explain-turn type exists yet. The test requires idle, holding, processing, loading, error, and recovery, one open turn, and no tap-to-toggle state.

**Checkpoint**: The red test names the states. The type that satisfies it comes with US1, not before the test is red.

---

## Phase 3: User Story 1 - Hold Right Option to talk (Priority: P1)

**Goal**: A clean Right Option hold raises the overlay and listens. Release processes the request. Another key, a click, or Esc while held means the release processes nothing. Control-Option hold-to-talk stays.

**Independent Test**: Synthetic key and click events only.

### Tests for User Story 1

- [ ] T003 [P] [US1] Write `holdingRightOptionAloneShowsTheOverlayAndReleaseProcesses` in `Tests/ZeusCoreTests/ExplainToggleTests.swift`. It fails on this branch: Right Option is the 0.25 s hold second talk key, and holding it does not raise an explain overlay or process on release.
- [ ] T004 [P] [US1] Write `rightOptionDoesNotFireWhenAnotherKeyOrAClickHappensWhileItIsHeld` in the same file. It fails on an implementation that still processes the release after another key or a click. Land it in the same red commit as T003.
- [ ] T005 [P] [US1] Write `escapeWhileRightOptionIsHeldCancelsAndTheReleaseProcessesNothing` in the same file. It fails because Esc during Right Option is not an explain cancel.
- [ ] T006 [P] [US1] Write `controlOptionHoldToTalkIsUnchanged` in the same file. It asserts the current Control-Option hold still starts and sends a talk turn and does not open an explain hold. It fails if US1's implementation moves that chord.

### Implementation for User Story 1

- [ ] T007 [US1] Make T003, T004, T005, and T006 pass in the existing Right Option path (`Sources/Zeus/Voice/HotkeyMonitor.swift` and the ZeusCore key machine it drives). Do not change the Control-Option confirm or the top bar. Do not add a second-tap send.

**Checkpoint**: A clean hold listens and release processes. A modifier, a click, or Esc does not. Control-Option still talks.

---

## Phase 4: User Story 2 - Open, close, and explain on release (Priority: P1)

**Goal**: Release runs the spoken command. Open, close, and explain each have matching visuals. A close that would lose unsaved work waits for the existing gate.

**Independent Test**: Three scripted transcripts and a fixture application. No live microphone.

### Tests

- [ ] T008 [P] [US2] Write `holdThenOpenLaunchesTheNamedFixtureApp` in `Tests/ZeusCoreTests/ExplainToggleTests.swift`. It fails because a release after "open" plus a fixture name does not request that launch.
- [ ] T009 [P] [US2] Write `holdThenCloseClosesUnlessUnsavedWorkNeedsTheExistingGate` in the same file. It fails because a release after "close" does not close a clean fixture, and a fixture with unsaved work does not stop at the existing approval or confirm gate.
- [ ] T010 [P] [US2] Write `holdThenExplainThisSpeaksWithNumberedMarks` in the same file. It fails because "explain this" on release does not produce a spoken answer plus one numbered mark per relevant element.

### Implementation

- [ ] T011 [US2] Make T008, T009, and T010 pass. The fixture name is not a third-party product. Open, close, and explain do not wait for a second prompt. The close gate is the existing one.

**Checkpoint**: The three spoken commands each do the matching thing on release.

---

## Phase 5: User Story 3 - Describe what is on screen (Priority: P1)

**Goal**: "Describe what's on my screen" speaks and puts a numbered mark on each named item.

**Independent Test**: A scripted hold and a synthetic screen of three controls. No live capture.

### Tests

- [ ] T012 [P] [US3] Write `describeTheScreenSpeaksAndNumbersEachNamedItem` in `Tests/ZeusCoreTests/ExplainToggleTests.swift`. It fails because a describe transcript on release does not produce numbered marks tied to the named controls.
- [ ] T013 [P] [US3] Write `speechCallsOutTheMatchingMarkNumber` in the same file. It fails because mark 2 is not the one selected while the answer names item 2.
- [ ] T014 [P] [US3] Write `aDescriptionThatNamesNothingDrawsNoMarks` in the same file. It fails if an empty answer still opens marks.

### Implementation

- [ ] T015 [US3] Make T012, T013, and T014 pass in the explain turn. Marks are data here. Drawing them is US6.

**Checkpoint**: A describe answer has one numbered mark per named item, or no marks.

---

## Phase 6: User Story 4 - Show where to click (Priority: P1)

**Goal**: "Show me where to click to X" flies a drawn pointer to the real control and highlights it while it is named. Reduce Motion fades instead.

**Independent Test**: A scripted control frame. No click is delivered.

### Tests

- [ ] T016 [P] [US4] Write `showWhereToClickFliesThePointerAndHighlightsWhileNamed` in `Tests/ZeusCoreTests/ExplainToggleTests.swift`. It fails because a where-to-click transcript on release does not commit that control's frame as the pointer target for the duration of the naming phrase.
- [ ] T017 [P] [US4] Write `reduceMotionFadesTheHighlightInsteadOfFlying` in the same file. It fails because the pointer cue has no fade path.
- [ ] T018 [P] [US4] Write `anUnseenControlDoesNotFlyAndDoesNotClick` in the same file. It fails if a missing control still gets a target frame.

### Implementation

- [ ] T019 [US4] Make T016, T017, and T018 pass. The cue is a target and a motion choice. The overlay that draws it is US6. No system-cursor warp.

**Checkpoint**: Point, fade, or refuse. Never a guessed frame, never a click.

---

## Phase 7: User Story 5 - Walk through a task (Priority: P1)

**Goal**: "Walk me through X" shows one step. The next step starts on a tap or when the step is done. The tap does not start a hold.

**Independent Test**: Three synthetic steps. No click on the person's behalf.

### Tests

- [ ] T020 [P] [US5] Write `aWalkShowsOnlyTheCurrentStep` in `Tests/ZeusCoreTests/ExplainToggleTests.swift`. It fails because a walk transcript does not keep a step index or hide the later steps.
- [ ] T021 [P] [US5] Write `aTapOrAFinishedStepAdvancesTheWalk` in the same file. It fails because a Right Option tap during a walk does not advance, and a finished step does not advance on its own. The same test fails if that tap starts a new hold.
- [ ] T022 [P] [US5] Write `escapeOrTheLastStepEndsTheWalk` in the same file. It fails because Esc and the last step do not both return the turn to idle with no further step.

### Implementation

- [ ] T023 [US5] Make T020, T021, and T022 pass.

**Checkpoint**: One step visible. Tap or completion moves forward. Esc stops. The tap is not a listen gesture.

---

## Phase 8: User Story 6 - Overlay, displays, sync, and approval (Priority: P1)

**Goal**: One click-through overlay, up for the hold and the result, in sync with speech, correct on every display, torn down with the turn. A click for the person still waits for approval.

**Independent Test**: App-side tests with synthetic screens. The approval assertion uses the existing approval path.

### Tests

- [ ] T024 [P] [US6] Write `theOverlayIsUpWhileHeldAndClicksPassThrough` in `Tests/ZeusAppTests/ExplainOverlayTests.swift`. It fails because no explain overlay is created for a hold, so there is nothing to tear down, and a click-through flag is not set. The test also fails if a second new window appears.
- [ ] T025 [P] [US6] Write `pointerAndMarksMatchThePhraseOnEveryDisplayAndScale` in the same file. It fails because a mark is not placed on a non-main display's frame at that display's backing scale while the phrase names it.
- [ ] T026 [P] [US6] Write `aClickForThePersonWaitsForTheExistingApprovalCard` in the same file. It fails if the turn can click before the existing approval card allows it. A highlight alone must not click.
- [ ] T027 [P] [US6] Write `theLatencyClocksMatchTheSpec` in `Tests/ZeusCoreTests/ExplainToggleTests.swift`. It fails because the turn does not record the three clocks in spec.md SC-001, SC-002, and SC-003. SC-001 starts at release. The test checks the clock definitions, not a p50 measured on this host.

### Implementation

- [ ] T028 [US6] Make T024, T025, T026, and T027 pass. One overlay, `ignoresMouseEvents` for the whole turn, frames from the control's screen, torn down on every end. The click path calls the existing approval card and does not add a gate. The p50 run on Tony's Mac is a later measurement, not this task.

**Checkpoint**: The overlay is up for the hold and the result, on the right display, and it does not eat clicks. Approval is unchanged.

---

## Phase 9: User Story 7 - Right Command stays hold to dictate (Priority: P2)

**Goal**: Murmur's Right Command hold stays. Its tap stays off.

**Independent Test**: Default settings, synthetic Right Command events.

### Tests

- [ ] T029 [P] [US7] Write `rightCommandHoldStillDictatesAndItsTapDoesNotExplain` in `Tests/ZeusCoreTests/ExplainToggleTests.swift`. It fails if the Right Option work makes a Right Command tap start an explain hold, or if a Right Command hold no longer dictates.

### Implementation

- [ ] T030 [US7] Make T029 pass without adding a setting control and without turning the optional tap on.

**Checkpoint**: Dictation and explain do not share a hold.

---

## Phase 10: User Story 8 - VoiceOver, loading, error, and recovery (Priority: P2)

**Goal**: The same outcomes are announced. A hold while the engine is not ready does not process on release.

**Independent Test**: Scripted VoiceOver actions and a scripted engine that is loading, then failing.

### Tests

- [ ] T031 [P] [US8] Write `voiceOverHearsHoldReleaseCancelAndTheMark` in `Tests/ZeusAppTests/ExplainOverlayTests.swift`. It fails because hold, release, cancel, the mark number, and the control name are not announced, and VoiceOver cannot cancel a hold.
- [ ] T032 [P] [US8] Write `loadingDoesNotProcessAndErrorRecoversOnTheNextHold` in `Tests/ZeusCoreTests/ExplainToggleTests.swift`. It fails because a hold while the engine is loading can be mistaken for a captured request, and an error does not return to idle ready for a fresh hold with nothing processed.

### Implementation

- [ ] T033 [US8] Make T031 and T032 pass. Announcements name the state in words. Loading, error, and recovery match FR-015 and FR-016.

**Checkpoint**: VoiceOver can cancel a hold. A broken engine cannot process.

---

## Phase 11: Polish

**Purpose**: Prove the preserved surfaces and leave the measured p50 for Tony's Mac.

- [ ] T034 [P] Record, in the implementation PR, that the top bar files were not part of the diff, and that the existing explanation hold control's tests still pass. This task does not restyle either surface.
- [ ] T035 Run the 20-turn p50 samples for SC-001, SC-002, and SC-003 on Tony's Mac and attach the timestamps. Until that run exists, the latency targets stay unmeasured. Do not invent the medians.

---

## Dependencies & Execution Order

### Phase Dependencies

- Setup (T001) starts immediately.
- Foundational (T002) is red before any story implementation.
- US1 (T003 to T007) blocks every later story, because there is no turn without the hold.
- US2, US3, US4, and US5 can proceed in parallel after US1. They all start from a release.
- US6 draws US2 through US5, so it follows their data tests.
- US7 can be written beside US1 and must be re-run after T007.
- US8 follows US1 and US6.
- T035 waits for a Mac. It does not block the red tests.

### Within Each User Story

- Tests are committed red, with the assertion that fails on the parent, before the implementation task.
- A story's implementation task is done only when its listed tests pass and no earlier story's tests regress.

### Parallel Opportunities

- T003, T004, T005, and T006 are one red commit.
- T008, T009, and T010 can be written together.
- T012, T013, and T014 can be written together.
- T016, T017, and T018 can be written together.
- T020, T021, and T022 can be written together.
- T024, T025, T026, and T027 can be written together.

## Implementation Strategy

1. T001 and T002, red.
2. US1, red then green. Stop and check Control-Option and Right Command.
3. US2, US3, US4, and US5, red then green, still without a window.
4. US6, the one overlay, red then green.
5. US7 and US8.
6. T035 on Tony's Mac. The docs head is not that measurement.

Slice 002, the shared microphone owner, is specified separately and is not implemented from this list.
