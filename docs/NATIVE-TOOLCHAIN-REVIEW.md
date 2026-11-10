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
