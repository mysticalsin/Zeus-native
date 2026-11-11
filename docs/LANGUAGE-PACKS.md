# Language packs

Owner request (verbatim): "Make sure that if I need language packs too they get installed after the install of the app keep it very light for install packages (install eng, french, spanish, portugues)".

## DESIGN

Principle: the app bundle carries no language data. Language support is installed after the app, from an explicit, visible choice, in the background.

**What a pack is.** Four packs: English (en-US), French (fr-FR), Spanish (es-ES), Portuguese (pt-BR). A pack is a list of components:

| Component kind | What it is | Installed by |
|---|---|---|
| `appleSpeechAnalyzerAsset(locale)` | Apple's on-device SpeechAnalyzer model for one locale (macOS 26+) | `AssetInventory.assetInstallationRequest` (install), `AssetInventory.release(reservedLocale:)` (remove) |
| `systemVoice` | Spoken replies use the macOS voice for the language. No download, state is always "not needed". | nothing |

Kokoro finding (verified in `FluidAudio/Sources/FluidAudio/TTS/KokoroAne/KokoroAneConstants.swift`): FluidAudio's Kokoro has language variants `english`, `mandarin`, `japanese`, `spanish`, `french`. There is no Portuguese frontend (the `pf_dora`/`pm_*` voice packs would speak English phonemes). English, Spanish and French share one `ANE/` model bundle, so a per-language Kokoro download does not exist; Kokoro stays the existing optional "Set up Kokoro" button under Voice and is not part of the default packs (keeps the install light). Portuguese therefore always uses a macOS voice. Call-window name patterns are strings in code and need no download.

SFSpeechRecognizer on-device assets (macOS 14 and 15 path, and the Polyglot and wake-word listeners) are managed by macOS and cannot be installed by an app. Settings shows a one-line hint and a button that opens System Settings (Keyboard > Dictation) through the existing `NSWorkspace.open(x-apple.systempreferences:)` helper style, never scripted.

Parakeet v3 (25 languages in one model, about 480 MB) stays a separate optional item "Best accuracy, all languages" in the existing speech-engine card. It is not in any default pack.

**State machine (ZeusCore, pure).** `LanguagePacks.reduce(state, event) -> (state, [effect])`, same pattern as `ModelPreparation`.

- Component state: `notNeeded`, `notInstalled`, `queued`, `downloading(progress)`, `installed`, `failed(reason)`, `unsupportedOnThisMac`.
- Pack state is derived from its components (`installed`, `installing`, `queued`, `deferred` for Low Power, `failed`, `notInstalled`, `unsupported`).
- Consent is the `wanted` set of packs. It is the only thing persisted. Nothing is queued unless a pack is wanted.
- Serial: at most one component runs. A token on every async completion makes stale completions no-ops.
- Events: `launched`, `probed`, `installRequested(packs, source)`, `installNowTapped`, `lowPowerChanged`, `progress`, `succeeded`, `failed`, `cancelRequested`, `removeRequested`.
- Effects: `startInstall(token, component)`, `cancelInstall(token)`, `release(component)`, `persistWanted`.
- Resume after interruption: downloading is never persisted. On launch the wanted set is reloaded, each component is probed against macOS (`installed` or `notInstalled`), and the missing ones are queued again.
- Low Power Mode: onboarding-sourced and resumed installs wait while Low Power Mode is on; a tap on "Install now" (or an owner-sourced Install button) overrides it until the mode changes. Turning Low Power on mid-download cancels the running item and re-queues it.
- Unsupported OS: analyzer components are `unsupportedOnThisMac` below macOS 26; the pack shows that reason and the hint toward System Settings.

**Flow.**
1. Onboarding step "Languages" (after Murmure) in the shipping flow `Sources/Zeus/Onboarding` (the older `App/OnboardingView.swift` is used only by the snapshot renderer and does not ship). English, French, Spanish and Portuguese are ticked. "Continue" records the ticked packs as the pending choice; "Set up later" records nothing.
2. When the guide finishes (`OnboardingWindowController.finish`), the controller dispatches `installRequested(pending, .onboarding)`. Nothing downloads before that.
3. `LanguagePackController` (app target, `@MainActor @Observable`) performs effects. Work runs in a `Task(priority: .utility)`; the SpeechAnalyzer calls sit in a nonisolated helper so no system callback is written in a main-actor type. No `Task.sleep`.
4. On launch `resumeOnLaunch()` is called after dictation starts. It reads `wanted`, probes, and continues. It never blocks startup.
5. Settings > Dictation gets a "Language packs" card: per pack status, Install / Remove, "Install all four", "Install now" while deferred, Cancel, and the SFSpeechRecognizer hint.

**Sizes.** Apple does not publish asset sizes before install, so the components report `nil` and the UI says "Size is shown by macOS" instead of inventing a number. Sizes appear in the model when a component declares one.

## Lean install

Measured on the existing preview bundle `zeus-qa-224d9df/app/Zeus.app` (an unstripped build: `nm -a` lists 1,016,813 symbols in the main binary). `strip -S -x` was run on copies of the binaries in a scratch directory.

| Item | Before | After `strip -S -x` |
|---|---|---|
| MacOS/Zeus | 106.4 MiB | 63.7 MiB |
| Helpers/zeus-hook (zeus, zeus-bridge are the same size) | 18.0 MiB | 11.3 MiB |
| Resources/Zeus_Zeus.bundle (unchanged) | 31.6 MiB | 31.6 MiB |
| Whole app (194.1 MiB measured) | 194.1 MiB | about 131.5 MiB (estimate: 62.6 MiB less across the app and three helpers) |

What changed: `scripts/bundle.sh` runs `xcrun strip -S -x` on the app binary and the three helpers after copying and before signing (the signature seals the stripped files; signing, notarization and install steps are untouched). `ZEUS_KEEP_SYMBOLS=1` keeps symbols for a profiling build. Dynamic symbols stay, so behaviour is the same. No dSYM is ever copied into the bundle. `qa/release-scripts/test_release_scripts.py` asserts the four files are stripped before the first `codesign`. `scripts/check-bundle-size.sh [app]` enforces a 150 MB budget (`BUDGET_MB` overrides); `qa/release-scripts/test_bundle_size_budget.py` covers pass, fail and missing app. The perf-budget script (`scripts/check-perf-budget.sh`) measures CPU and memory, not bundle size, so it is unchanged.

Language packs add nothing to the bundle: there is no language data in `Resources`, and the assets are fetched by macOS after the app is installed.

Not done, with the reason:
- `-Xlinker -dead_strip` and `-Xswiftc -Osize`: SwiftPM release builds already dead-strip, and `-Osize` changes generated code. I could not run `swift build` or `swift test` in this sandbox (SwiftPM's nested `sandbox-exec` is refused), so release tests could not prove either flag. Re-measure the helpers after a real release build.
- Avatar Poses (21 MiB, 25 PNGs at 1254 x 1254) and Anim (7.6 MiB): the loader reads `.png` (`LivingMascot.swift`), so HEIC or palette PNG would need loader and tool changes, and both are lossy. Lossless re-encoding of the pixel data saves about 2.6 MiB (12 percent of Poses) but every pose carries a C2PA content-credentials chunk (`caBX`, 0.57 MiB in total) whose manifest would no longer verify after a rewrite. That is the owner's call, so the files are untouched. Anim PNGs were already optimal.
- Kokoro per-language voices: see the finding above; unchanged.
- Parakeet stays separate (about 480 MB, optional, click to download).

## Verification

- `LanguagePackTests` (19 Swift Testing cases in `Tests/ZeusCoreTests`): default four packs install serially, stale tokens, failure then retry, resume after interruption, cancel, remove, unsupported OS, Low Power deferral, Install now, mid-download Low Power, consent round trip. They were compiled and run with `swiftc` against the module, since `swift test` cannot start here.
- The app-side controller and assets were type-checked with `swiftc -typecheck` for macOS 14.2. The SwiftUI step and card could not be built here (the Observation macro plugin is blocked); CI `app` is their first full compile.
- Onboarding gained a tenth step; the nine-step expectations in `ZeusAppTests` were updated to ten.
