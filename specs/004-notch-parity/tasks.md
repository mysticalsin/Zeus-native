---

description: "Red-first tasks for notch parity"
---

# Tasks: Notch parity

**Input**: `/specs/004-notch-parity/`

**Tests**: Each implementation task is blocked until its test is red. `checklist.md` is updated only with a command that was actually run. This docs commit runs none of them.

## Phase 1: Wave 1 docs gate

- [ ] T001 Keep `checklist.md` as the only place a "verified on" value is written. A task that updates it without a log is not done.

## Phase 2: Wave 1 multi-display and settings (first code batch)

### Tests

- [ ] T002 [P] Write `everyConnectedDisplayGetsOneBar` in `Tests/ZeusCoreTests/NotchDisplayTests.swift`. It fails because `DisplaySelection.targets` with the default `NotchDisplayMode.builtIn` returns one screen when three exist.
- [ ] T003 [P] Write `hotPlugAndScaleRebuildTheBars` in the same file. It fails because a resolution change that keeps the same ids is not required to rebuild unless `needsRebuild` sees a frame change, and the test for three scales does not exist.
- [ ] T004 [P] Write `mirrorBarsDoNotDoubleActions` in the same file. It fails because nothing yet says a second bar's play control is not a second command.
- [ ] T005 [P] Write `notchlessDisplaysUseTheDrawnNotch` in the same file. It fails until a notchless descriptor selects the drawn notch and a notched one does not.
- [ ] T006 [P] Write `settingsRowsAreReachableAndHeldRowsSayNotAvailableYet` in `Tests/ZeusAppTests/NotchParitySettingsTests.swift`. It fails because held contracts are absent or look like working controls.

### Implementation

- [ ] T007 Make T002 through T006 pass. Default to every display. One controller. Preserve the current top bar drawing and motion. Do not add a window.

## Phase 3: Wave 1 shuffle and lyrics (same first batch)

### Tests

- [ ] T008 [P] Write `spotifyNeverOffersRepeatOneAndAScriptTimesOutAtThreeSeconds` in `Tests/ZeusCoreTests/MusicModeTests.swift` if that suite exists, otherwise `MusicModes` tests. The repeat-one half already has a home in `MusicModeRules.supportedRepeatModes`. The 3 s half fails because no timeout is applied to the script.
- [ ] T009 [P] Write `aScriptIsNotBuiltWithoutConsent` next to it. It fails if a set script is produced when Automation is false.
- [ ] T010 [P] Write `aLyricsFailureIsNotCachedAndTheWaitHonoursRetryAfterWithJitter` in the lyrics tests. It fails because `LyricsBackoff.recordFailure` uses Retry-After with no jitter.

### Implementation

- [ ] T011 Make T008, T009, and T010 pass. Do not cache `.unavailable` as `.none`. Do not change the 45 s or 20 s timeouts.

## Phase 4: Wave 2 face approval (after Wave 1)

### Tests

Write these red, against synthetic vectors and cue readings, not against Tony's face. Do not report a false-accept rate from them.

- [ ] T012 [P] Write `genuineAndImpostorVectorsAreOrderedByDistance` in `Tests/ZeusCoreTests/FaceApprovalTests.swift`. It fails until a threshold exists that accepts a near vector and rejects a far one, with the false accept treated as the worse error.
- [ ] T013 [P] Write `photoReplayAndVirtualCameraAreRejected` in the same file. It fails until a replay cue or a virtual-camera flag refuses the match even when the vector is close.
- [ ] T014 [P] Write `lowLightFarNearOccludedNoCameraDeniedAndTimeoutEachHaveASentenceAndATouchIDFallback` in the same file. It fails until each of those eight conditions has its own message and a `LocalAuthentication` fallback flag.
- [ ] T015 [P] Write `lockoutAfterNFailuresCannotApprove` in the same file. It fails until the Nth failure locks and a later face or fallback inside the lock cannot approve.
- [ ] T016 [P] Write `theAuditLineHasNoEmbeddingAndTheKillSwitchStopsTheCamera` in the same file. It fails until the log string contains no float vector and the kill switch forces a deny.
- [ ] T017 [P] Write `enrolmentStoresNoImage` in the same file. It fails if a record type can encode an image or a thumbnail.
- [ ] T018 Write `approvalSyncUsesFaceBeforeItClearsBothSides` as the spec 003 hook test. It fails until a successful face check is what allows the card and the terminal choice to clear together, and a failed check clears neither.
- [ ] T018a Write `faceUnlockWithNetworkAndLLMStubbedToThrowDoesNotCallEither` in `Tests/ZeusCoreTests/FaceApprovalTests.swift` before T019. Network and LLM clients are disabled or stubbed to throw, and each records that it was entered. The test runs enrolment, the match, a face approval, the Touch ID fallback, and presence. It fails if either stub is entered. It fails if the run does not finish with a local result. It stays red while the pipeline is missing or while any step calls a stub.

### Implementation

- [ ] T019 Make T012 through T018a pass behind the embedder protocol. The selected implementation is SFace with YuNet, converted to Core ML, and it is not vendored until the celebrity-dataset sign-off in spec.md. Do not add an InsightFace weight. Do not add an entitlement. Camera permission only. Active liveness uses Vision landmarks. Do not add a language model, a network client, or a second language to this path.
- [ ] T020 Measure false-accept and false-reject on synthetic or licensed public fixtures and write the counts into `checklist.md`. If the fixtures are not licensed, leave the cells blank and stop. Do not invent the rates.
- [ ] T021 Leave `qa/face-approval-live.md` for Tony. Do not fill its result fields in an agent run.

## Phase 5: Other Wave 2 settings

Each test fails while the feature can turn on without its setting, or can run when the symbol is missing.

- [ ] T022 [P] R-015 and R-016: `missingBatteryKeysHideAndUnknownIsNotZero`, then the Bluetooth prompt only when the setting is on.
- [ ] T023 [P] R-018: `missingLockScreenSymbolStaysHidden` and `unlockDoesNotSwallowTheNextClick`.
- [ ] T024 [P] R-017: `focusNameUsesThePublicFilterUnlessTheStoreFileIsOptedIn`.
- [ ] T025 [P] R-019: `speakerNamesDoNotBrowseUntilLocalNetworkIsOn`.
- [ ] T026 [P] R-020: `theDropPageRefusesPlainHttpOnSharedWiFi`.
- [ ] T027 R-022: add Sparkle 2 only in that commit, EdDSA, no private key, no publish. The red test is `anUpdateWithoutAValidSignatureDoesNotInstall`.

## Dependency

Wave 1 (T002 through T011) is green before Wave 2 (T012 onward). R-014, R-024, and R-025 have no implementation tasks.
