# Polyglot caption harness

Checks the real `PolyglotPipeline` and `PolyglotTranscript.applySettled` with synthetic 16 kHz samples. The translator reports the pair unsupported. The heard line must remain, and no translation request may run.

This does not open a microphone, download a language pack, or call a network. It does not prove a live caption session. On macOS before 26, `PolyglotAppleTranslator` still returns `.unsupported`; that is the production path this fixture stands in for.

From the repository root, with Swift 6:

```sh
swiftc -parse-as-library -O -o /tmp/polyglot-caption-harness \
  Sources/ZeusCore/Polyglot/PolyglotModels.swift \
  Sources/ZeusCore/Polyglot/PolyglotSegmenter.swift \
  Sources/ZeusCore/Polyglot/PolyglotPipeline.swift \
  qa/polyglot-swiftc/main.swift
/tmp/polyglot-caption-harness Sources/Zeus/Polyglot/PolyglotController.swift
```

Expected output:

```
PASS polyglot unsupported pair keeps the heard line
OK 1
```

The same caption survival is also asserted by `PolyglotPipelineTests/unsupportedPairSaysSo`:

```sh
swift test --filter PolyglotPipelineTests/unsupportedPairSaysSo
```

Package resolution for that command may download the existing Zeus dependencies. The test itself uses fakes.

On 9 November 2026 the standalone command above compiled and passed on Linux with Swift 6.2.1:
`PASS polyglot unsupported pair keeps the heard line` / `OK 1`. This replaced the original
uncompiled packet check after repairing the translation argument label and the missing
`await` on actor-isolated audio ingestion.

The Swift tests also cover language changes while translation is suspended, separate
language tracking for microphone and Mac audio, and Clear while recognition is still
pending. These use synthetic samples and controlled fake engines. The native pin/dismiss
tests are in `Tests/ZeusAppTests/PolyglotPinTests.swift` and require macOS.

This is not a native build receipt or live microphone/translation proof. A macOS build,
OS-consented capture session, actual language-pack translation, and visible pin/Stop/dismiss
checks remain required before release.
