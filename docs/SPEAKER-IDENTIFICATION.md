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

Persistence (2026-11-11): invitee names, speaker labels and each turn's voice vector are saved inside the meeting's
own JSON file (`ScribeMeetingRecord.attendees`, `.turnVoices`; 0600 in a 0700 folder), so after a relaunch the recap
still offers invite names and "Remember this voice". The vectors are never uploaded, never in the vault and are removed
when the meeting is deleted. Older files without these keys load as before. Saved voices of people across meetings
(`ScribeVoiceLibrary`) stay opt-in per person.

Rules: no em dashes in UI text, no `Task.sleep`, no network except the clicked model download, no audio stored.
