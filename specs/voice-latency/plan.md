# Implementation Plan: Voice latency

**Branch**: `zeus-bot/voice-latency` | **Date**: 2026-11-19 | **Spec**: [spec.md](spec.md)

## Summary

Add a duration-only harness, keep the capture engine prepared while listening is enabled, stream partials, finish short phrases against a warm recognizer, and run a local fast path before the language model. Do not drop the installed talk cues or the right-Command tap rule.

## Technical Context

**Language/Version**: Swift 6

**Primary Dependencies**: The existing speech capture and the workspace APIs already in the app. No new package.

**Storage**: None. Durations are logged, not stored as audio or text.

**Testing**: Swift Testing. Red first. Hosted macOS for the measured table. Linux cannot compile the app target.

**Target Platform**: macOS

**Project Type**: Native macOS app

**Performance Goals**: See spec SC-001 to SC-004.

**Constraints**: Log durations only. Keep cues. Keep the tap-versus-modifier rule. A second hold must still capture. Do not change Package.swift, workflows, or CI timeouts.

**Scale/Scope**: One push-to-talk path and the listed local commands.

## Constitution Check

*GATE: Must pass before implementation.*

- Simplicity: one trace type and one fast-path matcher. No second UI.
- Red-first: a failing harness test before the timing code, then the budgets.
- Clean-room: no third-party product names in new code.
- Privacy: the log has no audio and no transcript.
- Motion and accessibility: cue audio is not motion. Reduce Motion does not silence it.
- Preserved surfaces: top bar springs stay. The talk cue stays.
- Gates: the baseline is the hosted job on the exact head. No invented milliseconds.

## Project Structure

### Documentation (this feature)

```text
specs/voice-latency/
├── spec.md
├── plan.md
├── tasks.md
└── checklist.md
```

### Source Code (repository root)

- `Sources/ZeusCore/Voice/VoiceLatencyTrace.swift` stays the spoken-answer trace. A separate dictation trace is added so that log format does not change.
- `Sources/Zeus/Voice/SpeechInput.swift` is where the engine is built per turn today. Pre-warm replaces that per-press setup. The second-hold silence bug stays covered.
- `Sources/Zeus/Voice/HotkeyMonitor.swift` already plays the installed cues and the right-Command tap. Those calls stay.
- Fast path: a pure matcher in ZeusCore, called before the language-model request, with the model request allowed to start in parallel and discarded on a hit.

## Design notes

The current capture builds a fresh engine on every `start()` because reusing one engine after `stop()` came back silent on the second hold. The new requirement is the opposite shape: keep the engine and input node prepared while listening is enabled. The implementation has to prove both the 50 ms budget and a second hold that still receives audio. If those two cannot be true together without a larger redesign of capture, stop and say so. Do not delete the second-hold regression.

The existing `VoiceLatencyTrace` starts at key-up and is the spoken-answer path. Do not overload its log line. The dictation harness is a new trace.
