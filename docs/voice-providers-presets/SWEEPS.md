# Sweeps

## Security: voice quality presets

Lens: key handling, meter tamper, endpoint host pinning, redirects, and keychain accessibility.

Red: `161a96f8da3493c81001c1ea7f24f899f569d85c` (failing tests only).

Green: `a863d0a0f2da5704a397d53d99bcf7106842801e`. Isolated `swift test` of the five voice-quality suites exited 0. 49 tests passed. No network.

The seam commit is `38e790af354281fcf5a6f25b687f86a274c2d544`. The preset commit is `7a26707f1d39baceb85bc07ad39aed8b129bb762`.

### Findings

1. A key was accepted at 7 characters if the minimum check was lowered, and DEL (U+007F) was accepted if that comparison was removed.
2. C1 controls (U+0080 through U+009F), U+0085, U+2028, and the listed format characters could remain in a key. The 256 cap counted Swift characters, so a multibyte key could pass.
3. The 5,000 and 50,000 caps counted Swift characters. Combining marks cost one character and several UTF-8 bytes.
4. The production `URLSession` transport did not prove that a 302 was refused. A direct call to the task delegate was the only check.
5. The meter read path did not reject a non-regular file or a link count above 1. The parent directory was not opened with `O_NOFOLLOW` and was not synced after rename.
6. `kSecAttrAccessible` could be dropped from the update query without a failing test. Items saved earlier were not migrated on read.
7. The direct `synthesize` entry was public. Callers are `synthesizeIfEnabled` and the route-gated method.
8. The fake end-to-end comment named `app.zeus.voice-provider.<id>` as the production service. Production keys stay on `com.zeus.app`.

### Fixes

- `VoiceProviderKeyPolicy` trims only ASCII space, tab, and newline, then requires 8 characters and at most 256 UTF-8 bytes. It refuses C0, DEL, C1, whitespace, and format characters U+200B through U+200F, U+202A through U+202E, U+2060 through U+2064, and U+FEFF. The error text is exactly `The key is not valid.`
- Request and meter caps are UTF-8 bytes: 5,000 per request and 50,000 cumulative. ElevenLabs and Google bill by their own character counts. Bytes fail closed for combining text.
- `VoiceQualityURLSessionTransport.send` builds the production session with `VoiceQualityRedirectDelegate` and throws `endpointRefused` on status 300 through 399. The delegate returns nil.
- The meter opens reads with `O_NOFOLLOW` and `O_NONBLOCK`, requires a regular file and a link count of 1, creates the temporary file with `O_EXCL`, checks the device and inode after rename, syncs the parent directory, and refuses a symlinked parent.
- Add and update queries include this-device-only accessibility. The first read migrates an older item.
- The un-routed `synthesize` method is internal and still refuses the call.

### Mutants

Lowering the minimum from 8 to 7 failed `sevenCharactersAreRejectedAndEightAreAccepted`. Removing the DEL check failed `deleteAndLineSeparatorsAreRejected`. Removing accessibility from the update dictionary failed `addAndUpdateQueriesIncludeThisDeviceOnlyAccessibility`. Removing `O_EXCL` failed `anExclusiveTemporaryNameCollisionLeavesTheFileUntouched`. Each mutant was restored before the green commit.

### Known limits

Linux `swift-corelibs-foundation` aborts inside `URLProtocolClient.wasRedirectedTo`. The production-transport test on Linux delivers the 302 with `didReceive` and checks that `send` refuses it and does not contact the second host. macOS calls `wasRedirectedTo`, and the same delegate returns nil. This Linux run did not build the native macOS app.

## App route: explicit preset opt-in

Lens: a migrated provider must not count as consent, and an explicit preset must reach `VoiceQualitySpeaker`.

Red: `4a700b280d03738d0ab36d0512205d4e2e65f21c`.

### Findings

1. `voice.ttsProvider` set to `elevenLabs` or `googleCloud` by migration, plus a preset key, selected the cloud voice. A legacy domain such as `com.zeus.elevenlabs` could be widened into the same choice.
2. `VoiceSpeakAllowlist` accepted only `zeus.synthetic`, so the speak path never called `VoiceQualitySpeaker`.
3. Settings had two pickers, and neither wrote `voice.quality.preset`.
4. A rejected key said it was not valid, without saying what to do.
5. Live contract tests used `.enabled(if:)`, so a missing key could look like a pass. The human QA step looked up `settings.voiceProviders.status.elevenlabs`, which is not the status identifier.

### Fixes

- `VoiceQualityOptIn.set` is the only write. It stores `voice.quality.consent`, the preset, and the exact provider raw value. `selection` requires that consent and the exact raw value `elevenLabs` or `googleCloud`.
- `VoiceSpeakAllowlist.destination` sends an explicit preset to `VoiceQualitySpeaker` and everything else to `zeus.synthetic`.
- Settings keeps one preset picker, `settings.voiceProviders.preset`, and it calls `applyPicker`.
- A rejected key says: `Paste the key again. It needs 8 to 256 characters and no spaces or line breaks.`
- Live tests are `.disabled(if:)` with the variable name, `shouldSkip` counts them, and a missing key inside the test body fails instead of returning. Human QA reads `settings.voiceProviders.status`.

`Speaker.swift` changes are only `providerSpeech` and the `speakLine` switch. `speakKokoro` and `KokoroClausePlayback` are untouched. Timeouts are unchanged.
