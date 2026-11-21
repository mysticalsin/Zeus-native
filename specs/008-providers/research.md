# Voice providers: what the reference companion does

Studied November 2026. This note describes behavior. It does not copy an implementation.
The reference companion is not named, and neither are the other products around it.

## Where keys live

The open-source companion does not put vendor secrets in the app binary. A small proxy,
deployed by the person running the app, holds three secrets: one for the language model,
one for transcription, and one for the voice. The app sends the spoken text to the proxy.
The proxy attaches the secret and calls the vendor.

The voice id is treated as non-secret configuration. It sits beside the proxy, not in the
secret store.

For local development the same proxy runs on the machine. Secrets live in a file next to
that proxy and are not part of the app. The app is pointed at the local proxy address.

There is no in-app field where a person pastes a voice key into the open-source companion.
Selection of the voice is a configuration value on the proxy, not a picker in the app.

## How a turn uses the voice

The voice client posts the text and asks for audio. It names a low-latency voice model so
playback can start before a full clip exists. The client that ships in the repository waits
for the whole response body before it plays, and it uses a 30 second request timeout and a
60 second resource timeout. Those numbers are not Zeus's. Zeus does not copy them, and this
work does not change Zeus's existing 20 second and 45 second ceilings.

A non-success status throws. Playback can be stopped. The client does not fall back to a
local voice. If the request fails, that turn has no speech from this client.

## What the current public documentation says

The reference companion's public pages do not document a setting where a person pastes a
voice API key. Setup is: download, sign in, and grant the operating-system permissions.
The privacy notice says the service issues short-lived access, names the processors it uses,
and says sign-in details for apps the person connects are stored on the computer.

The public changelog describes the closest "add a credential" behavior, and it is for custom
connectors rather than the voice: saving a token makes a real request, and the row then
shows Checking, then Connected, or Token rejected. Billing is a Settings page. None of that
is a voice-provider key field.

## What Zeus takes from this

Zeus keeps the shape, not the proxy:

- A person adds a provider, enters a key, and Zeus checks the key with a real request before
  calling the provider ready.
- The voice id is not a secret. The key is.
- Spoken text is sent only when a provider is selected and ready.
- The default remains Zeus's existing local voice.
- If the provider errors, times out, or is not ready, that turn speaks with the local voice.
  The reference companion does not do this. Zeus does, so a failed provider never leaves the
  turn silent.

Zeus stores the key in the macOS Keychain on this device, not in a proxy and not in
settings defaults. The reference companion's proxy is a deployment choice for people who
build that app. It is not the storage Zeus uses.
