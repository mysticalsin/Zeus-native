# 011 — Fast local commands

Tony can say “open Harbor”, “pause”, or “volume up” and Zeus should act before a model
round-trip. This path is a small deterministic parser plus an explicit state machine.
Anything it does not recognise continues through the existing voice route, including
the current rules engine and the LLM, with no change to that route.

The budget is recognition to action: the machine may emit a perform effect only when
the injected clock is strictly under **150 milliseconds** after the transcript is final.
At 150 milliseconds or later it does not act.

## Where it sits

`VoiceTurnController.understand` is the single hook. That function already decides
what a final transcript can answer without a model. The hook runs first:

1. When Settings has instant commands off, or the turn is a restricted command-line
   turn, the machine is reset and the transcript is not consumed. The existing
   refusal still applies.
2. Otherwise the machine is given the transcript, the final-transcript instant, the
   clock, and the injected app list.
3. A consumed decision is performed and spoken here, and `understand` returns.
4. A fall-through decision returns control to the code that already follows, unchanged.

No other call site routes a final transcript into this machine.

## Catalog

App names are not built into the parser. The machine receives a list of `LocalApp`
values: display name, bundle identifier, path, aliases, whether it is running, and
unsaved-document state.

`hasUnsavedState` is `true` (dirty), `false` (known clean), or `nil` (unknown).
Unknown is the default. The macOS adapter fills the list from the in-memory app
index and `NSWorkspace`’s running applications. It does not scan the disk on the
transcript path, and it does not know whether a document is dirty, so it passes
`nil`. Quit therefore asks on a real Mac.

The spoken catalog is not every installed app. A row is kept only when its path
is `/Applications` or the user's Applications folder (`~/Applications`), or a
path inside one of those two roots. The path must equal the root or continue
with `/`. These are left out:

- `/System/Applications` and anything under it
- `/System/Library/CoreServices`
- a folder that only begins with the same letters, such as `/ApplicationsExtra`
- any other location the index may have scanned for a different feature

The index itself is unchanged. This catalog is the filter in front of it.

Matching, after the same normalisation the parser uses:

- Exact equality with the display name or an alias wins.
- If nothing is exact, a name or alias that continues past the query with a space
  is a prefix match (“field” matches “field notes”).
- Exact matches suppress prefix matches.
- Two or more apps in the winning tier are ambiguous.
- A query shorter than two characters matches nothing.
- The same bundle identifier is kept once, first occurrence wins.
- Candidates are ordered by name, case-insensitively, then by bundle identifier.

No commercial product name is part of this grammar. A fixture app is just a row
in the injected list.

## Normalisation

The parser lowercases, strips diacritics, deletes apostrophes, and turns every
other non-alphanumeric character into a space. “Don’t” becomes “dont”. “30%”
becomes “30”.

Leading fillers, removed repeatedly: “hey zeus”, “hi zeus”, “hello zeus”,
“okay zeus”, “ok zeus”, “please”, “um”, “uh”, “can you”, “could you”,
“would you”, “zeus”.

Trailing fillers, removed repeatedly: “for me”, “thank you”, “please”, “thanks”,
“now”.

## Intent table

The grammar is closed. A transcript that is not one of these rows is not a local
command. Verbs are tried only after the exact media and volume rows.

### Media

| Remaining words | Intent |
| --- | --- |
| play, play music, play the music, resume, resume music, resume the music, resume playback, start music, start the music | play |
| pause, pause music, pause the music, pause the song, pause playback | pause |
| next, next song, next track, skip, skip song, skip track, skip this song, skip this track | next |

“play jazz”, “play harbor”, and “play some music” are not in this table.

### Volume

| Remaining words | Intent |
| --- | --- |
| volume up, louder, turn it up, turn the volume up, turn up the volume | up |
| volume down, quieter, turn it down, turn the volume down, turn down the volume | down |
| mute, mute it | mute |
| unmute, unmute it | unmute |
| set the volume to N, set volume to N, set the volume at N, set volume at N, change the volume to N, change volume to N, change the volume at N, put the volume to N, put the volume at N, put volume to N, put volume at N, turn the volume to N, turn the volume at N, turn volume to N, make the volume to N, make the volume at N, volume to N, volume at N, volume N | set N |

N is an integer from 0 through 100, or a number word from zero through nineteen,
a ten from twenty through ninety, “hundred”, or a ten followed by a one
(“twenty five”, “ninety nine”). An optional trailing “percent” is allowed.
A value outside 0...100 is not a local command.

### Apps

The open verbs are “fire up”, “bring up”, “pull up”, “open”, “launch”, “start”,
and “run”. The switch verbs are “switch to”, “go to”, and “switch”. The quit
verbs are “quit”, “close”, and “exit”. Longer phrases win over shorter ones.

One leading “the” or “my”, and one trailing “app” or “application”, are removed
from the remainder. The remainder is the query. It must be one to four words,
at least two characters, and must not contain “and”, “then”, or any of: it, this,
that, these, those, them, window, windows, tab, tabs, file, files, folder,
folders, everything, all, application, screen, page, email, message.

| Verb | Intent |
| --- | --- |
| open verb + query | open query |
| switch verb + query | switch to query |
| quit verb + query | quit query |

The parser stops at the query. It does not decide which installed app that query
is. “start the music” is the media row, so it is play, not an app launch.

## States

The machine stores one of four states.

| State | Meaning |
| --- | --- |
| `idle` | Nothing is waiting. |
| `confirmingQuit(app)` | A quit was recognised and Zeus is waiting for yes or no. |
| `confirmingChoice(verb, candidates)` | The query matched more than one app. Zeus is waiting for a name. |
| `acted(action)` | The last transcript authorised an action. The next transcript is read as if the machine were idle. |

Effects are `perform(action)`, `speak(line)`, and `fallThrough`. A decision that
includes `fallThrough` is not consumed. Perform is listed before speak: the hook
starts the action, then speaks.

### From idle or acted

The clock is read once. If `now - finalAt` is 150 milliseconds or more, the state
becomes `idle`, the effect is `fallThrough`, and nothing is performed. A negative
skew is treated as zero and is still inside the budget.

Otherwise:

| Recognition | Next state | Effects |
| --- | --- | --- |
| Not in the intent table | idle | fallThrough |
| Query matches no app | idle | fallThrough |
| Media or volume | acted | perform, then “Playing.”, “Paused.”, “Next.”, “Louder.”, “Quieter.”, “Muted.”, “Unmuted.”, or “Volume N.” |
| One app, open | acted | perform open, “Opening NAME.” |
| One app, switch | acted | perform switch, “Switching to NAME.” |
| One app, quit, not running | idle | “NAME isn’t open.” |
| One app, quit, running, unsaved is false | acted | perform quit, “Quitting NAME.” |
| One app, quit, running, unsaved is true or nil | confirmingQuit | “Quit NAME? It may have unsaved changes.” |
| Two or more apps | confirmingChoice | “Did you mean A or B?” or “Did you mean A, B, or C?” |

Quit asks whenever unsaved state is anything other than a known clean. That is
the default.

A quit confirmation does not wait forever. It expires **10 seconds** after the
clock reading that asked the question, or at the end of the next turn, whichever
comes first. The same single clock reading that enforces the 150 millisecond
budget also measures those 10 seconds. At 10 seconds the pending quit is dropped
and the transcript is read as a fresh command, so a late “yes” does not quit and
a late “pause” is pause. `endTurn` drops a confirmation that was already pending
when the turn began. A confirmation created during the turn is armed for the
following turn and is not dropped by that same `endTurn`.

### From confirmingQuit

Still subject to the 150 millisecond budget, measured from this reply’s final
instant, and to the 10 second lifetime above. Over the 150 millisecond budget:
drop the confirmation, go idle, fall through. The late “yes” must not quit the app.

Confirmation is an explicit phrase. “ok”, “sure”, and a bare “quit” are not
confirmation.

| Reply | Next state | Effects |
| --- | --- | --- |
| yes, yeah, yep, yah, confirm, do it, go ahead, quit it, please do, okay | acted | perform quit, “Quitting NAME.” |
| no, nope, nah, cancel, dont, do not, stop, never mind, leave it, leave it open | idle | “Leaving it open.” |
| Another row of the intent table | as if idle | that row’s effects |
| ok, sure, quit, or anything else | idle | fallThrough |

### From confirmingChoice

Over budget drops the choice and falls through.

| Reply | Next state | Effects |
| --- | --- | --- |
| A negative from the list above | idle | “Okay.” |
| Another row of the intent table | as if idle | that row’s effects, against the full catalog |
| The words match exactly one of the candidates | acted, or confirmingQuit if the verb is quit and a confirmation is required | that app’s effects |
| The words still match more than one candidate | confirmingChoice | the same question again |
| Anything else | idle | fallThrough |

“Yes” does not choose an app. Naming one does. “Field notes” chooses the app
whose name is Field Notes when that name is unique among the candidates.

## Action, on the Mac

The hook performs with `NSWorkspace` only for apps:

- Open and switch activate a running application, or open its bundle with
  `NSWorkspace.openApplication` and activation on.
- Quit sends the Quit Apple event (`kAEQuitApplication`) to that running
  application’s process, with interaction and layer switching allowed, and does
  not wait for a reply. That is the normal Quit path: the app may show its own
  save dialog. This path does not call `terminate()` or `forceTerminate()`.

Play, pause, next, and volume are the actions Zeus already uses for those words:
the existing media-key event and the existing output-volume helper. This path
adds no permission, TCC prompt, entitlement, dependency, or timeout.

If the named bundle is not running and has no URL, open does nothing after the
decision. The machine has already decided the command was his.

## Fallbacks

Fall through, without speaking and without performing, when:

- the words are not in the intent table
- the query matches no injected app
- the clock is at or past 150 milliseconds
- a confirmation reply is neither an answer nor a new local command
- instant commands are switched off

Those transcripts keep the approvals, browser, walkthrough, learned-step,
selection, instant-table, rules, and model behaviour they have today.

## Tests

The acceptance tests are pure. They do not import AppKit.

- The exhaustive parser table: every row above, including filler, case, and punctuation that normalise onto a row.
- Fall-through: the rejected phrases, plus an app name that is not in the injected list.
- Latency: an injected clock at 149 milliseconds acts; a clock at 150 milliseconds falls through and does not perform. A confirmation that arrives at 150 milliseconds does not quit.
- Quit confirmation: “yes” and “quit it” quit. “ok”, “sure”, and a bare “quit” do not. A “yes” at 9.999 seconds quits. A “yes” at 10 seconds does not, and “pause” at 10 seconds is pause. `endTurn` after the question drops the confirmation, so a later “yes” does not quit.
- Catalog roots: a path under `/Applications` or `~/Applications` is included. System locations and prefix lookalikes are not.
- Ambiguous names: two installed apps that share an alias ask, a later reply that names one acts, and “yes” or “no” does not guess.

Linux cannot build the macOS application target. The pure files are executed in
an isolated throwaway package. That run does not start the app, does not call
`NSWorkspace`, and does not prove the voice-hook wiring on a Mac.
