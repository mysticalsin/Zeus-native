# Sweeps

## Security — voice quality presets (#237)

Lens: key handling, meter tamper and races, endpoint host pinning, error and log leakage. Sentinel notes from #145 are included: control characters in keys, and redirects that would replay key headers.

Red: `1721196e85a9a61dd5e18a8c92ffceb1e072c13c` (tests only; the route and gate types were absent).

### Findings

1. A key with an embedded newline, CR LF, tab, or NUL was accepted and placed in `xi-api-key` or `X-Goog-Api-Key`. The meter was charged before the request failed. That is header injection, and the error path could have echoed the key.
2. The meter file was opened with `Data(contentsOf:)`, which follows a symlink. A swapped link would read or replace another file.
3. One speak request could be as large as the whole 50,000 character budget. There was no per-request cap.
4. Built URLs were the two provider hosts, but nothing checked the host again before send.
5. `URLSession` on Linux crashes if a `URLProtocol` asks it to follow a redirect (`swift-corelibs-foundation` does not handle redirects). The quality path must refuse the redirect in the task delegate instead of following it. A 302 to another host would otherwise be a place a key header could be replayed.
6. Cloud presets could be applied from the stored preset alone. #229's `PersonaSpeakRoute` stays on `zeus.synthetic` unless that provider is selected and a key exists.

### Fixes

- `VoiceQualityKeyGate` trims, then refuses any remaining character below U+0020, DEL, or whitespace. The error text is exactly `The key is not valid.` The meter is not charged. `publicName` maps URLSession errors to a fixed failure name and does not use the localized description or header values.
- The meter file is opened with `O_NOFOLLOW`. A symlink fails closed and the target is left unchanged. Reads stop at 65,536 bytes.
- A single request is capped at 5,000 characters, before the meter. The 50,000 cumulative ceiling is unchanged.
- `VoiceQualityEndpoint` allows only `https://api.elevenlabs.io` and `https://texttospeech.googleapis.com`, with no userinfo.
- `VoiceQualityRedirectDelegate.willPerformHTTPRedirection` returns nil. The test stub answers 302 with a `Location` on `collector.example` and does not ask Linux URLSession to follow it. The delegate is invoked with that redirected request and returns nil. The second host is not contacted and the key is not on a request to it.
- `VoiceQualityRoute` reads `PersonaSpeakRoute.chain`. A preset is used only when that chain starts with the same cloud step. Automatic, a missing key, a mismatched preset, and a failed provider stay on `zeus.synthetic` and do not open a request.
- The in-process meter lock still makes two concurrent 30,000 reserves succeed once.

No file from #229 was edited.
