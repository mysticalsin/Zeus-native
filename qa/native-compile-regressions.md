# Native compiler regressions — initial public build

The first actual Mac build of audited public commit
`f07b1192ebdfb85f0dd9dadba397b52bbd63eebe` failed in
[run 42731139415](https://github.com/mysticalsin/Zeus-native/actions/runs/42731139415),
app job `129549169770`. It used macOS 15.8.2 arm64, Xcode 26.1.1 (17B100) and
Apple Swift 6.2.1. Native tests and bundling were correctly skipped after failure.
The extension and mocked release-script jobs passed.

These are **compiler/type-check guards**, not invented runtime unit tests. The
mandatory `app` job executes `swift build`; `required-checks` requires its build,
test, bundle and archive steps to succeed. The separately named native fixture
commands also compile the real app module before running. Keeping this compiler
and these source files in those commands makes a recurrence fail the check.

The test-function registry in `regressions.json` describes behavioral tests. This
ledger records type-check failures separately so they cannot be mislabeled as
executed behavioral coverage. All rows remain **native verification pending**
until a later actual Mac build of the repaired source succeeds. Linux frontend
parsing alone does not clear them.

| ID | File / first failing line | Observed compiler failure | Required guard |
| --- | --- | --- | --- |
| TYPE-001 | `Sources/Zeus/App/KeychainSelfTest.swift:73` | `Task.detached` transfers a non-Sendable closure and risks data races | Real app build under Apple Swift 6.2.1 |
| TYPE-002 | `Sources/Zeus/Dictation/CloudSpeechEngines.swift:143,151` | Closures capture `failure` / `committed` before shadowing locals are declared | Real app build; keep the actual cloud-engine source compiled |
| TYPE-003 | `Sources/Zeus/Prompter/PrompterWindow.swift:124` | Ambiguous subtraction in mixed floating-point coordinate expression | Real app build; preserve coordinate behavior |
| TYPE-004 | `Sources/Zeus/Notch/HaloRenderer.swift:27` | Path traversal expression exceeds type-check complexity budget | Real app build; retain rendering behavior |
| TYPE-005 | `Sources/Zeus/Voice/VoiceSample.swift:31` | `Task.detached` transfers a non-Sendable closure and risks data races | Real app build; no live TTS/network call needed to type-check |
| TYPE-006 | `Sources/Zeus/TopBar/HomeBackdrops.swift:168,254` | Canvas layer expressions exceed type-check complexity budget | Real app build; retain visual formulas |
| TYPE-007 | `Sources/Zeus/TopBar/RecordingFeedbackView.swift:65,66` | Accessibility environment keys are read-only, not writable key paths | Real app build plus existing `RecordingFeedbackRenderTests`; no weakened accessibility assertions |
| TYPE-008 | `Sources/Zeus/TopBar/TopBarViews.swift:135` | `VoiceLevelBars.body` exceeds type-check complexity budget | Real app build; retain waveform behavior |

There were 12 distinct compiler diagnostics across these eight files; repeated
batch-compile diagnostics are not additional failures. The
[deduplicated diagnostic receipt](receipts/20261110/native-ci-initial-errors.json)
contains exact context, source SHA and run/job identity. Full raw logs are
available in the linked Actions job and its `zeus-check-app` artifact.

The follow-up source refactors split numeric expressions into explicitly typed
intermediates while preserving the existing geometry formulas. Three repairs
also bind actual native behavioral guards in `regressions.json`: Bezier endpoint
and midpoint preservation (`REG-036`), retaining the cloud stream's missing-key
failure during finish (`REG-037`), and reduced-motion frame stability with explicit
view/style inputs instead of read-only environment setters (`REG-038`). Those
guards remain unexecuted until Mac CI runs them; source parsing is not a pass.

Do not lower the language/SDK requirements, skip these files, turn errors into
ignored output or treat a new native fixture count as proof of physical user
interaction. These repairs clear compilation only; the feature-map integration,
window journey, device and signing obligations remain separate.

## Later native checkpoints

Production and test compilation passed at `ca6d1ca` in app job `129569661281`.
That clears the initial compiler rows for that revision; its two real-control
test failures remained failures.

| ID | Revision / job | Observed compiler failure | Repair and required guard |
| --- | --- | --- | --- |
| TYPE-009 | `1c6bf06`, job `129583572489` | `OnboardingFlow.swift:291`: a Swift switch expression cannot appear directly as a call argument | Bind the result to a local before passing it to the preferences port. Mandatory actual macOS production and test compilation remains the guard; frontend parsing did not catch this type-check restriction. |
| TYPE-010 | `d571d75`, job `129586646795` | Generated `@Observable` extension cannot reference a private nested onboarding test service | Restrict the fixture to file scope with `fileprivate`, which permits the generated extension. Linux Swift 6.2.1 minimal reproduction fails before and type-checks after; actual native test-target compilation remains mandatory. |
| TYPE-011 | `bc3a586`, job `129977022153` (Xcode 26.3, Apple Swift 6.2.4) | Compiler crash, not a diagnostic: signal 6, `SmallVector unable to grow`, during IRGen of `ExplanationPane.swift` while emitting the reabstraction thunk from an `@isolated(any) @Sendable (Bool, Actor?) -> ()` function to `(@in_guaranteed Bool) -> ()`. Source: unapplied `@MainActor` method references used as `Binding` setters (`set: controller.setMuted`, line 214; same shape for `set: controller.seek`, line 166). | Pass explicit closures (`set: { controller.setMuted($0) }`, `set: { controller.seek($0) }`), matching every other setter in the file. Behavior is unchanged. Apple Swift 6.4.2 does not crash on either form, so only the pinned Xcode 26.3 app build clears this row. Do not pass unapplied actor-isolated methods as SwiftUI `Binding` setters. |
| TYPE-012 | `7417e7d`, job `130271727317` (Xcode 26.3, Apple Swift 6.2.4) | `PointingController.swift:51`: main actor-isolated default value (`NSEvent.mouseLocation`) in a nonisolated nested `Services` struct; `PointingProviders.swift:123,236`: missing argument label `tier:` for `ModelCap.httpModel`; portable `PointingCoordinateTests.swift:79`: ambiguous `.nan` in `CGRect(x:)`. Code was written in a sandbox that cannot run the Swift compiler. | `Services` is `@MainActor`; calls use `tier:`; the test uses `CGFloat.nan`. The mandatory macOS app build and the portable pointing group remain the guard. Agent-written Swift must pass the real CI compile before it is called done. |

Production and test-target compilation both passed at `df3dcc3` in
[run 42744043519](https://github.com/mysticalsin/Zeus-native/actions/runs/42744043519),
app job `129591763939`. That clears TYPE-009 and TYPE-010 for that revision.
Execution then stopped at a separate structured test-discovery validation error:
Swift Testing's list output omits argument cases for parameterized functions.
No native tests executed in that run, and preview bundling remained blocked.
