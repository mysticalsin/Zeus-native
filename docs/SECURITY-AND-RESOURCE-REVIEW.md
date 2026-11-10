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
- Native-host framing validates the four-byte header before retaining its body.
  Output admission is bounded to 32 frames / 8 MiB with absolute write deadlines.
  A broken stream closes the host; clean EOF drains accepted responses first.
- Browser extension callbacks and replies belong to their original native
  connection. Retired messages cannot dispatch new work, clear a replacement
  connection or settle its reused request IDs. A failed handshake is displayed as
  disconnected. This does not undo browser actions already dispatched before a
  disconnect or establish a complete browser recovery journey.
- The extension's locked esbuild version is updated to 0.28.2, outside the affected
  range for [GHSA-67mh-4wv8-2f99](https://github.com/advisories/GHSA-67mh-4wv8-2f99).
  That advisory affects its development server; Zeus uses the build CLI. CI now
  audits development dependencies too and blocks on moderate-or-higher findings.
  A clean registry audit is a dependency check, not a security certification.
- Local Python helper execution now bounds stdin writes, stdout/stderr retention
  and termination cleanup. A helper that ignores SIGTERM cannot turn a timeout
  into a reported success. This does not establish task cancellation or kill an
  arbitrary descendant process tree.
- Custom OpenAI-compatible endpoints require HTTPS outside exact loopback hosts.
  Both request construction and dispatch enforce this; redirects are not followed
  with prompts or credentials. Changing the address, model or key invalidates the
  previous connection check. Unknown sign-in status remains unknown, and app-only
  launchers do not advertise unsupported prompt delivery.
- Microphone-status reads have a bounded number of in-flight workers. Hung OS
  reads cannot accumulate replacement workers; stale evidence remains unknown.
- Credential deletion succeeds only when the backend confirms removal or absence.
  Failed deletion retains truthful saved state and an error. Partial license
  cleanup survives relaunch and remains retryable. Delayed activation responses
  cannot restore credentials after an explicit deactivation.
- Provider logos identify supported integrations. Their source versions and
  hashes are recorded; images use a bounded cache instead of repeated file decode.
- Voice diagnostic sinks share one redacted record. Wake transcripts, conversation
  text and provider errors use metadata unless content logging was explicitly
  enabled; that option never bypasses credential redaction. Oversized diagnostics,
  including one grapheme with many combining marks, are omitted before expensive
  pattern matching rather than publishing truncated credential fragments.
- Recording effects use display-synchronized clocks, pause when hidden or reduced,
  and stop after finite reveals. Meetings separates decorative drawing from
  static content. Incoming-word layout is cached until actual text admission.
- The resident Kokoro worker now acknowledges an atomic completed WAV before the
  app validates and publishes its own exclusive copy. Requests, output size,
  cancellation, cleanup and idle lifetime are bounded; stale replies cannot
  complete a replacement request. Synthetic fixtures execute the production
  worker protocol with disposable modules, without loading a voice model.
- WAV decoding validates the complete declared RIFF structure before reading
  chunk fields or samples. Truncated chunks and malformed PCM are rejected;
  sliced `Data` uses buffer-relative offsets. A previously crashing 44-byte
  fixture is retained as a regression test.
- Repeating UI clocks invalidate their timers when their owner is released.
  Hidden, occluded or minimized onboarding windows stop polling, and cancelled
  notification refreshes cannot publish stale status. Cloud-only selections do
  not warm a local voice model; only the selected, ready local voice is warmed.

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

At `dd19cb5`, the PR run compiled production and test targets and executed every
selected partition. Eighteen App suites completed with 147 passing tests. Core
and three GUI partitions still failed; the aggregate is not a native pass. See
[the exact run receipt](../qa/receipts/20261110/mac-dd19-ci.json). Suite isolation
preserves strict assertions and complete compiler-derived test selection. A
separate push run emitted a compiler internal error despite exit code zero;
the compiler barrier correctly rejected it.

The subsequent resident-worker, WAV and idle-resource repairs above have focused
source-bound synthetic evidence and independent review. Fresh native compilation
and execution remain required. Bounded worker lifetimes do not prove measured
CPU, energy or real-voice latency, and ordinary file syscalls do not provide a
hard real-time deadline or an arbitrary descendant-process sandbox.
