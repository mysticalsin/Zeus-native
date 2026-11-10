# Native compiler checkpoint

At `ead3e6969687ec170ca0cbd7a0aa867575ef03c9`, both Mac app jobs
completed compilation with exit code zero but emitted `Internal Error:
dataCorrupted` diagnostics. The test compiler barrier rejected those logs, so
none of the 26 selected native processes ran. A successful shell exit is not a
clean compiler receipt.

The PR build log contains 24 such diagnostics; its test-build log contains one
while emitting FluidAudio. No source-level `error:` diagnostic was found in
those two logs. The broader compiler warning inventory still requires review;
this finding does not certify that the application is warning-free.

[Swift issue 86833](https://github.com/swiftlang/swift/issues/86833) reports the
same message with Xcode 26.1.1 and traces it to macro-plugin shutdown messaging.
The linked [SwiftSyntax fix](https://github.com/swiftlang/swift-syntax/pull/3164)
handles an empty termination message. This is evidence for a toolchain-related
cause, not proof that every Zeus diagnostic has that cause.

The [exact runner image inventory](https://github.com/actions/runner-images/blob/macos-15-arm64/20261104.0514/images/macos/macos-15-arm64-Readme.md)
lists Xcode 26.3 at `/Applications/Xcode_26.3.app`. Both Mac jobs now select
that explicit installation for a fresh build and test run. No error text is
filtered or reclassified, no test is removed, and no failed artifact is reused.
The existing compiler-barrier regression continues to reject the observed
internal-error diagnostic, even when followed by `Build complete` and exit zero.

Earlier Linux evidence remains scoped to `ead3e69`: 631 development checks in
56 suites. Its extension job also passed 18 named tests, typechecking, bundling
and the dependency audit. A new workflow revision needs its own CI evidence.

Physical QA is planned first on the MacBook Pro built-in display. This task
still runs in the cloud Linux workspace; viewing it from the Mac has not handed
execution to that machine. No capture, install or signing has been performed.


## Xcode 26.3 results and CI compiler barriers

For head `79844a3b38b027f6a22e70ef3e0a846c68257b1e`, the
[PR app job](https://github.com/mysticalsin/Zeus-native/actions/runs/42783761863/job/129719797313)
reported 2,317 fully identified passing tests across 22 of 26 selected native
partitions, including all 2,146 Core tests. The production job log contains
`Build complete!` and no `Internal Error:` diagnostic. The native test compiler
barrier passed and discovery completed. This is progress beyond the earlier
compiler failure, not a successful app job.

Four partitions remain failed: ScribeComponentJourneyTests,
ScribeAccessibilityJourneyTests, OwnedWindowEventDriverTests and
KokoroWorkerSessionTests. The two event-dispatch suites lack a terminal Swift
Testing summary; the accessibility and resident-worker processes exited 1.
Their exact causes require their detailed artifacts. The CI job and required
aggregate remain failed, and preview packaging was skipped. The separate
development feature map reported 631 passing checks. Artifact validation and
physical-device acceptance are separate obligations; these log summaries do
not establish either one.

Review found that the standalone production build, and the additional build
inside `scripts/bundle.sh`, could exit zero after compiler diagnostics.
Both CI steps now validate their compiler logs before proceeding; the aggregate
also validates both hash-bound logs. The native test build uses the same
parser. The parser recognizes compiler diagnostic headers while allowing
Swift warning source excerpts containing an `error:` argument. Regression
tests cover both production logs, warnings, diagnostic prefixes, ANSI color,
missing completion and the command-line exit status.

The workflow exposes a bounded tail of failed native fixture logs to aid
diagnosis, while retaining full logs in the evidence artifact. Test selections,
assertions, deadlines and required outcomes are unchanged. This change does
not authorize installation, recording, notarization or release.

The cloud executor went offline while this repair was in progress. The
preliminary local patch had 11 focused tests passing and an independent review
that identified the bundle gap. The extended patch was reconstructed from
the exact published head through the GitHub connector; it requires its own CI
validation. Prior local results must not be attributed to the extended patch.

Independent review of the extended parser also found that LLVM errors and
absolute compiler-tool paths could evade its initial prefix list. The parser
now retains rejection of those headers, including root-level and space-containing
paths, with explicit regression cases. This was established by source review;
no corresponding zero-exit LLVM failure was observed in Zeus CI.

At `1e88f0639836b8898396c639deb609419b5f2fa2`, the
[PR run](https://github.com/mysticalsin/Zeus-native/actions/runs/42787029328)
again reported 2,317 native passes and the same four failed partitions.
The development run passed its other 528 checks but failed the selftest
partition. Source review identified expected CLI rejection diagnostics
interleaving unittest's result line; the fixture now captures and asserts
stderr. A subprocess regression feeds that case's actual transcript through
the unchanged strict Python summary parser. After the executor recovered, the original artifact confirmed all 109
unit tests exited successfully but the strict runner rejected the interrupted
CLI result line with `Python cases missing/duplicated/skipped`. This confirms
the transcript defect; the parser was not relaxed.

The exposed native logs establish two separate event-fixture findings:
AppKit changed event number 1,000,001 to 16,961 and rounded the timestamp,
causing the driver's exact identity comparison to reject its queued release;
both event suites also exited from Swift's async-main drain path without
terminal test evidence. These observations do not establish a shared cause.
The accessibility host remained inactive and its controls lacked the required
AX roles/tree. Four resident-worker assertions failed during concurrent
startup; the cause remains under investigation. None of these failures is
waived or reclassified as device proof.

At `1ffadd3`, all 110 verification selftests passed on Linux. Its macOS
development CI also passed all 638 checks. The native app job remains failed;
these verification repairs do not waive the native journey failures. The
interrupted local patch was preserved in a git stash and external diff before
fast-forwarding to the GitHub commits. The restored executor is still Linux.

The `1e88f06` native artifact has now been independently revalidated against a
detached exact-source checkout: source manifest, compiler/discovery evidence,
hashes and complete event streams establish 2,317 passes in 22 partitions.
The four failed partitions remain failed. See the machine-derived
[partial receipt](../qa/receipts/20261110/mac-1e88-ci.json).

The queued-release repair captures the canonical queue representation immediately
after insertion, before dispatch, and keeps subsequent identity checks exact.
A nontracking responder regression covers release delivery; the foreign release
regression now shares the same window and point and preserves its own canonical
identity. Linux parsing succeeds, but native execution is still required; this
repair does not claim to resolve premature test-host exit or AX exposure.

The worker fixtures now retain bounded synthetic phase traces, join rendering
and close sessions before deleting fixture files, and require a valid-WAV
control plus a per-mode acknowledgement for rejection tests. The original
wrong-ID/path fixtures also supplied invalid WAV data, which could mask missing
protocol checks. All 17 focused Foundation/subprocess tests pass on Linux.
Separate mutations removing the ID and path guards each fail their test;
early directory removal fails the cleanup guard. Production worker source,
concurrent execution and existing timing limits are unchanged. Mac startup
latency and the actor-owned synchronous Process.run path still require
diagnosis; these fixture repairs do not establish a production latency fix.

## Native fixture checkpoint at c803a96

The intervening `f024d1a` run caught the outdated spelling of AppKit's
`acceptsFirstMouse(for:)` override in the new test view. Its production build and
638 development checks passed, but test compilation failed and no native test
partition ran. The spelling was corrected in `c803a96`.

Both `c803a96` Mac runs completed production and test compilation and still
reported the same four failed native partitions. Independent validation of the
[push artifact](https://github.com/mysticalsin/Zeus-native/actions/runs/42794257141)
confirms 2,317 complete passes in 22 partitions; the
[partial receipt](../qa/receipts/20261110/mac-c803-ci.json) binds the exact source,
compiler/discovery evidence and event streams. Canonical event capture no longer
rejects the first dispatched release, but the event host still exits before its
suite completes. This is not acceptance of the queued-release regression.

The worker traces separate configuration from Python entry. The three early
marker waits still failed at roughly two seconds without a Python-entry marker.
The push run's idle test passed around 2.7 seconds; its PR counterpart failed at
three seconds. The valid-WAV control and wrong-ID/path tests completed on both
runs, as did the throwing-fixture cleanup guard. Swift system uptime and this
Python runtime's monotonic timestamps have different origins and must not be
subtracted across processes. The precise cold-start delay remains unresolved;
neither deadlines nor concurrency have been relaxed.

The push development job passed 638 checks; the PR development job caught a
successful write in a supposedly closed-pipe fixture. A remaining reader is
required for that result. The fixture's unprotected Foundation Pipe could be
inherited by another child, although the specific child was not identified.
It now uses a private FIFO opened atomically with CLOEXEC, unlinks it, proves a
positive byte transfer, and requires kernel evidence of reader closure before
requiring the exact unavailable-stream error. Darwin's HUP and Linux's ERR are
both recognized. All 35 focused export/transport tests pass on Linux; native
validation of this revision is still required.

The three owned-window suites now have a test-only synchronous AppKit host.
It loads the existing compiled test bundle through Swift Testing's documented
[ABI](https://github.com/swiftlang/swift-testing/blob/swift-6.2.4-RELEASE/Sources/Testing/ABI/EntryPoints/ABIEntryPoint.swift),
without calling its async main. Swift Testing still writes the original
version-zero event stream and terminal summary. The runner binds the exact
host, bundle and filter command and retains the host binary and metadata as
hashed artifacts. The normal compiler barrier, compiled test discovery,
positive test counts, complete events and accessibility assertions remain
required. Source review and Linux gate tests do not establish AppKit execution;
the new host requires its own Mac build and run. No installed app or OS privacy
permission is changed by this synthetic host.
