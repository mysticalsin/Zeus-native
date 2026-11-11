# Superwhisper and Plaud: how they work (REA, 2026-11-11)

Scope: installed apps on the owner's Mac, inspected from outside only. Superwhisper 3.1.0
(`com.superduper.superwhisper`) and Plaud Desktop 1.3.13 (`ai.plaud.desktop.plaud`). Methods: bundle listing,
Info.plist, entitlements, `strings`/`nm` on binaries, Plaud's Electron `app.asar` JavaScript read in a scratch
directory, model folder names and sizes, database schema only. Neither app was launched. No recording, transcript or
personal row was read. No code, prompt or asset is copied into Zeus.

Labels: **O** observed in the installed app, **D** vendor docs, **I** inferred, **U** unknown.

## 1. Superwhisper

### Who is speaking (diarization)
- **O** Live model: NVIDIA Nemotron-3 Diarization (Sortformer family, up to 8 speakers, about 100M parameters),
  Core ML fp16 "fast32", 190 MB, from `FluidInference/nemotron-3-diarization-coreml`, in
  `~/Library/Application Support/superwhisper/models/superdiarize/streaming-eend/`. Licence OpenMDW-1.1.
- **O** It runs through FluidAudio (`Nemotron3Diarizer` and the other FluidAudio diarizers are linked), wrapped by
  their own Swift module `SuperDiarize` (StreamingDiarizer, DiarizationSession, MicrophoneSpeechGate, SileroVAD).
- **O** Two passes: streaming labels while recording, then a batch Nemotron pass at stop gives the final labels
  ("final attribution from batch Nemotron pass"). If labelling fails, audio and text are kept.
- **O** Older fallback: Argmax SpeakerKit pyannote segmentation plus a speaker embedder (ONNX, 5.6 MB + 25 MB).
- **I** Microphone and system audio are separate channels, so "you" comes from the mic channel.

### Putting names on speakers
- **O** The key trick: Accessibility reading of the call window (`MeetingSpeakerSource`). It reads the participant
  roster and the "is speaking" highlight in Zoom, Teams, Meet (browser), Slack huddles and FaceTime, then binds a
  name to the anonymous voice that was talking at the same moment ("Applied AX names").
- **O** Safety rules: no name when two meeting windows are open, when windows disagree on who speaks, or when more
  than one meeting app is active.
- **O** Manual "Assign speakers": click a name, change it for the whole transcript, play samples after the
  recording ends. Manual names override automatic ones.
- **O** Calendar attendees are stored with the recording and given to the summary model; not used to cluster.
- **O** No saved voice library: no voiceprint table in the database; voices are matched only within one meeting.
- **D** Complaint: names cannot be edited in the newer History view, and copied text loses names.

### Recording and starting
- **O** System audio: Core Audio process tap in an aggregate device (macOS 14.4+), ScreenCaptureKit as fallback.
  Health check restarts capture.
- **O** Meeting start, three ways: manual; calendar nudge before a meeting; automatic call detection from "which
  process holds the microphone" (maps helper processes to their parent app), then either a prompt or auto-start
  (`autoStart` setting).
- **O** Stop: sustained microphone release, the browser tab releasing the mic, or Accessibility showing no call
  controls, with a hold timer before ending.
- **O** Entitlements: microphone, calendars, Apple Events. Usage strings: Accessibility, audio capture, calendars.

## 2. Plaud Desktop

### Why it starts by itself
- **O** It watches per-process audio activity with a native Core Audio module (`audio_monitor_mac.node`), not the
  calendar. There is no calendar code at all.
- **O** Process names map to apps: Zoom, Meet, Teams, Slack, Discord, Webex, WhatsApp, Lark, and any browser
  (one "browser" bucket, no tab or URL check). Debounced 1 s.
- **O** Settings `enableAutoRecord` (silent start with a notification) and `enableMeetingStartNotify` (ask first),
  plus a consent timestamp when auto-record was first turned on. On this Mac both are on, which is why it starts
  by itself.
- **O** Stops when the same app's audio goes quiet. Zoom gets 2.5 s of grace (breakout rooms). A second meeting
  while recording shows a "next meeting" prompt instead of switching.

### Audio and speakers
- **O** System audio by Core Audio process tap and aggregate device; mic captured separately with WebRTC echo
  cancellation, then **I** mixed into one OGG.
- **O** Transcription and speaker separation are cloud only: the file is uploaded to S3 and processed with
  `diarization:1`. Nothing runs on the Mac.
- **D** Speakers are "Speaker 1, 2"; only your own voice can be labelled automatically after you record a voice
  profile; everyone else is renamed by hand.

## 3. Zeus today vs them

| Capability | Superwhisper | Plaud | Zeus today | Zeus next |
|---|---|---|---|---|
| Call detection | Mic owner process | Per-process audio | Mic owner process, 5 s poll, plus calendar | Event-driven Core Audio listeners, poll as backup |
| Starts by itself | Option | Option (on here) | Prompt only | Opt-in auto-start with first-use consent, visible indicator |
| Auto-stop | Mic release + hold + AX controls | Audio quiet, Zoom grace | Prompt on app exit | Mic release + grace, call controls gone, next-meeting prompt |
| Separation model | Nemotron-3 on device + batch pass | Cloud | Hand-built voiceprint | Nemotron-3 via FluidAudio live, batch pass at stop (WeSpeaker as small fallback) |
| Names | Call window (Accessibility) + manual | Manual, own voice profile | None | Call window names + saved voices + calendar and introductions + manual |
| Remembers voices | No | Own voice only | No | Opt-in per person, local only |
| Audio leaves Mac | Only for cloud ASR choices | Always | Never | Never |

## 4. Build slices added to `SPEAKER-IDENTIFICATION.md`

- **S7 Auto-start.** Setting "When a call starts: Ask me (default) / Start recording / Do nothing", first-use consent
  timestamp, event-driven `kAudioProcessPropertyIsRunningInput` listeners on known call processes (poll stays as
  backup), stop after sustained mic release (grace 8 s, Zoom breakout safe), "next meeting" prompt while recording.
  Recording indicator always visible. Core tests for the policy reducer.
- **S8 Call-window names.** Accessibility read of Zoom / Teams / Meet participant tiles and speaking highlight
  (only when Accessibility is already granted, never prompted), bound to diarizer clusters by time overlap, withheld
  when ambiguous, manual names win. Core tests on the binding with synthetic timelines.
- **S9 Nemotron-3.** Swap the live embedder path for FluidAudio's Nemotron3 diarizer when downloaded; batch pass at
  stop relabels the recap.

## Probe: how call apps expose speakers

Slice S8 (call-window names) depends on what each app publishes through Accessibility. Run this once per app during a
live call, from Terminal with Accessibility enabled (System Settings > Privacy & Security > Accessibility). Do it
yourself; it is read-only and local, and the trust check never prompts.

```bash
cd "<repo>/Zeus-native"
xcrun swift scripts/call-ax-probe.swift --app zoom  --seconds 30     # or teams | meet | slack | auto
# alternative: scripts/call-ax-probe.sh --app teams --seconds 30   (compiles first, same flags)
```

Output goes to `~/AI-Brain-build/call-ax-probe/<timestamp>/` (`snapshot-<app>-<n>.jsonl`, `diff-<app>.jsonl`). Names
are hashed by default (same name, same 8-hex hash within a run) so the structure and indicator words stay readable;
add `--no-redact` only for your own eyes. Chromium/Electron apps (Chrome for Meet, new Teams, Slack) may get
`AXManualAccessibility` / `AXEnhancedUserInterface` switched on while the probe runs, and it restores them on exit.

What to do during the run: have 3+ participants if possible, let different people talk, mute and unmute yourself once.

What to look for in the stdout summary and files:

- **Roster:** a parent node with several person-like siblings (`roster candidates`). Note the role chain and which
  field carries the name (title, description or value), and whether it also carries state like "muted".
- **Speaking indicator:** nodes under `most-changing nodes` and `diff-<app>.jsonl` entries whose title, description,
  value or selected flips when someone talks (text like "speaking", a selected tile, a changed subrole).
- **Dead ends:** an empty or tiny tree for an app means the indicator is drawn without Accessibility support; report
  that as a "no" for that app.

## 5. Deeper pass: how Superwhisper binds names (2026-11-11, second pass)

Binary is stripped, so type and property names come from `strings`; the algorithm is **I** from those names.

- **O** One Accessibility source per app: `ZoomSpeakerSource`, `MeetSpeakerSource`, `TeamsSpeakerSource`,
  `SlackHuddleSpeakerSource`, behind a `MeetingSpeakerSource` protocol, driven by `MeetingSpeakerMonitor` (polling,
  `consecutiveEmptyPolls`, `hasAmbiguousWindows`, `hasConflictingWindowSpeakers`).
- **O** Per participant: `name`, `isMuted`, `isActiveSpeaker`, `rosterSize`. Polls fold into `MeetingSpeakerSpan`
  (open span, `maxObservationGap`), then `MeetingSpeakerVotes` and a `MeetingSpeakerTimeline` winner per anonymous
  voice ("mint"). Binding is confidence-gated (`confidencePromotedMints`), later evidence can correct automatic
  names, declined names are remembered (`declinedAutoNames`).
- **O** One streaming diarizer per channel (`micStreamingDiarizer`, `systemStreamingDiarizer`); the mic voice is
  `sharedMicSelfMint` (you). Words are mapped to speakers by overlap (`overlapMinimumCoverage`,
  `nearestSpeakerMaximumGap`).
- **O** App signals: Meet active tile class `__video-frame--active`, tile labels "profile picture of";
  Slack `p-huddle_peer_tile`, `__overlay--active_speaker`, `__name_overlay--muted`; generic " is speaking",
  ", active speaker", "muted"; suffixes stripped " (Guest)", " (External)", " (You)". English only.
- **O** UI: inline `MeetingSpeakerNameField`, sample cards, "Identifying this speaker" while unresolved,
  "Reassign this block to", "Assign selected words to", merge warning "can't be undone". No avatars in assets.
- **O** Storage: `meta.json` per recording with `speakers[{number,name}]` and `segments[{speaker,start,end,words}]`.
  The name source is not saved, so a reopened meeting cannot tell an automatic name from a typed one.
- **O** On this Mac: 3 meetings; one shows 6 speakers where 3 hold very few segments (likely spurious clusters).

Where Zeus will beat it: saved name source and confidence per speaker, audio-plus-tile agreement before binding,
cross-meeting voices (opt-in), calendar roster as a prior, French and other languages in the tile patterns,
undoable merge, pruning of tiny spurious speakers, live "now speaking" chip with retroactive relabel.
