# Scribe input boundary and end workflow

Updated 10 November 2026. This implementation is verified with synthetic automated
scenarios; it is not a claim that native device behavior or reference motion has
passed. No microphone, screen or system-audio capture was started during this work.

## Microphone admission

`ScribeMicrophoneIngress` now runs before the microphone callback reads sample
memory or writes the application ring. The entire buffer must belong to the
acknowledged recording and fit within fresh, completed, unmuted evidence. Missing
timestamps, startup buffers, stale/unknown/muted evidence, stopped/replaced
sessions, and a contended admission lock all fail closed. The callback never
blocks: it tries the lock and drops the buffer if it cannot get it. The permit is
held through the ring write, so a completed revocation cannot be followed by a
copy admitted under the old permit. Existing drain-time history and ASR routing
checks remain in place. Rejected intervals reset resampling continuity and retain
their withheld-audio report even if newer evidence later becomes unmuted.

Any positively observed external microphone owner, including an unsupported app,
latches local microphone exclusion for the monitor's lifetime. A later empty
scan, mute-induced input release, or Stop/Start cannot clear it. Idle applications
do not create this latch and do not count as calls. There is deliberately no
absence-based rearm or mute override. This conservative policy can omit the local
speaker after external input use; system audio is a separate source.

**The absolute strict-mute requirement remains open.** CoreAudio ownership and a
polled device mute property are not a synchronous per-call mute signal. The gate
cannot know a transition before the OS reports it, prevent OS-owned AVAudioEngine
buffers, or recover historical call state across an app restart. A supported
call-specific mute adapter or a different source contract is needed before
claiming that physical mute always means zero hardware capture. The new guarantee
is rejection at the application's input boundary for the evidence it has.

## Real end triggers

Explicit Stop arms a nine-second monotonic deadline. A second supported trigger is
a positive `NSWorkspace.didTerminateApplicationNotification` for the exact native
call-app instance bound when the person chooses Record on its detected-call
popup. Binding includes PID, bundle ID and launch time; PID reuse and unrelated
application exits cannot end the recording. The message says the call app closed.
Browser hosts, calendar-only prompts and manual starts have no automatic call-end
binding. Microphone disappearance, missing window titles, silence and a calendar
end time are never treated as a call ending. Remote hang-up detection is not
implemented.

Keep recording cancels the deadline until a stop request has been sent. A consumed
application-exit notification cannot rearm it after Keep; explicit Stop can arm a
new deadline. End now and expiry share the same one-time stop gate. Capture stays
in its ending state until the provider acknowledges that it ended. A native end
window and the Meetings tab display the same live state; closing the window only
hides it. Fake-controller tests have native window creation disabled.

## Save and completion

Final notes must persist successfully before production emits `notesReady`, enters
`complete`, reveals a saved note or shows successful top-bar feedback. A failure
keeps processing active, retains the recap and any earlier transcript checkpoint, and offers
Retry save. Retry uses the newest in-memory private-note edits and does not
regenerate the note. Explicitly discarding an unsaved final note also removes its
earlier transcript checkpoint; failed deletion retains the existing cancellation
tombstone and retry behavior. Success feedback expires after five seconds with a
session guard; a reset or new recording clears it immediately.

## Automated verification

The portable group exercises the actual input-boundary class, end-workflow model
and save-before-completion method with fake copies, timestamps and persistence
results:

```sh
python3 qa/portable-core/prepare.py --group scribe --run
```

The current-source portable group passed **151 tests in 15 suites**, including
eight input-boundary, three durable-completion and seven end-workflow regressions.
The validation manifest matches the copied production files and extracted pure
declarations. This result excludes native controller and device execution.

The native controller suite uses inert capture providers, an injected monotonic
clock and temporary synthetic meeting files. It asserts countdown cancellation,
one-time stopping, save failure and retry, actual top-bar feedback, newest private
notes, stale application-exit suppression, and explicit checkpoint deletion:

```sh
swift test --filter ScribeLifecycleScenarioTests
```

Linux cannot execute that native AppKit suite. A syntax parse is not a native
typecheck or test pass. Complete native build/scenario receipts, automated
accessibility/layout and motion scenarios, and owner-consented device scenarios
remain required. Human/manual clickthrough is not part of this verification plan.
