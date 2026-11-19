# DESIGN: Scribe speaker names

Owner ask (2026-11-11): Scribe shows who is speaking by name, never "Speaker 2" when a name can be known.
Evidence: private research notes (kept outside this repo). Engine plan: `SPEAKER-IDENTIFICATION.md` (S1 to S9).

## Principles
1. A name is a claim with a source and a confidence. Sources, strongest first: typed by you, saved voice, call
   window, calendar plus introduction, introduction alone. Stored per speaker in the meeting file.
2. Never a wrong name with confidence. When unsure, show the colour and "Naming…", then the name when it lands.
3. Live first, corrected after: the batch pass at stop can change labels; names follow the voice, not the number.
4. Nothing leaves the Mac. Accessibility, calendar and saved voices are each optional; Scribe still works without.

## Name binding (S8, ZeusCore pure)
- Input A: diarizer turns `(voice, start, end)` per channel. Mic voice 1 is You.
- Input B: call-window observations every 0.5 s while recording: `[(name, isSpeaking, isMuted)]` plus roster.
- Spans: a participant speaks from first to last lit observation; gap over 1.5 s closes a span.
- Votes: for each system-channel voice, overlap seconds with each participant's spans, weighted by span length.
- Bind when the winner has at least 4 s overlap, at least 60 % of that voice's overlapped time, and leads the
  runner-up by 2x. Withhold when two meeting windows or two call apps are active, or windows disagree.
- Muted participants never win a vote. "(You)", "(Guest)", "(External)", "(Invité)", "(Externe)" suffixes stripped.
- A typed name is never overwritten. A declined suggestion is never offered again for that voice in that meeting.
- Calendar roster narrows candidates: a call-window name matching an attendee gets +1 confidence step.

## Screens
**Live (notch and Scribe page)**
- Top: "Now speaking" pill. Initials disc in the speaker colour, full name, a tiny source glyph
  (window icon = call, waveform = saved voice, calendar = invite). Cross-fades within 150 ms of a turn change.
  Reduce Motion: no fade.
- While unresolved: colour disc with "…", label "Naming…". When a name lands, earlier lines of that voice relabel
  in place with a one-time soft highlight (no layout jump).
- Transcript lines: name chip in the speaker colour, time, text. You is always "You".
**Recap**
- Header: people chips (initials, name, talk share). Unconfirmed names show a dotted outline and "Confirm".
- Speaker row: tap name to edit inline; Enter saves for the whole meeting, notes, export and copy.
  Below: three longest lines of that speaker as the sample (audio is never kept).
- Suggestions under the row: "Marie Dubois? (from the call)" with Accept and Not them.
- Merge: typing a name another speaker has asks "Merge into Marie Dubois?" with Undo for 10 s.
- Tiny voices (under 2 % talk time and under 3 lines) fold into "Other voices" with Review.
- "Remember this voice" checkbox, off by default, with the line "Only save voices of people who agreed."
**Settings > Scribe > Speakers**
- Speaker recognition model: Download (size), progress, Ready, Remove.
- Names from the call window: status (needs Accessibility, granted / not granted, Open Settings button; never a
  prompt), per-app support list.
- Saved voices: list, rename, delete, delete all.
- When a call starts: Ask me / Start recording / Do nothing.

## Accessibility of our own UI
VoiceOver reads "Marie Dubois is speaking, from the call" on change (polite announcement, at most every 3 s).
All chips have labels; colour is never the only signal (initials and names always shown).

## Acceptance
- Synthetic timeline tests: correct binding, withheld on ambiguity, muted never wins, typed name kept.
- Snapshot tests: live pill (named, naming, you), recap with suggestions, merge undo, settings page.
- Live (owner Mac): Teams or Meet call with 2 people plus owner: both named from the window within 30 s of
  speaking; rename one, tick Remember, next call: named before the window binds.
