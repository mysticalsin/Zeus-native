# Notch parity checklist

Verified on this head: nothing. A row is done only when "Verified on" is a command and a result, not a plan.

| Item | Test | Evidence level | Verified on |
| --- | --- | --- | --- |
| Every display has one bar | `everyConnectedDisplayGetsOneBar` | unit | |
| Hot-plug and scale rebuild | `hotPlugAndScaleRebuildTheBars` | unit | |
| Mirror bars do not double actions | `mirrorBarsDoNotDoubleActions` | unit | |
| Drawn notch only when notchless | `notchlessDisplaysUseTheDrawnNotch` | unit | |
| Settings rows and held labels | `settingsRowsAreReachableAndHeldRowsSayNotAvailableYet` | integration | |
| Spotify repeat and 3 s timeout | `spotifyNeverOffersRepeatOneAndAScriptTimesOutAtThreeSeconds` | unit | |
| No script without consent | `aScriptIsNotBuiltWithoutConsent` | unit | |
| Lyrics failure and jitter | `aLyricsFailureIsNotCachedAndTheWaitHonoursRetryAfterWithJitter` | unit | |
| Genuine and impostor order | `genuineAndImpostorVectorsAreOrderedByDistance` | unit | |
| Replay and virtual camera | `photoReplayAndVirtualCameraAreRejected` | unit | |
| Eight failure sentences | `lowLightFarNearOccludedNoCameraDeniedAndTimeoutEachHaveASentenceAndATouchIDFallback` | unit | |
| Lockout | `lockoutAfterNFailuresCannotApprove` | unit | |
| Audit and kill switch | `theAuditLineHasNoEmbeddingAndTheKillSwitchStopsTheCamera` | unit | |
| No image in enrolment | `enrolmentStoresNoImage` | unit | |
| Approval sync uses the face check | `approvalSyncUsesFaceBeforeItClearsBothSides` | unit | |
| Face path never calls a model or the network | `faceUnlockWithNetworkAndLLMStubbedToThrowDoesNotCallEither` | unit | |
| False-accept and false-reject | fixture run named in the notes | integration, then native Mac | |
| Tony's face | `qa/face-approval-live.md` | live service | |
| R-015 R-016 battery | `missingBatteryKeysHideAndUnknownIsNotZero` | unit | |
| R-018 lock screen | `missingLockScreenSymbolStaysHidden` | unit | |
| R-017 Focus | `focusNameUsesThePublicFilterUnlessTheStoreFileIsOptedIn` | unit | |
| R-019 speakers | `speakerNamesDoNotBrowseUntilLocalNetworkIsOn` | unit | |
| R-020 drop page | `theDropPageRefusesPlainHttpOnSharedWiFi` | unit | |
| R-022 updater | `anUpdateWithoutAValidSignatureDoesNotInstall` | unit | |

Native Mac and live service rows stay blank on a Linux docs commit.
