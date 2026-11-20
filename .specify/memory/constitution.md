# Zeus Constitution

## Core Principles

### I. Simplicity (Linear hierarchy, Apple Notes plainness)

Zeus stays a native macOS app. A surface MUST read like a plain note and work
like a compact list: one primary action, a clear hierarchy, and the next step
visible without decoration. Detail opens in place. The terminal is an explicit
button, never the default destination. Do not copy another product's assets,
layout, or chrome. Meaning comes before decoration.

### II. Red-first tests (NON-NEGOTIABLE)

A behavior change starts with a failing test that names the required outcome,
then the implementation that makes that test pass. MUST NOT weaken, skip,
early-return, hide, or reinterpret a test or gate to obtain a pass. MUST NOT
change a test to match an unintended implementation. A missing proof stays
blocked. Linux checks do not count as the native app.

### III. Clean-room

New code, comments, commits, and specs MUST NOT name third-party apps. Identify
a call or media app only when the accepted spec for that feature already
requires it, using the names that spec allows. Do not import another product's
runtime, vault, or private workflow.

### IV. Privacy by default

Features are local-only unless a default-off setting, left unbuilt until
explicitly accepted, says otherwise. MUST NOT log audio, transcripts, emails,
notes, briefs, or secrets. Tests use synthetic records, generated audio, and
disposable local vaults. No microphone, screen, or audio capture without the
user's own OS consent. Never script a permission prompt.

### V. Motion and accessibility

Respect Reduce Motion and Reduce Transparency. Motion explains a state change
and stays interruptible. With Reduce Motion, state changes are immediate or a
short crossfade, and nothing bounces. Keyboard and VoiceOver MUST be able to
complete the same action. Status MUST NOT depend on color alone.

### VI. Local without a model (NON-NEGOTIABLE)

Tony, 13:34 BRT (t242u). He runs out of LLM tokens often, so the local
surfaces MUST work fully with no model and no network. Face unlock, presence,
approvals by face or Touch ID, music transport, multi-monitor, Settings, and
onboarding have ZERO dependency on Claude or any other LLM or the network.
The face path is on-device Swift using Vision and Core ML only. A red-first
test runs that pipeline with network and LLM clients disabled or stubbed to
throw, and fails if either client is entered. Where an LLM feature such as
explain is unavailable, it shows a clear message and MUST NOT block a local
feature. Zeus stays Swift. It is not rewritten in another language.

## Preserved surfaces

The top bar's existing visuals, springs, and animations stay as they are unless
the change's spec says that surface is in scope. A side fix MUST NOT restyle
the top bar, drop a cue sound, or change the right-Command tap-versus-modifier
rule. Push-to-talk cue sounds stay.

## Quality gates

Acceptance is the exact head that was reviewed, not an older receipt, a test
count, or a nearby commit.

- Hosted Zeus checks (app, feature-map, extension, release-scripts, and
  required-checks) run on that head. A red or cancelled app job is not a pass.
- Sentinel reviews the privacy and permission boundary before a feature that
  touches capture, calendar, contacts, or logging is treated as done.
- Devin reviews that same head. A review of a different SHA does not carry over.
- Do not freeze a head until those gates are green for that SHA.
- MUST NOT change Package.swift, workflows, entitlements, or CI timeouts to
  make a run finish.

## Governance

This constitution is the standing bar for Spec Kit specs, plans, and tasks.
It does not override the user's instructions, consent, or tool permissions.
An amendment is an explicit edit to this file with a version bump: MAJOR when a
principle is removed or redefined, MINOR when a principle or section is added,
PATCH for wording that does not change a rule. Ratification date stays fixed.
Every feature spec starts from these principles and names measurable acceptance
criteria before implementation.

**Version**: 1.1.0 | **Ratified**: 2026-11-19 | **Last Amended**: 2026-11-19
