# Portable synthetic validation

This harness makes isolated Swift 6 packages from selected Zeus source and test files. It provides regression evidence on a Linux host when the native macOS package cannot build. It does **not** make Zeus a Linux application or prove the native capture, permissions, UI, export, signing, or installation paths work.

For a gate with schema validation, named regression guards, fresh source manifests
and failure handling, use [the closed-loop runner](../closed-loop/README.md).
`prepare.py` is its lower-level package constructor, not a release acceptance gate.

## Run

Install an official Swift 6 toolchain and put `swift` on `PATH`, then run from the repository root:

```sh
swift --version
python3 qa/portable-core/prepare.py --run
```

The script creates a new temporary directory and prints it. Each package contains `test.log` and `validation-manifest.json`; the output root contains `results.json` with the commands and exit codes. Source files are copied byte for byte, so the test inputs remain stable if the checkout changes during the run. The manifests record the source SHA-256 hashes and every excerpt boundary.

For a narrower run:

```sh
python3 qa/portable-core/prepare.py --group polyglot --group regressions --run
```

Use `--output /path/to/new-directory` to retain artifacts at a chosen location. The path must not already exist. The script never changes the production manifest, downloads packages, starts Zeus, requests OS permissions, or installs an app. Tests use fake recognizers, synthetic samples, in-memory state, and temporary test directories.

## Coverage and limits

| Group | Inputs | What remains outside this check |
| --- | --- | --- |
| `dictation-insertion` | Actual cross-turn receipt/replacement transaction and injected-field tests, including secure/unknown field refusal and acknowledgement races | Native Accessibility readback, actual focused-field replacement and recognizer accuracy |
| `polyglot` | Complete Polyglot core files and tests: segmentation, captions, source-language isolation, Clear and target-change races | Actual microphone/system audio, Apple translation packs, native bar pin/dismiss behavior |
| `regressions` | Complete core files/tests for dictation correction and prompt recovery, voice signal processing, Recordly timestamps, interruptible typing and orb geometry | Native speech engines, TTS playback, video writer/export, Accessibility and CGEvent delivery |
| `scribe` | Complete capture/session/gate/notes/presentation, microphone ingress, end-workflow and shared recording-feedback files/tests, plus verbatim pure declarations and tests extracted from `ScribeLiveLogic` | Actual LiveCapture callbacks, permission timing on devices, host clock, Accelerate chunking/diarization, real meeting windows |
| `presentation` | Complete walkthrough, timeline and numeric-action files/tests; exact `PointTarget`, math layout and Accessibility value declarations | AppKit overlays, screen coordinate mapping, motion parity, real Accessibility snapshots |
| `recordly-geometry` | Complete cursor-follow/export-plan files and tests, with the exact `CompanionSpring` declaration | Native movie writing, video rendering, large-file persistence, real display coordinate evidence |
| `buddy` | Complete companion pointing/flight/coordinate files and tests, including display-change retargeting and reduced-motion label behavior | Native display events, controller/renderer integration and reference motion parity |
| `wiki-relationships` | Complete relationship/compiler/page and saved-recap navigation policy files/tests, plus the exact `ScribeMeetingRecord` declaration | Native related-page UI and actual source navigation; no filesystem persistence test is selected |
| `wiki-export` | Complete export selection/transaction/journal/confinement/MCP sources, actual app `MCPStdioClient` in a separate support target, a wrapper forwarding to production `WikiExportMCPCommand.run`, real-process transport tests and temporary-vault tests | Native selection UI, unified learning, graph usability and the user's configured MCP destination; never a personal vault |
| `wiki` (optional) | Complete Wiki files/tests and the exact `ScribeMeetingRecord` declaration | Native filesystem semantics and the app's learning integration |

The declaration excerpts are listed explicitly in `prepare.py`. No business implementation is replaced with a fake in these packages. On Linux, `recordly-geometry` and `buddy` supply a module named `CoreGraphics` that only reexports Foundation's `CGPoint`, `CGSize` and `CGRect` value types. They exercise real planning math; they do not validate Apple's CoreGraphics implementation. On macOS that compatibility module is not generated. The manifest records the explicit recipe platform for cross-job verification. The omitted platform imports and surrounding code are still unvalidated. The separate ad hoc Brain app-model and Chrome socket-stub checks from the November review are not part of this harness and must not be counted as a native build.

## Wiki filesystem diagnostic

The optional Wiki suite includes filesystem tests that fail with Swift 6.2.1 Foundation on this Debian Linux host. `FileManager.replaceItemAt` throws Cocoa error 4 for two existing temporary files and removes the original. The same failure reproduces without Zeus code:

```sh
swift qa/portable-core/reproduce-foundation-replace.swift
python3 qa/portable-core/prepare.py --group wiki --run
```

The November 9 run passed 66 of 76 Wiki tests; ten overwrite/state tests reported twelve issues. Keep those failures in the receipt. They require macOS validation; do not weaken atomic persistence or skip them in the native suite to obtain a green result.

## Native gate remains required

Run the real package on a supported Mac:

```sh
swift build
swift test --filter "$(python3 qa/closed-loop/gate.py native-filter)"
python3 qa/closed-loop/run.py --mode full --output /tmp/zeus-native-full-NEW
```

The native filter selects only reviewed synthetic suites; it is not the whole app suite. The November 9 Linux attempts at `swift build` and `swift test` both stopped in FluidAudio's `MachTaskSelf.c` because `mach/mach.h` is unavailable. Portable passes do not clear that gate. Full mode stays red until every required automated native/device obligation is implemented and executed. Any real capture still needs the owner's OS consent, and every installation needs a rollback copy. Signing, notarization and Gatekeeper verification need their own native receipts.
