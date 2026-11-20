# Spec: companion parity

Status: specification only. No behavior in this folder has been implemented or run.

Audience: Tony. Zeus is the native macOS notch and top-bar assistant. The bar is the public behavior of the reference companion (a cursor-side buddy that listens, looks at the screen, speaks, and points), then past it: faster first audio, numbered marks, a privacy lamp, and controls that keep working with no model and no network.

The reference companion is not named in this tree. Its behavior is summarized in `gap-matrix.md`. Nothing from its source is copied.

Design of later UI slices follows `docs/DESIGN-DIRECTION.md` and keeps Zeus's own identity. This spec does not add a product surface by itself.

Row ids (R1–R39) are defined in `gap-matrix.md`. Budgets are defined in `perf-budgets.md`. Proof steps are defined in `e2e-proof-plan.md`. Delivery slices are defined in `plan.md`.

## Stories

### S1. Hold Right Option and Zeus is already listening

Tony holds Right Option. The buddy beside the pointer shows the listening pose and the notch shows the same phase before the microphone session returns. He speaks, lets go, and the turn is sent. A tap shorter than the confirm types a character and does not talk. A mouse-down during the confirm cancels the hold.

Acceptance:

- R1 and R37. p95 from the key event to the `listening` phase is under 50 ms (`perf-budgets.md`).
- R2. Right Command still dictates and does not start this turn.
- R3. Control+Option remains the primary talk key. With VoiceOver on, Zeus leaves Control+Option to VoiceOver and speaks the key it moved to.
- R4. A double-tap latches listening until silence, Escape, or a second press.

### S2. The first word arrives while the rest is still being written

Tony lets go of the key. He hears the first sentence before the model has finished the reply, and before the rest of the audio exists. A point tag at the front of the reply flies the buddy without holding that first sentence.

Acceptance:

- R5. The caption shows stable partials during the hold. Key-up commits them within the on-device budget and does not wait out a second recognition pass.
- R6 and R7. On at least 27 of 30 direct-stream turns, the first-audio signpost precedes the end of the model stream. p50 and p95 meet the route table in `perf-budgets.md`.
- R29. Connection warm-up runs on key-down and is not on the 50 ms indicator path.
- R30. Screen capture overlaps speech. The answer does not take a second capture after key-up.

### S3. He can talk over Zeus

Tony holds the key again while Zeus is speaking or flying. Speech, the flight, the caption, and the capture stop together. The buddy is listening again. Sound is gone within 150 ms of that hold.

Acceptance:

- R8. One transition: `speaking` to `interrupted` to `listening`.
- R25. A failure takes the same shape: one short spoken line, lamps off, pointer cleared, next hold listens.

### S4. Zeus looks, and points with numbers

Tony says "point at the second button" while a window is on screen. Zeus captures during the hold, names the control, paints a numbered badge on it, and flies the buddy there. On a second display the badge is on that display. If Screen Recording is off, Zeus says it cannot see the screen.

Acceptance:

- R9, R10, R11, R12, R13, R18, R31.
- Up to six numbered badges, in the order of the sentences that mention them.
- VoiceOver hears "Mark 2" plus the label (R27).
- Own windows, including the badges, are absent from the next capture.

### S5. The buddy is alive, and still when asked

The mascot sits beside the pointer in a pose that matches the phase: listening, thinking, speaking, pointing, interrupted, error. At 60 Hz and at 120 Hz a spoken reply drops no frames. Reduce Motion shows the rest pose and a single move. After the turn, the default policy lets him leave.

Acceptance:

- R14, R15, R16, R26, R28, R33, R38.
- The notch and the buddy show the same phase.
- The waveform tracks the microphone when motion is allowed, and holds still when Reduce Motion is on.

### S6. He can use Zeus with the network gone

Airplane mode. No model key. Face unlock still accepts Tony's enrolled face and rejects another. Time, date, arithmetic, and the fast commands still answer from the notch in under 150 ms. A question that needs a model gets one spoken sentence that says so. Dictation still types.

Acceptance:

- R19, R20, R21.
- No brain process starts for an instant command.
- The camera for face presence stays off until Tony has switched that feature on.

### S7. He can see when Zeus is listening or looking

The moment the microphone opens, the notch shows a mic lamp. The moment a capture starts, it shows a screen lamp. Both go out when that use ends. Zeus stays out of screen shares when that setting is off. Turn text is not logged.

Acceptance:

- R22 and the privacy rules in `e2e-proof-plan.md`.
- Latency lines keep the existing shape: stages, engines, and a reason, with no transcript and no answer (`Sources/ZeusCore/Voice/VoiceLatencyTrace.swift:54-68`).

### S8. First launch teaches the hold

The welcome guide ends with one real hold. The buddy appears, Tony holds Right Option, and Zeus answers once. Skip leaves the keys at their defaults. Reduce Motion crossfades the guide.

Acceptance:

- R23.
- The hold step uses the same turn machine as a normal hold (S1–S3).

### S9. Settings keep the current mascot, and can hold another persona later

Settings still show the current personality choices. A new persona row defaults to the current mascot. The orb choice is off and does nothing until the orb study below is filled in. Shortcut conflicts are shown before a key is saved.

Acceptance:

- R24 and R34.
- Right Option and Right Command cannot be saved onto each other's roles (R1, R2).

### S10. Zeus remembers the conversation, and can forget it

The next hold in a session hears the last 10 turns. After a relaunch the same 10 are restored from the local vault. Screenshots and point tags are not in that vault. The privacy control wipes it. Chat's own history stays on its own store.

Acceptance:

- R17 and R36.

### S11. The Mac is driven only with consent

A request that would click, type, or run a command shows the plan in the notch. Nothing in the plan runs until Tony approves. Escape cancels the plan before the next step.

Acceptance:

- R35.

## Turn phases

The companion turn the stories share:

`idle`, `listening`, `transcribing`, `thinking`, `speaking`, `interrupted`, `error`.

Legal transitions are specified in `plan.md`. A phase with no transition in that table is a defect.

## Acceptance of this spec

This spec is accepted as a document when:

- The five files in `specs/007-companion-parity/` are the only change.
- Every required capability in the request appears as a row in `gap-matrix.md`.
- Every row has a proof ladder in `e2e-proof-plan.md`.
- Every budget in the request appears in `perf-budgets.md` with a signpost or an XCTest metric and a pass threshold.
- `plan.md` names disjoint file owners and red-first tests.
- The orb section below is still the unfilled marker.

This spec is not acceptance of the product. A later slice is proven only by the ladder in `e2e-proof-plan.md`.

---

## Orb study (unfilled)

<!-- ORB STUDY: FILL IN LATER. Do not invent the orb. A separate study owns this section. -->

Status: **unfilled**. A separate study replaces this section in a later change. Until that change lands:

- The orb has no visual, no motion, no layout, and no lines.
- The Jarvis persona has no copy and no voice.
- The setting that would select them stays off.
- The current mascot and the current Ultron and Plain personalities stay the default (R34, R39).
- `OrbPersonaTests.unfilledStudyStaysOff` is the only test this plan allows for the orb, and it asserts the setting does nothing.

Do not fill this section from the reference companion, from this spec's other stories, or from guesswork. The study writes the orb's states, the Jarvis lines, and the motion here, and only then may a slice draw it.
