# Security and resource review

This is an engineering checkpoint, not a security certification or release
approval. The exact acceptance obligations remain in `qa/feature-map.json`.
Native control, consented hardware, signing and distribution proof remain required.

## Repairs in this checkpoint

- Local socket replies run away from the caller with a bounded deadline, peer
  count and message size. A non-reading client must not freeze the main actor or
  prevent Stop controls from responding. Disposable socket tests exercise the
  stalled peer and exactly-once reply/descriptor ownership.
- MCP input has one-chunk backpressure, bounded messages and pending requests.
  Writes cannot block the actor that processes cancellation and timeouts. A
  partial write or malformed message ends the transport; uncertain exports keep
  their existing journal/readback rules rather than automatically replaying.
- Untrusted JSON-RPC numeric IDs and error codes cannot trap integer conversion.
  Bridge pending replies retain the original request when a duplicate ID arrives.
- Microphone-status reads have a bounded number of in-flight workers. Hung OS
  reads cannot accumulate replacement workers; stale evidence remains unknown.
- Credential deletion succeeds only when the backend confirms removal or absence.
  Failed deletion retains truthful saved state and an error. Partial license
  cleanup survives relaunch and remains retryable. Delayed activation responses
  cannot restore credentials after an explicit deactivation.
- Provider logos identify supported integrations. Their source versions and
  hashes are recorded; images use a bounded cache instead of repeated file decode.
- Recording effects use display-synchronized clocks, pause when hidden or reduced,
  and stop after finite reveals. Meetings separates decorative drawing from
  static content. Incoming-word layout is cached until actual text admission.

The tests use memory-only credentials, synthetic data, disposable vaults and
local subprocesses. They do not read a personal vault, use provider credentials,
grant permissions or capture microphone/screen/system audio. Tests of the native
Keychain adapter, actual GUI and hardware have narrower platform requirements
than the portable cache, geometry and transport tests.

## Evidence still required

The requested 240 FPS target requires a compatible physical display and measured
presentation within a 4.17 ms budget. Model samples, callback timestamps and
generated previews cannot establish GPU presentation, CPU load or energy use.
Measure idle and active CPU, memory, energy, frame pacing and input responsiveness
on the actual app, including a long session, hidden windows and mixed displays.

Literal hardware-level “nothing captured while muted” remains unproved. The app
rejects prohibited frames before its own ring and rechecks admission, but sampled
OS evidence and OS-owned buffers prevent a stronger claim without device proof.

The current Mac test host does not expose the required accessibility tree.
Strict accessibility assertions remain mandatory and separate from the new
owned-window event journeys. A failure or an unavailable GUI is not a passing
user journey. Signing, notarization, Gatekeeper, rollback and clean-machine
installation also require evidence from the exact final artifact.
