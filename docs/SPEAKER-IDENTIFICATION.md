# Speaker identification in Scribe

Goal: Scribe says who is talking by name, not "Speaker 2", and tells similar voices apart.
Owner request 2026-11-11. Plan by Opus, build by Sonnet, live QA on the owner's Mac.

## 1. What Superwhisper does (research, 2026-11-11)

Label key: Documented = vendor docs say so. Unknown = not found. No claim here comes from inside the app.

| Area | Superwhisper | Evidence |
|---|---|---|
| Separating voices | Yes, on the Mac, with a separate model of about 150 MB downloaded before the first meeting | Documented, superwhisper.com/docs/modes/speaker-separated-meetings |
| Default labels | "Speaker 1", "Speaker 2"; "You" only when recording alone without call audio | Documented, superwhisper.com/docs/meetings/record.md |
| Names from the call | "Suggests names from the call" in Zoom, Meet, Teams, Slack huddles; how is not stated | Documented (mechanism Unknown) |
| Calendar | Fills meeting title and attendee list from macOS Calendar; not matched to voices | Documented, superwhisper.com/docs/meetings/overview.md |
| Manual rename | "Assign speakers": play a sample, type the name, applies to that meeting; same name twice merges | Documented, record.md |
| Remembers voices across meetings | Not described | Unknown |
| Names from what people say ("Thanks Sarah") | Not described | Unknown |
| Known complaints | Names cannot be edited in the new History view; copied text loses names | Documented, superwhisper feedback board (2026-01-06) |
| Model, speaker limit, overlap | Not stated | Unknown |

Others (secondary sources, low trust): Granola shows real names only on Meet and Zoom, otherwise Me / Them.
Otter builds voice profiles that improve over meetings. Fireflies takes names from the invite and join events and
learns from corrections.

## 2. Where Zeus is today

- `ScribeDiarizer` (ZeusCore) clusters each speech turn by a hand-built voiceprint: 20 mel bands plus median pitch.
  Its own comment says it separates clearly different voices and is weak on similar ones.
- Microphone's first voice is "You"; every other voice is "Speaker N".
- No rename, no saved voices, no calendar names, no correction after the meeting.

## 3. What Zeus will do (better than Superwhisper on every row)

Five layers, each one useful alone. Every name that is not typed by the owner is a suggestion until confirmed.

1. **Trained voice embeddings.** Replace the hand-built voiceprint with WeSpeaker (256-d, CoreML, on the Neural
   Engine) through FluidAudio 0.18, already a dependency: `DiarizerModels.download(...)`,
   `DiarizerManager.initialize(models:)`, `extractSpeakerEmbedding(from:)`. The hand-built voiceprint stays as the
   fallback whenever the model is not on disk, so Scribe never breaks.
   - The model downloads only when the owner clicks "Download" in Settings > Scribe > Speaker recognition
     (same consent rule as Parakeet). Never at launch.
   - `ScribeDiarizer` becomes generic over a `ScribeVoiceEmbedding` (vector + kind), thresholds per kind.
     Cosine distance for WeSpeaker: same-voice threshold tuned from the FluidAudio default (0.65 speaker match);
     start at 0.5 for live clustering, documented and tested with recorded fixtures.
   - One `DiarizerManager` per recogniser, serialised under the existing `Recogniser` lock (the class is not
     Sendable). Embedding runs off the main actor, on the recognition task, as today.
2. **Saved voices (opt-in, local only).** `ScribeVoiceLibrary` in ZeusCore: `[SavedVoice(id, name, centroid,
   sampleCount, kind, updatedAt)]`, JSON in Application Support/Zeus/Voices, file protection complete, never
   uploaded, never in the vault.
   - A voice is saved only when the owner renames a speaker and ticks "Remember this voice" (off by default).
   - Owner's own voice: an optional 20-second enrolment in Settings, so "You" is right even on a shared mic.
   - At meeting start the library seeds the diarizer; a cluster within threshold of a saved voice takes its name.
   - Settings lists every saved voice with Delete and Delete all. Deleting removes the file entry at once.
   - Voices of other people are biometric data in Quebec (Law 25) and other places. The UI says so in one line:
     "Only save voices of people who agreed." The legal call is the owner's.
3. **Name suggestions.** Pure ZeusCore `ScribeNameSuggester`, no network:
   - Calendar attendees of the meeting the call popup matched (display names, never emails in the transcript).
   - What people say: self-introductions ("I'm Marie", "this is Paul from finance", "Marie here") give that
     speaker a suggestion; direct address ("thanks, Marie", "over to you Paul") gives the *next* speaker a weaker
     one. Names are kept only when they match an attendee, a saved voice, or appear twice.
   - The owner's own name (About you) is never suggested for a non-microphone voice.
   - Shown as chips on the speaker row: "Marie Dubois?" with Accept. Nothing renames itself.
4. **Rename that works everywhere.** Recap speaker row: tap the name, type, Enter. Applies to every line of that
   meeting, the stats, the notes, the exported Markdown and copied text (fixes Superwhisper's two complaints).
   Same name on two speakers merges them. Audio is never kept, so instead of a sample clip the rename sheet shows
   the speaker's three longest lines.
5. **Correction after the meeting.** When the transcript finishes, re-cluster all turn embeddings of the meeting
   together (average-linkage agglomerative, same threshold) and relabel turns that the live pass split or merged.
   Live labels stay on screen during the call; the recap uses the corrected ones. Pure ZeusCore, tested.

Not now (later phase, needs owner say-so): reading active-speaker names from Zoom / Teams / Meet windows through
Accessibility. It works only with Accessibility granted and changes with every app update.

## 4. Build slices and acceptance

| Slice | Done when |
|---|---|
| S1 embedding abstraction + WeSpeaker embedder + fallback | ZeusCore tests: clustering over synthetic 256-d vectors (two close, one far) gives 2 speakers; fallback path unchanged (existing diarizer tests green); app compiles in CI |
| S2 model download in Settings | Snapshot shows the row in each state (not downloaded, downloading, ready, failed); no download without a click (lint: no `DiarizerModels.download` outside the settings action) |
| S3 rename + merge in recap, notes, export, copy | Core test: rename maps every segment and stats; merge by same name; Markdown export carries names |
| S4 voice library + seeding + delete | Core tests: save, match within threshold, no match beyond, delete removes; file never under the vault |
| S5 name suggester | Core tests: intro, address, attendee filter, owner-name guard, no suggestion from one stray mention |
| S6 post-meeting re-cluster | Core test: a live split (A, A', B) merges back to (A, B); a live merge stays when distances are clear |
| Live QA (owner Mac) | Two-voice YouTube interview through system audio + owner on mic: owner labelled You, two guests distinct; rename one, tick Remember, rerun a second clip of the same guest: named automatically |

Rules: no em dashes in UI text, no `Task.sleep`, no network except the clicked model download, no audio stored.

## 5. Slices S7 to S9 and speaker parity (2026-11-11)

Spec: `SUPERWHISPER-PLAUD-REA.md` sections 3 to 5. Status below is what is built; "needs a live call" means the code
exists and is covered by synthetic tests, but only a real call on the owner's Mac can show what each app exposes.

| Slice | Status | Notes |
|---|---|---|
| S7 Auto-start | Not in this change | Separate builder. |
| S8 Call-window names | Built, needs a live call | Pure logic in ZeusCore (`MeetingSpeakerLabels`, `MeetingSpeakerBinding`, `MeetingSpeakerWindows`, `ScribeSpeakerBook`); Accessibility reader in `Sources/Zeus/Scribe/MeetingSpeakerSources.swift`. |
| S9 Nemotron streaming diarizer | Built, needs a live call | FluidAudio 0.18.0 (the version in `Package.resolved`) ships `Nemotron3Diarizer` with `appendAudio`, `processBufferedAudio` and `finishStream`, so it is wired. No dependency bump. |

### S8, how it works
- `MeetingSpeakerSource` per app: Zoom, Teams, Meet (Chrome, Safari, Arc, Edge) and Slack huddles. Each lists its
  bundle ids and which window titles may be a call; `MeetingTileExtractor` reads tiles out of a bounded copy of the
  window's Accessibility tree. Generic signals work everywhere: " is speaking", ", active speaker", "muted", and French
  ("parle", "est en train de parler", "micro coupe", "en sourdine"). Meet and Slack also use DOM class markers
  (`video-frame--active`, `huddle_peer_tile`, `overlay--active_speaker`, `name_overlay--muted`). Suffixes
  " (Guest)", " (External)", " (You)", " (Invite)", " (Externe)", " (Vous)" are stripped.
- Only read when `AXIsProcessTrusted()` is already true; Zeus never prompts. Polls run on the main actor (own-process
  Accessibility off the main thread traps), at most every 0.7 s, with an 80 ms node and time budget, and only while a
  Scribe session is recording. For Chromium and Electron apps the reader may switch on `AXManualAccessibility` and puts
  it back when the session ends.
- Polls fold into spans (gap over 1.5 s closes one), spans into votes per diarizer cluster, votes into a timeline
  winner. A name binds only when audio and tile agree: at least 4 s of overlap, at least 60 % of the voice's overlapped
  time, a 2x lead over the runner-up, the voice is also that person's best voice, and no ambiguous poll overlaps the
  turns (two meeting windows, or more than one call app). Muted tiles and the "(You)" tile never vote. The microphone
  channel is always "You".
- Manual names always win. A declined automatic name is remembered per voice. Later evidence can correct an automatic
  name only with a stronger source or 0.1 more confidence, never a typed or accepted one.
- Unknown until a live call: the exact Accessibility structure of each app. Run `scripts/call-ax-probe.swift` per app
  (section 4 of the REA) and compare with the extractor; Zoom and Teams use the generic signals only until then.

### S9, how it works
- Settings > Scribe > Speaker recognition has a second row, "Follow speakers live", with an explicit Download button
  (the only caller of `Nemotron3Models.loadFromHuggingFace`). Preset `fast32`. Meetings load the model from disk only.
- Live, each closed system-audio turn is fed to the streaming diarizer followed by silence for its latency, and the
  slot with the most active frames in the turn is its voice ("Speaker N" by first arrival). A matching saved voice
  keeps its own name. WeSpeaker stays the fallback when the model is not on disk, then the hand-built voiceprint. A
  second voice on the microphone is "Room voice N" in this mode so numbers never collide.
- At stop the stream is flushed and every turn is read again against the whole timeline (the batch relabel);
  turns that moved are relabelled, and call-window names are worked out again on the corrected voices. This reads the
  recorded speaker timeline, not stored audio: Zeus still keeps no meeting audio.

### Naming parity and beyond
Per speaker the meeting file stores name, source (typed, call window, invite, introduction, saved voice), confidence,
declined names and folded tiny voices (`speakerBook`; older files load unchanged). The recap shows the source, a dotted
underline and Confirm / Not them for an unconfirmed automatic name, "Reassign this block to" and "Assign selected words
to" per transcript block, Undo for every speaker change (this session), and "Restore small voices". Voices under 3 %
of the talk time and under 3 blocks are folded into the nearest speaker at stop (not when a name is known, not the
owner, not in a meeting under 30 s of talk). `ScribeController.nowSpeakingClaim()` gives the live pill the best
current name or "Identifying this speaker..." and lines relabel in place when a name binds. The play button for a 3 s
voice sample is hidden because Zeus keeps no meeting audio (`ScribeVoiceSample.clip` picks the clip for when it does).
