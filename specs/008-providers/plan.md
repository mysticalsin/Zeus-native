# Plan: pluggable voice providers

## Shape

ZeusCore owns the plug-in. The app owns the Keychain calls it already can make, the settings
card, and the one hook in the existing speaker.

Adding a provider later:

1. Add one adapter file that conforms to `TTSProvider`. HTTPS only, the 8 second provider
   timeout, no key in the URL, no key in the log.
2. Add one `ProviderEntry` in `ProviderRegistry.entries` with the same id.
3. The registry test fails until those ids match. Fish Audio's file is the written form of
   these steps and is not an entry.

## Files

New, in ZeusCore: descriptor and failure types, the two state machines, the HTTP transport,
the credential protocol and the in-memory store, the macOS Keychain store, the log and
signpost, the ElevenLabs adapter, the Google Cloud adapter, the Fish Audio stub, the
registry, and the session that adds, validates, selects, speaks, and falls back.

New, in the app: `VoiceProvidersCard.swift` and `PluginVoiceBridge.swift`.

Edited, and only these: `GlanceSettingsPages.swift` gains one `VoiceProvidersCard()` on the
Voice page. `Speaker.swift` asks the bridge before the existing engine chain. When no
provider is selected the bridge returns immediately and the chain is unchanged. When a
provider is selected and fails, the speaker tries Kokoro, Chatterbox, then the Mac voice,
and does not call another cloud engine for that turn.

Not edited: `Package.swift`, workflows, the 20 second and 45 second timeouts, the orb,
persona, and turn-machine files.

## Red, then green

The first commit is the tests only. They do not compile against the base, because the types
are not there. The implementation commit makes them pass.

Linux cannot build the app target. The portable proof is a small package of
`Sources/ZeusCore/Providers` plus `Tests/ZeusCoreTests/VoiceProvider*.swift`, run with
`swift test --filter VoiceProvider`. That is not a Mac run. Keychain prompts, audio
playback, and the signpost interval on a real device stay MAC-PENDING.

## Privacy

The session sends text only from the cloud branch, and only when the state is `ready`.
Logs go through `ProviderLog`, which replaces any secret it is given before the sink sees
the line. Status, preferences, and signpost metadata do not carry the key or the sentence.
Preferences store the selected id and the voice id. The key goes to the credential store.

## First audio

`voice.first-audio` starts when a turn starts speaking and ends on the first cloud chunk or
on the local voice's return. The verdict compares that interval with 600 ms, 900 ms, and
1,400 ms. Those numbers are the existing voice-leg budget and the direct-stream percentiles.
This slice does not loosen them and does not claim a live percentile.

## Built in

The picker is `VoiceProviderPicker` in `Sources/Zeus/Settings/VoiceProvidersCard.swift`.
It is mounted inside the existing Voice card (`GSVoiceCards.swift`), on the same page as
"Speaks with". It uses SwiftUI `Picker`, `SecureField`, `Toggle`, `ProgressView`, and
`Button`, and the glass material from the settings shell (translucent, solid when Reduce
Transparency is on). It does not open a window.

ElevenLabs uses the existing Keychain account `elevenlabs.api-key` and voice account
`elevenlabs.voice-id` on `com.zeus.app`. The choice is the existing `voice.ttsProvider`
key (`elevenLabs`, `googleCloud`, or `kokoro` for the local voice). Google Cloud has no
older account, so its key is `google-cloud-tts.api-key` on that same service and its voice
id is `voice.googleCloud.voice`, the same shape as `voice.gemini.voice`.

Offline order is Zeus's existing local voice, then `AVSpeechSynthesizer`. The chain is
`OfflineVoiceChain`. A turn does not stop with no step.

Playback is AVFoundation: `AVAudioEngine` for a WAV buffer, `AVAudioPlayer` for the MP3
a cloud provider returns. Requests are `URLSession`. Keys are Security.framework. There
is no web view and no added package.

## Hook for the companion persona

`VoiceProviderQuickSwitch` in `Sources/Zeus/Settings/VoiceProvidersCard.swift` is the
SwiftUI entry another surface can embed. It is the same picker, compact, and it does not
open a window. The persona slice owns `Sources/Zeus/Companion/PersonaSetting.swift` and
can place `VoiceProviderQuickSwitch()` next to the persona control. This branch does not
edit that file, the orb files, or the turn machine.

## Out of scope

Speech-to-text and language-model adapters. A Fish Audio client. A proxy. Editing
`Sources/Zeus/Companion/PersonaSetting.swift`.
