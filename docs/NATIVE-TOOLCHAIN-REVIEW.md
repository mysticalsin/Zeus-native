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
Their exact causes require their detailed artifacts. For the accessibility
suite, one cause is that SwiftUI's hosting view exposes no in-process
accessibility children; that single SwiftUI journey test now lives in
ScribeTrustedAccessibilityJourneyTests, a trusted-Mac device-proof obligation
that CI does not select and that stays open. The AppKit readiness and wrong-role
guards stay in the required ScribeAccessibilityJourneyTests partition. The CI job and required
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
It uses a private FIFO opened atomically with CLOEXEC, proves a positive byte
transfer, and requires kernel evidence of reader closure before requiring the
exact unavailable-stream error. All 35 focused export/transport tests passed on
Linux. The next Mac run (`3afa6de`) caught an incorrect FIFO poll assumption:
Darwin reports available buffer space without guaranteeing ERR/HUP when the
reader closes. XNU's
[FIFO open path](https://github.com/apple-oss-distributions/xnu/blob/f6217f891ac0bb64f3d375211650a4c1ff8ca1ea/bsd/miscfs/fifofs/fifo_vnops.c#L268)
instead guarantees ENXIO for a nonblocking writer-open with no readers. The
fixture now uses that bounded, write-free readiness probe, then unlinks the
private FIFO and invokes the tested write once. Native validation of this
revision remains required.

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

At `3afa6de`, the new host compiled on macOS, and all 113 verification selftests
passed. The app job reported 2,305 complete native passes in 21 partitions.
The three hosted suites stopped before executing tests because the combined
delegate/policy initialization guard failed; Memory transport failed the FIFO
readiness premise described above, and the worker startup waits still failed.
No UI pass is inferred from successful host compilation. Initialization now
reports an unexpected delegate separately, attempts a policy transition only
when necessary, and checks the effective regular policy. A refused transition
remains fatal. The prior combined error does not establish which condition
failed; that requires the next Mac run.

## Responsive local voice launch and process finalization

Process launch previously ran synchronously while holding the voice session
actor. The new handoff runs that transaction on a serial dispatch queue, keeps
one owned launch until adoption or cleanup, checks request identity/cancellation
and absolute deadline before and after spawning, and rejects replacement requests
while launch remains unresolved. Cancellation and deadlines can now resolve the
request during a stalled launch. Closing the session still joins a late launch
and cleans up its child; Foundation's noninterruptible `Process.run()` means that
join cannot have a hard wall-clock bound if the OS call never returns.

The successful launch releases its ownership before sending request bytes, so a
fast reply cannot leave the next sequential render incorrectly rejected. A
retained process is finalized only after exit is observed. Linux controls and
the pinned
[Foundation implementation](https://github.com/swiftlang/swift-corelibs-foundation/blob/swift-6.2.1-RELEASE/Sources/Foundation/Process.swift#L1168)
show that `waitUntilExit()` also releases its retained run-loop source. This call
is made only after `isRunning` is false, and only for a started process. It does
not claim to join a termination callback. Failed bounded child cleanup still
prevents replacement.

All 24 focused Foundation/subprocess tests pass on Linux, including finite-gate
launch deadline, cancellation, close/join, queued-expiry, before/after-spawn
failure, process lifetime and immediate worker reuse guards. Mutations that
block the session actor during launch or remove replacement-admission protection
fail the relevant guards. The normal suite remains concurrent and existing
request deadlines are unchanged. Diagnostics add fixed launch phase names and
labeled epoch/monotonic clocks; they do not read production stderr or record
submitted text. These results establish the focused Linux behavior, not Mac
startup latency, audio quality or native acceptance.

## Native lifecycle checkpoint at 139eb55

Independent validation of the [PR artifact](https://github.com/mysticalsin/Zeus-native/actions/runs/42801415962)
confirms 2,320 complete test passes across 23 partitions. The
[partial receipt](../qa/receipts/20261110/mac-139-ci.json) binds compiler output,
exact source, discovery, qualified execution and artifact hashes. All three
Scribe component journeys now finish under the synchronous AppKit host, and the
Memory transport suite passes with the Darwin-compatible ENXIO reader check.
The separate development job passes 641 checks. Three native partitions still
fail; preview packaging and the aggregate remain blocked.

The foreign-event guard failed because it queued a release before an async
readiness wait. A real AppKit loop may consume queued input during that yield.
The fixture now settles through the public click path, then synchronously tests
the same dispatcher while the foreign event is owned by the fixture. Exact
identity, geometry and action-count assertions remain required. This corrected
fixture still needs its next Mac execution.

Accessibility failures still show an AXUnknown button wrapper and no semantic
children for the SwiftUI hosting view. An ignored AppKit wrapper is not the
semantic control; this evidence alone cannot attribute failure to CI. Additional
owned-window diagnostics compare ignored views/cells with Apple's public
unignored-element APIs. Action eligibility and assertions remain unchanged.

The Python traces place the early delay after Process.run returns and before
Python enters the fixture wrapper. They do not establish its cause. CPython's
`-I` excludes environment and user-site injection but still performs system site
initialization; these disposable stub-module fixtures now also use `-S`. The
product worker retains its installed environment. Binary selection, concurrency
and request deadlines are unchanged. The isolation correction does not certify
a cold-start improvement. A bounded after-test diagnostic records the exact Apple
launcher linkage and selected interpreter without warming the cold fixtures first.
Those metadata cannot establish where the observed startup delay occurs.

## Production onboarding component journey

A fourth AppKit-hosted suite now starts from the real General Setup card, opens
the real guide controller and activates Start, Set up later, Back, Continue and
Finish through owned-window events. Persistence, permission requests, connection
checks, model downloads and sound feedback use explicit inert dependencies. The
complete deferred route runs under requested normal and reduced-motion policies;
an OS reduction preference remains authoritative. A separate denied-microphone
case requires exactly one inert recovery call and verifies that skipping remains
possible. Neither fixture constructs the live permission model or grants consent.

The tests assert step persistence, current footer reachability, closure and one
completion for that activation, plus no unsolicited service calls. They do not
prove each page's rendered text, keyboard or accessibility navigation, temporal
quality, active polling on an occluded host, the full Settings/AppDelegate route,
or a physical user's permission flow. The separate completion-isolation suite
retains repeated-completion protection. Native execution of this new component
journey remains required; Linux parsing and host/map contract tests are not a
passing Mac journey.

## Semantic controls, event admission and decorative playback

The [5dfeeb8 push artifact](https://github.com/mysticalsin/Zeus-native/actions/runs/42806557428)
was independently revalidated: 2,320 completed tests across 23 partitions, with
three failed partitions preserved in the
[partial receipt](../qa/receipts/20261110/mac-5dfe-ci.json). The exposed native
button cell has its natural AXButton role while its ignored wrapper reports
AXUnknown. Synthetic fixtures now annotate that actual cell and put the negative
role on the same identified semantic element. The production SwiftUI journey
still exposed no children. A bounded, off-main, read-only own-PID AX snapshot
now diagnoses that failed lookup without retrying or changing its original
failure. It requires an exact synthetic window marker and verified membership;
it cannot request trust, perform actions or inspect another application's tree.

The synchronous event fixture also showed that native mouseDown tracking itself
can consume a foreign release. The driver now refuses admission when any release
is already queued, before posting or dispatching a gesture. The guard requires
no additional action, exact foreign-event preservation and a successful clean
subsequent click. This protects preexisting input; it does not control new input
arriving during AppKit tracking.

At `7974d1f`, production compilation passed but the new nested private observable
fixture failed test compilation: its macro emits a file-scope conformance
extension. No native tests executed in that run. File-visible fixture scope
corrects the access; a local Swift macro control reproduces the original failure
and accepts the correction. Fresh native compilation and execution are required.

Decorative onboarding films now explicitly pause when the owned window is hidden,
minimized, fully occluded or closing, when the view is hidden, or when motion is
reduced. Reattachment replaces scoped observers; dismantling pauses playback,
disables looping, clears queued items and rejects late callbacks. Multi-film
completion requires the exact owned AVPlayerItem, consumed once, rather than
only a matching asset URL from any player. Four new native lifecycle guards use
real muted playback and media-time advancement as a positive control, then
exercise visibility/disposal and a natural completion. No capture or global
preference mutation is used. A host with existing OS Reduce Motion cannot satisfy
the initial normal-playback precondition; that remains an explicit failure, not
an override. These tests do not measure decoder CPU, energy or physical FPS.

The `318b5c8` Mac build caught two Swift concurrency errors: Notification values
were captured across MainActor.assumeIsolated in the film observers. Those
callbacks now extract a Sendable item identity or notification-kind Boolean
before entering the MainActor handler. The owned item dictionary retains exact
identity and consume-once behavior. Native test execution did not begin in that
run; the production compile failure remains a failure. The Linux Foundation
control does not reproduce Apple's diagnostic, so only a fresh Mac compile can
validate this correction.

One existing Python publication fixture now has an explicit macOS CI diagnostic
flag. After 350 ms it may sample its still-running owned child if the bounded
phase log has no interpreter-entry marker. The original binary, request deadlines
and concurrency remain unchanged. Sampler stdout is held only in bounded memory;
matching child/parent headers are required before at most 64 bounded call-tree
tuples are emitted. Raw arguments, headers, paths and errors are discarded.
Denial or timeout is unavailable evidence, with no elevation or consent retry.
Auxiliary diagnostics are joined after launch/render cleanup before deleting the
fixture directory. Two sanitizer guards pass in the portable harness. Sampling
can perturb the child and is not latency evidence; its two-second helper budget
is not a hard wall-clock cap around a stalled OS launch and allows bounded stop
observation afterward. The macOS sampling branch still requires native execution.

The `77c3d6c` [Mac PR run](https://github.com/mysticalsin/Zeus-native/actions/runs/42813474734)
passed production compilation, confirming the film observer isolation correction.
Test-target compilation then rejected optional binding of
`NSWindow.accessibilityIdentifier()`, whose AppKit declaration returns `String`.
The failure-only AX diagnostic now binds that declared value directly and keeps
the synthetic-window prefix check. No native tests ran on this revision, and
no sampler or new onboarding/film journey result is established. Fresh native
compilation and execution remain required.

## PCM conversion ownership

The two native conversion callbacks previously captured an unprotected mutable
`fed` flag and a borrowed non-Sendable PCM buffer. Each synchronous conversion
now owns a retained read-only input reference and lock-protected consume-once
state. The caller must leave the sample bytes unchanged until conversion returns;
this is not a general transfer wrapper for mutable audio buffers. A separate
nonblocking resampler guard protects the stateful converter from overlap. The
live path retains its drop-on-error behavior; checked file conversion throws.
Neither path waits for a competing conversion.

Three new native guards use generated PCM only: concurrent input requests,
streaming/final conversion with reused input storage, and contested conversion
followed by recovery. They do not open an engine, request permission, play sound,
recognize speech or measure physical-device performance. Linux parsing and source
review cannot validate AVAudioConverter behavior; fresh Mac execution is required.
The preceding compiler failure is preserved in the
[77c3d6c receipt](../qa/receipts/20261110/mac-77-ci.json).

At `e295aaf`, both production and test compilation passed. Independent validation
of the [PR artifact](../qa/receipts/20261110/mac-e295-ci.json) confirms 2,327
completed native tests in 25 of 28 partitions. All owned-event tests and the
production Setup-card/guide journeys now pass with inert services. The semantic
button fixture still rejects its press and the following SwiftUI journey exits
with a trap; actual film tests cannot reach their initial playing/advancing
condition; the cold Python fixtures retain five issues and sampling is unavailable.
These three failures remain failures. None of the film pause/requeue assertions
is accepted merely because the earlier compile errors were repaired.

## Managed test-host motion profile

The [runner-image setup](https://github.com/actions/runner-images/blob/macos-15-arm64/20261104.0514/images/macos/scripts/build/configure-system.sh#L19-L21)
explicitly enables Reduce Motion. The `e295aaf` guide trace confirms effective
reduction for both requested settings. The film tests therefore demanded
movement while the app correctly respected the OS preference. This does not
establish normal-motion playback or any later lifecycle assertion.

The app CI step now uses a wrapper that accepts only a Darwin, GitHub-hosted
runner with an existing boolean `reduceMotion` key. It records that value, sets
normal motion for the disposable profile, then restores and verifies the original
value in `finally`. Unknown preference state, setup failure, test failure or
restoration failure cannot pass. SIGTERM invokes cleanup where the process can
handle it; an uncatchable kill still relies on disposal of the hosted machine.
No personal Mac preferences, Reduce Transparency, TCC settings, daemon restarts
or consent prompts are involved. Each fresh owned-window host independently
checks the real NSWorkspace property before loading tests. Requested reduced
motion remains covered through the production view policy.

The film diagnostic exposes actual reduction/eligibility and raw player statuses.
The failure-only AX snapshot now emits bounded fixed phase names immediately,
so a trap cannot erase all progress markers; rejected semantic presses retain
exact owned-cell/target facts without an alternate action. These diagnostics do
not turn either failed journey into a pass.

At `db9d410`, [independent native validation](../qa/receipts/20261110/mac-db9-ci.json)
confirms 2,330 completed tests across 26 partitions, including all three real
AVAudioConverter/PCM ownership guards. Accessibility, cold Python startup and
film playback still failed. The managed-profile change needs fresh native proof.

The separate `e295aaf` PR development job later timed out in
`portable-bridge-transport` after 1,800 seconds. It reported 613 completed checks
and 113 passing verification selftests, but the timed-out partition has no
terminal completion and stays failed. Its counterpart push's 641 passes cannot
replace that result. The timeout cause remains under investigation.

## First drawing and bounded check cleanup

The `a847dbd` run verified the managed profile through NSWorkspace and restored
its original `true` setting. Three film cases reached real playback and passed,
but the reattachment case failed before its operation began: player and item
were ready, all eligibility gates were true, and media time/rate stayed zero.
FilmView now resynchronizes its existing policy in the supported AppKit
`viewWillDraw` boundary. It adds no timer or policy override and does not relax
the four-second actual-playing guard. Fresh native execution remains required.

Separately, the verification command executor previously used a direct-child
timeout, which could leave an inherited grandchild running. Each command now
starts a fresh process group. Timeout or interruption checks direct-child
ownership before TERM, a finite grace period and KILL; no poll/reap occurs
between those signals. Reaping is bounded, uncertain ownership is reported
instead of signaled, and nondefault SIGCHLD is refused before launch because it
can lose the true exit status. Python 3.11 public APIs remain supported. The
request timeout retains its earlier scope after process creation; a blocked OS
spawn is not claimed bounded, and descendants that create another group are
outside this cleanup boundary. Ten focused guards passed; the exact original
executor failed the owned-grandchild negative control. This repairs a cleanup
gap, not an established cause of the earlier bridge hang.

A separate diagnostic workflow compares one first explicit launch of Apple's
Python shim and the selected Xcode interpreter on fresh hosted runners. Its
independent Homebrew driver enforces the original three-second observation
deadline and separately reports the two-second marker result. Target metadata
and source hashes are collected afterward. Nine driver guards, including a
mutation control for late polling, pass locally. This experiment does not replace
the failed Kokoro fixtures or certify managed-venv/model performance.

The [a847dbd receipt](../qa/receipts/20261110/mac-a847-ci.json) independently
binds the native result and motion-profile restoration to that exact source.
The [e295aaf development failure](../qa/receipts/20261110/mac-e295-feature-failure.json)
retains the timed-out bridge partition separately from its passing companion run.

## Explicit interpreter for synthetic voice fixtures

The [fresh-runner observations](../qa/receipts/20261110/python-c1-first-entry.json)
retain all four failed diagnostic jobs. On both push and PR runners, Apple's
`/usr/bin/python3` launcher emitted no Python-entry marker before the original
three-second deadline. The selected Xcode interpreter emitted its marker and
exited in approximately 0.13–0.15 seconds. Its later `xcrun --find python3`
metadata command still timed out, so the direct-path jobs are not complete
passes. File hashes and `xcode-select --print-path` identify the literal target;
the unavailable xcrun result remains unavailable.

CI now explicitly sets `ZEUS_TEST_PYTHON_EXECUTABLE` to the selected Xcode 26.3
interpreter for synthetic voice fixtures, including the full feature-map path.
The fixture validates one absolute executable file before creating its temporary
directory and reuses that choice at both launch sites. An invalid explicit value
fails instead of falling back; an unset value retains the previous local default.
No Python warmup or resolving subprocess is introduced, and the two-second marker
and three-second request deadlines are unchanged. The production worker script,
managed-venv routing, installed packages and model behavior are unchanged.
Fresh native execution of every worker guard is still required; the launcher
experiment alone does not establish product startup or latency.

At `c1e34a1`, [independent native validation](../qa/receipts/20261110/mac-c1-ci.json)
confirms 2,334 tests across 27 complete passing partitions. All four real film
lifecycle guards now pass. The accessibility partition still exits with SIGTRAP,
and the pre-interpreter-selection Kokoro partition retains five issues. The
original Reduce Motion setting was verified restored. This accepts the tested
film lifecycle behavior, not reference motion parity, device FPS or full onboarding.

At `2edc3c1`, [independent native validation](../qa/receipts/20261110/mac-2ed-ci.json)
confirms 2,360 tests across 28 complete passing partitions. All 26 voice-worker
cases pass with the explicit fixture interpreter and unchanged deadlines; all
four film lifecycle cases still pass. The accessibility partition alone remains
failed, including both the rejected action acknowledgement and subsequent
SIGTRAP. The separate development job failed one of 130 verification selftests
in its outer supervisor cleanup; that failure is distinct from the passing
native voice suite and remains a failed check.

## Outer verification-supervisor teardown

The [2edc3 development failure](../qa/receipts/20261110/mac-2ed-feature-failure.json)
records one PermissionError in the outer isolated supervisor's consecutive
TERM/KILL teardown, after the behavior assertions. Public XNU source supports
an all-zombie-group race as one explanation; the artifact does not prove which
signal failed or establish the exact kernel cause. The fixture now sends one
SIGKILL to its still-unreaped, separately owned group, then performs a bounded
wait and closes its handles. Unexpected signal or reap errors remain failures.
Production `run.py` and the original ten behavior guards are unchanged.
All 12 focused guards passed, and two negative controls caught the old signal
sequence and an attempted permission-error suppression. The
[6e863bd development receipt](../qa/receipts/20261110/mac-6e-feature.json) now
independently validates 678 tests across 14 checks on macOS, including all 150
verification selftests. This confirms the tested supervisor repair, not full
native or release acceptance.

## Read-only diagnosis of the original accessibility crash

The native host now emits its own PID, start timestamp and actual executable
path once. Before that original launch, a small input sidecar records the loaded
test-bundle digest. After a failed AX run, the collector checks the original
source, compiler/discovery receipts, command and artifact hashes, then reads
only fresh matching host `.ips` reports from the disposable runner's standard
report directory. Exact PID/path, launch/capture time, bundle and crashed-thread
identity checks reject unrelated or ambiguous reports. File reads, candidate
counts, polling and emitted frames are bounded. Raw reports, locals, memory,
environment and arbitrary paths are not exported; only sanitized crashed-thread
symbols/image basenames and fixed diagnostic phases are retained.

The collector never launches a debugger or another test host, sends another UI
action, changes OS settings or repairs an acceptance receipt. Existing output
is never overwritten, original evidence is rechecked afterward, and unsupported
or missing reports remain unavailable. Twenty-one focused collector/host tests
and Swift syntax parsing passed.

The [6e863bd native receipt](../qa/receipts/20261110/mac-6e-ci.json) independently
validates production/test compilation, discovery and 2,360 tests across 28
complete passing partitions. The accessibility partition still failed its
`scribe.start` action acknowledgement: AppKit returned false even though the
owned readiness fixture recorded one target invocation. A separate real-control
lookup then lacked its accessibility tree, and the diagnostic path exited with SIGTRAP.
The collector returned `unavailable`, `matching_report_unavailable`, at `scan`;
its nonzero exit deliberately preserves missing diagnostic evidence. Its source,
original native receipt and input-provenance hashes match the retained artifact,
and it reports the original evidence unchanged. No matching stack was available,
so the crash cause remains unresolved. The app job and required aggregate remain
failed, preview packaging was skipped, and no physical-device acceptance is claimed.
