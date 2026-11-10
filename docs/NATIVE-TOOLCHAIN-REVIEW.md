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
