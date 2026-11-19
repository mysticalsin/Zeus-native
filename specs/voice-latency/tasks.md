# Tasks: Voice latency

**Input**: `specs/voice-latency/spec.md` and `plan.md`

**Prerequisites**: plan.md, spec.md

**Tests**: Required. Red first. Do not weaken an existing test.

## Phase 1: Harness

- [x] T001 Add a failing ZeusCore test that a dictation trace records the five durations and that its log line contains no transcript text. `Tests/ZeusCoreTests/DictationLatencyTests.swift`
- [x] T002 Add the dictation trace next to the existing spoken-answer trace. `Sources/ZeusCore/Voice/DictationLatency.swift`
- [x] T003 Make T001 pass. Do not put audio or text in the log.

## Phase 2: Capture

- [x] T004 Add a failing test that a second press does not build a new engine while the prepared format stays valid, and that a bad format builds again.
- [x] T005 Keep the engine prepared while listening is enabled. A press reuses it when the format is valid, and builds a new one when it is not. `Sources/Zeus/Voice/SpeechInput.swift`
- [x] T006 Mark mic-hot, the first frame, and the first partial while the key is held. The mark carries no text.
- [ ] T007 Keep the recognizer resident between holds. Mark release-to-final.

## Phase 3: Insert and commands

- [ ] T008 Add a failing test that insertion is recorded as a duration and that a known intent resolves without a model call.
- [ ] T009 Record transcript-to-insert.
- [ ] T010 Add the local fast path for the intents in the spec. Run it at the same time as the model fallback. A hit cancels the fallback.

## Phase 4: Proof

- [ ] T011 Push the head and read the hosted macOS log. Fill the baseline table in `spec.md` from that log only.
- [ ] T012 Confirm the installed cue still plays and a right-Command tap still toggles. Do not change those tests to fit a new timing path.
