# Voice providers

A person can add a text-to-speech provider, validate its key, pick a voice, and have Zeus
speak with it. The default stays the local voice. A provider that is not ready never receives
the text, and the turn still speaks.

## Plug-in core

The core lives in ZeusCore and is tested on Linux.

- `ProviderKind` is `tts` now. `stt` and `llm` exist and have no adapters.
- A `ProviderDescriptor` has an id, a display name, a kind, the credential fields it requires,
  a documentation URL, and capabilities (`listVoices`, `streamingSynthesis`, `validateCredential`).
- `ProviderRegistry` is the only list. Adding a provider means one new adapter file plus one
  registry entry. A test fails unless every descriptor id has an adapter and every adapter id
  has a descriptor.
- `TTSProvider` lists voices, synthesizes text to a stream of audio chunks, validates a
  credential, and can cancel the stream in flight.

Fish Audio is documented as the shape of a third provider. It is not registered and it has
no client.

## Adapters

ElevenLabs uses the streaming text-to-speech endpoint, the voices list, and the user
endpoint for validation. The key is the `xi-api-key` header. The model is `eleven_flash_v2_5`.
Official references:

- https://elevenlabs.io/docs/api-reference/text-to-speech/stream
- https://elevenlabs.io/docs/api-reference/voices/search
- https://elevenlabs.io/docs/api-reference/user/get

Google Cloud Text-to-Speech uses v1 `text:synthesize` and the voices list. The key is the
`X-Goog-Api-Key` header and is never put in the URL. v1 returns one base64 audio payload;
Zeus yields that payload as the first chunk. Validation is the voices list. Official
references:

- https://cloud.google.com/text-to-speech/docs/reference/rest/v1/text/synthesize
- https://cloud.google.com/text-to-speech/docs/reference/rest/v1/voices/list
- https://cloud.google.com/docs/authentication/api-keys

Every request is HTTPS. A non-HTTPS URL is refused before a session is opened. Provider
calls use an 8 second timeout (`ProviderHTTPBudget.requestTimeout`). The existing 20 second
and 45 second ceilings are not changed.

Status mapping: 401 and 403 are unauthorized, 429 is rate limited, 5xx is a server failure,
and a timed-out URL is `timedOut`. A 400 during validation is treated as a rejected key.

## Credentials

`CredentialStore` reads, writes, and deletes. The macOS store uses
`kSecClassGenericPassword`, one service per provider (`app.zeus.voice-provider.<id>`),
account `api-key`, `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`, and no password dialog.
Tests use `MemoryCredentialStore`. Deleting a provider deletes that service. Keys are not
logged, printed, written to UserDefaults, or included in status, signpost, or diagnostic text.
The settings field is a secure field and the card model never publishes the raw key.

Native Keychain behavior is MAC-PENDING. Linux tests the protocol, the service names, and
the in-memory store.

## State

Each provider is `unset`, `validating`, `ready`, or `error(reason)`.

- `remove` from any state returns to `unset` and deletes the credential.
- `saveCredential` from any state starts validation.
- `retry` starts validation from `error` or `validating`, and is ignored otherwise.
- Success and failure of validation apply only while `validating`.
- A runtime failure applies only while `ready`.

The active voice defaults to `local`. Selecting a provider, choosing a voice, and removing
the selected provider are the only selection changes. Removing the selected provider returns
to the local voice. The voice id is stored in preferences. The key is not.

## A turn

Text is sent to a provider only when that provider is selected and its state is `ready`.
Otherwise the local voice speaks and the transport is not asked to carry the text.

- Unauthorized and rate limited move the provider to `error`. Later turns do not send text
  until the person validates again.
- A timeout or a 5xx speaks with the local voice for that turn and leaves the provider
  `ready`, so the next turn can try again.
- Cancel stops the cloud request and does not also speak the local voice.
- The status line is never empty.

First audio is an `OSSignposter` interval named `voice.first-audio` on macOS, and the same
name in `ProviderSignposter` everywhere. Metadata is only `provider` and `route`. The pass
thresholds are the existing voice-leg budget of 600 ms (`VoiceLatencyTargets.voiceLegMs`)
and the direct-stream p50 of 900 ms and p95 of 1,400 ms from
`specs/007-companion-parity/perf-budgets.md` on `zeus-bot/companion-parity-spec`. A fast
stub must come in under both. A live percentile on a Mac is MAC-PENDING. Linux cannot
record one.

## Settings

The Voice page mounts one card, `Voice providers`, from its own files. The card uses the
dark glass colors, 52 pt rows, 32 pt padding, and 28 pt between its groups. It has the
provider list, a masked key field, Validate, a voice picker, Test voice, a status pill,
Remove, and the helper lines below. The helper and the empty-state line say that spoken
words stay on this Mac until a provider is selected and ready.

The settings shell is unchanged apart from that one mount.

## Tests

Linux runs the registry completeness test, the exhaustive state-machine pairs, a fixed
random walk of 200 sequences, request shape for both adapters, URLProtocol stubs for
streaming chunks and for 401, 429, 5xx, and timeout, fallback to the local voice, the
proof that a key and the spoken sentence never appear in the captured log, and the
end-to-end add, validate, select, speak, and remove path. No real keys are in the repo.
Nothing is skipped except the live contract below.

## Live contract

`VoiceProviderLiveContractTests` runs only when `ZEUS_LIVE_ELEVENLABS_KEY` or
`ZEUS_LIVE_GOOGLE_TTS_KEY` is set to a non-empty value. Otherwise that test is skipped.
It must not print the key. It checks that the service accepts the key, lists voices, and
returns audio. It does not play audio. Playback remains MAC-PENDING.

```sh
ZEUS_LIVE_ELEVENLABS_KEY='…' swift test --filter VoiceProviderLiveContractTests/elevenLabs
ZEUS_LIVE_GOOGLE_TTS_KEY='…' swift test --filter VoiceProviderLiveContractTests/googleCloud
```

Run both by exporting either variable, or both, and filtering on `VoiceProviderLiveContractTests`.
Do not pass the key as a command-line argument. Do not echo it. If a test fails, the message
says that audio or validation failed. It does not include the key.

The Mac walk with a fake provider, a test-only Keychain service, and the Accessibility harness
is `specs/008-providers/e2e-mac.md`. That run does not use a real key.
