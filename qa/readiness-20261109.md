# Zeus readiness receipt — 9 November 2026

**The native release gate is still blocked.** The portable regression packages passed **300 tests in 32 suites**. Their 73 complete-file or verbatim-excerpt hashes match the current checkout. These results do not establish that the macOS app builds, runs correctly, matches the motion references, or is ready to sell.

The host was Debian 13 x86_64 with the official Swift 6.2.1 Linux toolchain. Inputs were synthetic; this work did not capture microphone, system audio or screen content, use the private vault, install Zeus, or perform live macOS QA.

## Portable packages

| Group | Tests | Suites | Receipt |
| --- | ---: | ---: | --- |
| Polyglot captions, target changes, Clear and bounded draining | 56 | 7 | [Log](receipts/20261109/polyglot.log), [sources](receipts/20261109/polyglot.sources.json) |
| Dictation correction/prompt recovery, voice signal, interruptible typing and recording clock | 68 | 8 | [Log](receipts/20261109/regressions.log), [sources](receipts/20261109/regressions.sources.json) |
| Scribe capture boundary, mute gate, session, notes and presentation rules | 115 | 10 | [Log](receipts/20261109/scribe.log), [sources](receipts/20261109/scribe.sources.json) |
| Walkthrough/timeline and untrusted action numbers/references | 16 | 3 | [Log](receipts/20261109/presentation.log), [sources](receipts/20261109/presentation.sources.json) |
| Recordly cursor-follow and export geometry | 31 | 2 | [Log](receipts/20261109/recordly-geometry.log), [sources](receipts/20261109/recordly-geometry.sources.json) |
| Wiki source/explicit-link relationships and saved-recap navigation policy | 14 | 2 | [Log](receipts/20261109/wiki-relationships.log), [sources](receipts/20261109/wiki-relationships.sources.json) |
| **Total** | **300** | **32** | [Machine-readable summary](receipts/20261109/summary.json) |

[Source verification](receipts/20261109/source-verification.json) records the final hash comparisons. Unchanged groups were not rerun merely to update the aggregate. Scribe and presentation use explicitly bounded, verbatim declarations from files with native dependencies. Recordly geometry uses a Linux import module that reexports Foundation geometry value types. No business behavior was substituted, but these checks do not validate Apple's frameworks or native integration.

Reproduce all six groups with Swift 6 on `PATH`:

```sh
python3 qa/portable-core/prepare.py --run
```

The [portable harness README](portable-core/README.md) documents group selection, snapshots, logs, excerpts and platform limits. Native capture, app-level pin controls, actual typing delivery, video encoding, sparse-file persistence, rendering and motion remain outside these packages.

## Separate evidence

These checks are deliberately excluded from the 300-test aggregate:

| Check | Recorded result | Scope |
| --- | --- | --- |
| [Brain core](receipts/20261109/brain-ad-hoc.log) | 29 tests / 6 suites passed | Ad hoc package with a stub for the unrelated `ResearchReport.vaultFolder` constant. [Harness source list](receipts/20261109/brain-harness-sources.txt). |
| [Brain app-model](receipts/20261109/brain-model-link-failure.log) | Three tests typechecked; zero executed | Extracted app model and native-provider stubs. Linking failed on a Swift Observation runtime symbol. No native app pass is claimed. |
| [Optional Wiki filesystem suite](receipts/20261109/wiki-persistence.log) | 66 passed; 10 failed tests with 12 issues | Linux Foundation `replaceItemAt` fails for existing temporary files. The [standalone reproduction](receipts/20261109/foundation-replace-linux.log) contains no Zeus code. macOS persistence is unresolved. |
| [Chrome extension](receipts/20261109/extension.log) | 12 tests passed; TypeScript and bundle build passed | Actual extension logic with mocked Chrome APIs. This is not a live-browser consent/UI test. |
| [Release scripts](receipts/20261109/release-scripts.log) | 13 tests passed | Mocked native commands cover fail-closed signing gates, publication order, rollback and failure handling. No real signing, notarization, Gatekeeper assessment or install occurred. |
| Swift syntax | [78-file sweep](receipts/20261109/syntax.json) and [7 later Wiki/source checks](receipts/20261109/wiki-source-syntax.json) passed | Parsing only; it does not resolve AppKit APIs, typecheck the complete app, link or execute it. |

The extension and release checks are reproducible with:

```sh
cd extension
npm ci
npm test
npm run typecheck
npm run build
cd ..
python3 qa/release-scripts/test_release_scripts.py
```

The optional Wiki suite keeps its platform failures visible:

```sh
swift qa/portable-core/reproduce-foundation-replace.swift
python3 qa/portable-core/prepare.py --group wiki --run
```

## Unresolved native gates

Both the real [`swift build`](receipts/20261109/native-build-linux.log) and [`swift test`](receipts/20261109/native-test-linux.log) were attempted. They stop in FluidAudio's `MachTaskSelf.c` because this host has no `mach/mach.h`. The full native suite did not execute. The [GitHub Actions annotation](receipts/20261109/github-ci-annotations.json) says the macOS job did not start because an Actions budget prevents further use.

A supported Mac must still run `swift build` and `./scripts/test.sh`, including the app tests and native Recordly export/checkpoint tests. After that, live QA must cover onboarding through daily use, real microphone-use detection and mute transitions, translation packs, pin/Stop/dismiss, cursor coordinates and exports, recap navigation/countdown/completion, and the supplied motion references. The owner answers every OS consent prompt; keep a verified rollback before each installation. Signed, notarized and Gatekeeper-clean distribution remains a separate, uncompleted release requirement.
