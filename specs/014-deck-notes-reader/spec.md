# 014 — In-browser deck notes reader

Spec only. Tony approved this in his words: "Build 3: in-browser deck-notes reader". This change adds the spec and the mock-up. It does not add application code, tests, a permission, a window, or a feature-map row.

The drawing is `mockup.md` and `mockup.html` beside this file.

## Before any build

These constraints are part of the spec. An implementation commit that does not meet them is not this feature. No application code in this change.

### Capture, screenshots, and accessibility

Speaker notes are always excluded from screen capture and from Zeus's own screenshots. The setting `general.showInScreenSharing` does not apply to them. When that setting shows other Zeus surfaces, the notes stay out of capture and out of any screenshot Zeus takes of itself. A view that draws the notes uses a capture mode that hides it, including when the rest of the top bar is visible to a share.

The notes string is not an accessibility value. It is not exposed on an element another process can read through the accessibility tree. The VoiceOver name of the region is "Speaker notes, slide N of M" and does not include the notes body.

### Deck URL

A URL is a deck only when every part below holds. The comparison is exact. A suffix, a prefix, or a lookalike host is not a match.

- The scheme is `https`. No other scheme matches, including `http`.
- The host, lowercased and without a trailing dot, is exactly `docs.google.com`. No userinfo. No port other than an empty port or 443.
- The path begins with `/presentation/`.

The extension applies this same allowlist itself, immediately before `executeScript`. An allow decision from the app is not enough.

These URLs are rejected. A later test lists them and expects rejection:

| URL | Why it is not a deck |
| --- | --- |
| `http://docs.google.com/presentation/d/abc` | scheme is not https |
| `https://docs.google.com.evil.example/presentation/d/abc` | host is not exact |
| `https://docs.google.com.evil.example/presentation/d/abc/present` | host is not exact |
| `https://evil.docs.google.com/presentation/d/abc` | host is not exact |
| `https://docs.google.com.attacker.test/presentation/d/abc` | host is not exact |
| `https://user:secret@docs.google.com/presentation/d/abc` | userinfo |
| `https://docs.google.com:444/presentation/d/abc` | port is not 443 |
| `https://docs.google.com./presentation/d/abc` | trailing dot |
| `https://docs.google.com%2e.evil.example/presentation/d/abc` | encoded dot in the host |
| `https://docs.google.com%00.evil.example/presentation/d/abc` | encoded NUL in the host |
| `https://docs.google.com%2f.evil.example/presentation/d/abc` | encoded slash in the host |
| `https://evil.example/presentation/d/abc?next=https://docs.google.com/presentation/d/abc` | host is the other site |
| `https://evil.example\@docs.google.com/presentation/d/abc` | host confusion |
| `javascript:https://docs.google.com/presentation/d/abc` | scheme is not https |
| `data:text/html,https://docs.google.com/presentation/d/abc` | scheme is not https |
| `//docs.google.com/presentation/d/abc` | no https scheme |
| `https://docs.google.com/presentation` | path lacks `/presentation/` |
| `https://docs.google.com/presentations/d/abc` | path is a different word |
| `https://127.0.0.1/presentation/d/abc` | host is not exact |

`https://docs.google.com/presentation/d/abc/edit` and `https://docs.google.com/presentation/d/abc/present` match. A query or a fragment on an otherwise exact URL may match. Nothing else in the table does.

### Page script

`executeScript` runs in the isolated world, never the page's own world. The target frame is frame id 0, the top frame only. Child frames are not injected.

The reader uses a named selector list for that site. The selector that is not in the list is not tried. Zero matches, or more than the one field the list names, fails closed: `notesNotOnPage` or `unreadable`, and the buffer stays empty. The script does not fall back to the page's visible text.

The extension test installs traps on the calls that would change the page or leave it: click, write, assignment to the document body, navigation, and fetch. The reader runs against a fixture. Any trap firing fails the test. A read that only returns the named field passes.

### Host, socket, and frame size

The native-host manifest `allowed_origins` lists one origin: the Zeus extension, `chrome-extension://` plus its id and a trailing slash. No wildcard and no second origin.

The local socket is mode `0600`. The owner can read and write it. No other user can.

A frame longer than the host already accepts is rejected before it is parsed. The limits that already exist stay: 1_048_576 bytes of JSON from the host to the browser, and 4_194_304 bytes from the browser to the host. This feature does not raise them. The notes payload is still at most 8,000 characters.

### Follow

Follow polls on the interval the spec already uses, 0.5 seconds, and it stops after 120 polls. Each poll re-checks the tab URL against the predicate above and re-checks the private-window flag before any script runs. A URL that no longer matches, a private window, or an unknown private flag cancels the watch and drops the notes. The 120th poll is the last even when both checks still pass.

### Text leaving the page

Before the notes or the title are held or drawn, bidi and zero-width characters are stripped. That includes U+200B, U+200C, U+200D, U+200E, U+200F, U+202A through U+202E, U+2066 through U+2069, and U+FEFF. The remaining text is what the page shows.

The extension does not write the notes, the title, or the URL to its console or to its storage.

### Private windows

Private-window detection is per browser. The extension reads the private-window bit that the browser it is running in exposes for that tab. A browser this build does not have a named check for is unknown. A missing bit, a thrown query, or a value that is neither private nor not-private is unknown. Unknown is refused: the state is `privateWindow` and no script runs.

## Finding

S04-11, P2, Prompter notes. Sweep 04 is PR #94, `qa/sweeps/sweep-04-completeness.md`, read against `codex/integration-20261111` at `2722dcb7497d5415fbc1fcb1f65c49629966a281`.

The in-browser notes provider in `Sources/ZeusCore/TopBar/PresenterSync.swift` (lines 210–217) has a `load` that always throws, a `status` that returns nil, and an empty advance script. The presentation-URL predicate on lines 222–225 still returns true for a deck URL. `Sources/Zeus/Prompter/PresenterNotesController.swift` lines 89–92 throw that error when the predicate matches the active tab and no presentation app is running. Lines 146–150 perform that check only when notes are loaded.

The presentation-app reader is a separate path. It stays as it is. This reader runs only when that path has no running app and the person asks.

## What it reads

Speaker notes of the slide deck open in the browser. Read-only.

One read returns the notes of the slide that deck is showing, and enough structure to label it:

| Field | Meaning | Bound |
| --- | --- | --- |
| `title` | The deck's name, plain text | 200 characters, trimmed |
| `slide` | The slide on screen, starting at 1 | An integer, at least 1, at most `count` |
| `count` | How many slides the deck has | An integer, at least 1 |
| `notes` | That slide's speaker notes, plain text, line breaks kept | 8,000 characters |
| `notesInDocument` | The page exposed a speaker-notes field | Boolean |

`truncated` is set when the notes were longer than 8,000 characters. The reader keeps the first 8,000 and the caption says "Truncated".

The notes are the speaker's notes for that slide. The slide's canvas, pictures, comments, and the notes of every other slide stay on the page. Visible page text is not a stand-in. The comment on the stub says the bridge can already read visible text, and that the notes of the slides are not that text while a slideshow is running. A page with no speaker-notes field ends in `notesNotOnPage`. The reader does not fill the gap with the slide body.

The string is shown as plain paragraphs in the Prompter page of the top bar. It is not parsed as a script, so a line that begins with a mark stays a line of notes. It is not written into the script the person already has on that page.

## Where it sits

The notes are a region of the existing Prompter page in the open top bar. The page is the one measured in `Sources/ZeusCore/TopBar/GlanceTopBar.swift`: body 870 pt wide, tab row under the notch, tall page 236 pt. The mock-up uses that frame.

The reader does not open, resize, or focus a window. The floating prompter stays the place for a script the person already sent there. Browser notes are not copied into it.

While the reader is idle, the Prompter page stays as it is, with one added control, "Read". After a read, that page shows the notes and the controls below. Leaving the page or closing the bar drops the text.

## Routes, ranked by least privilege

The route this build uses is the first one. The others are recorded so a later change has to edit this spec before it may use them. The feature never raises a TCC prompt.

| Rank | Route | Reads the notes | New TCC prompt | New permission | Eligible |
| --- | --- | --- | --- | --- | --- |
| 1 | Bundled browser extension, a new read-only command | Yes, when the page exposes a speaker-notes field | None | None. The manifest stays as it is | Yes |
| 2 | Accessibility read of the front browser window | Sometimes. A slideshow often leaves the notes out of the tree | None from this feature. The existing Accessibility grant is the same service the app already uses. If it is off, this feature leaves it off | The same Accessibility grant | No |
| 3 | Automation of the browser | Poorly. The browser's scripting dictionary does not hold the speaker notes | Yes. One Automation prompt for each browser. A grant for the presentation app does not cover the browser | The Automation entitlement is already in `Resources/Zeus.entitlements`. The prompt would be new | No |
| 4 | Screen recording and recognition of the notes pane | Pixels of the display, which is wider than the notes | Yes, when Screen Recording is not already granted. The purpose string is a separate finding, S04-05, and this feature does not add it | Screen Recording, which other features already have a row for | No |

### 1. Bundled extension

The extension already in `extension/` is Manifest V3. `extension/manifest.json` grants `nativeMessaging`, `tabs`, `scripting`, and `storage`, and host access for every URL. The app already talks to it through the local host `com.zeus.bridge` and a local socket. Media commands already refuse a private window (`extension/src/sw.ts`).

This build adds two commands and does not edit the permission lists. Widening or narrowing `host_permissions` would be a new browser consent, so the lists stay. The commands are not `page.context` and not `page.extract`. Those return visible text, the selection, and controls (`extension/src/page.ts`).

| Command | Returns | Page script |
| --- | --- | --- |
| `deck.notes` | The payload above, for one document | Reads the speaker-notes field. No click, no typing, no navigation, no fetch, no write to the page |
| `deck.index` | `slide` and `count` only | Reads the slide number. No notes text |

The script checks the document URL the command was given. A navigation answers as a stale document, and the machine drops the text.

Turning the extension on is the browser consent the person already uses for the bridge. This feature does not install the extension and does not raise a consent sheet. When the socket is absent, the state is `extensionOff`.

### 2. Accessibility

An Accessibility read would use the service the app already checks for tiling, shortcuts, and call-window names. This feature does not call the prompt. Web notes are often missing from the tree unless the browser has exposed them, and the grant can read every app's interface. It stays ineligible.

### 3. Automation

Automation is per target. A grant already given for the presentation app, or for any other app, does not cover the browser, so this route would be a new prompt for each browser. It can drive the browser, and the notes are not in the dictionary. It stays ineligible. This feature does not send events to the browser.

### 4. Screen recording

A capture of the display includes whatever else is on screen. It fails the data-flow rule below. It stays ineligible. This feature does not call the screen-capture APIs.

Paste into the Prompter page is already shipped and uses no permission. It does not read the page. It stays available and is not this reader.

## Data flow and threat model

The person starts every read. A presentation URL appearing, a slideshow starting, or the top bar opening does not read.

```
Prompter page, Read
  → app asks the bridge for the active tab (id, URL, private flag, document id)
  → predicate in PresenterSync.swift accepts or refuses the URL
  → deck.notes runs in that document
  → service worker → com.zeus.bridge → local socket → app
  → the notes string is held in the top-bar state and drawn on the Prompter page
```

Follow, after the person presses Follow, repeats `deck.index` every 0.5 s while the top bar stays open. That interval matches the existing presenting poll. A changed slide number sends one `deck.notes` for the new slide. The same number sends nothing further. One request is in flight at a time. A late reply for an older document is dropped.

What leaves the page is the payload, or the two integers from `deck.index`. The URL is used to choose the tab and to detect a navigation. The machine keeps it until the read ends. It is not shown, and it is not written to disk or to a log. The tab title is not shown. The deck name on screen comes from the payload.

Local only. The new commands make no network request. The page's own requests are untouched. Nothing is sent to a model, a provider, or another machine.

Nothing is stored. The string lives in the reader state until Clear, Escape, a failure, a document change, leaving the Prompter page, or closing the bar. Then it is dropped. Reopening the bar does not restore it. The string is not written to defaults, a file, the vault, the clipboard, the existing script, or a log line.

The only log line is the state name (`showing`, `notesNotOnPage`, and the other names below). The line does not include the notes, the title, the URL, or the document id.

The top bar keeps the capture policy it already has. This feature does not open a window and does not change that policy.

Threats the machine closes:

| Threat | Response |
| --- | --- |
| A page returns extra fields, markup, or the slide body | The parser accepts only the fields in the table. Anything else is `unreadable`, and the text is dropped |
| The notes contain instructions meant for a model | They are drawn as plain text. No command runs them and no model receives them |
| The extension's broad host access is pointed at another tab | The match is the active tab in a normal window. A background tab is ignored. A private window is `privateWindow` and no script runs |
| The tab navigates after the read | The document check fails, the state becomes `deckChanged`, and the text is dropped |
| A second process speaks on the socket | The existing bridge checks its peer. This feature adds no second listener |
| A log, a crash report, or a test printer records the notes | Production effects have no field a logger is allowed to print. Tests use the synthetic sentence in the mock-up and a disposable state |
| Follow keeps running after the bar closes | `dismiss` cancels the watch and drops the text |

The reader does not advance the deck. The stub's advance script stays empty.

## State machine

One value, `DeckNotesReader`, pure, in ZeusCore. The app performs the effects and sends the results back as events. The machine holds the notes. The effects carry a target so the bridge can address the document. A target is a tab id, a document id, and the URL the bridge needs for its stale-document check.

States: `idle`, `checking`, `reading`, `showing`, `following`, `failed`.

`showing` and `following` hold `title`, `slide`, `count`, `notes`, and `truncated`. `failed` holds one failure and no text. `reading` holds the target and no text.

Events: `read`, `bridgeDown`, `activePrivate`, `noMatch`, `matched(target)`, `payload(result)`, `index(result)`, `follow`, `stop`, `clear`, `dismiss`.

`clear` is the Clear control and Escape. `dismiss` is leaving the Prompter page or closing the bar. `read` is Read and Read again, and Return while the page is focused. Return never starts Follow.

Effects: `findDeck`, `readNotes(target)`, `watchIndex(target)`, `cancelWatch`. There is no persist, clipboard, network, log-text, prompt, or advance effect.

| From | Event | To | Effects |
| --- | --- | --- | --- |
| `idle`, `failed` | `read` | `checking` | `findDeck` |
| `showing` | `read` | `checking` | `cancelWatch`, `findDeck` |
| `checking` | `bridgeDown` | `failed(extensionOff)` | |
| `checking` | `activePrivate` | `failed(privateWindow)` | |
| `checking` | `noMatch` | `failed(noDeck)` | |
| `checking` | `matched` | `reading` | `readNotes` |
| `reading` | `payload` notes in the document, including an empty string | `showing` | |
| `reading` | `payload` notes not in the document | `failed(notesNotOnPage)` | |
| `reading` | `payload` malformed, or a stale document | `failed(unreadable)` or `failed(deckChanged)` | |
| `reading` | `bridgeDown` | `failed(timedOut)` when the wait ends with no reply; `failed(extensionOff)` when the socket is gone | |
| `showing` | `follow` | `following` | `watchIndex` |
| `following` | `index` with the same slide and count | `following` | |
| `following` | `index` with a new slide | `reading` | `readNotes` |
| `following` | `stop` | `showing` | `cancelWatch` |
| `following` | `bridgeDown` or a stale document | `failed(extensionOff)` or `failed(deckChanged)` | `cancelWatch` |
| any except `idle` | `clear` or `dismiss` | `idle` | `cancelWatch` when a watch is running |

A `read` while `checking` or `reading` changes nothing. A `follow` outside `showing` changes nothing. A `matched` outside `checking` changes nothing. A payload for a document that is not the one in `reading` is dropped.

An empty notes string with `notesInDocument` true is `showing`. The caption is "No notes on slide N". The page still shows the position, and the next slide's notes appear only after the person moves on and the reader is following, or after they press Read again.

## Failure copy

Each failure is a title and one line, in words, on the Prompter page. None of them opens Settings. None of them names a remedy that grants a permission.

| Failure | Title | Line |
| --- | --- | --- |
| `extensionOff` | The browser extension is off | Turn on the Zeus extension in the browser, then press Read. |
| `noDeck` | No slide deck in the browser | Open the deck in the browser, then press Read. |
| `privateWindow` | Private window | Zeus does not read a private window. |
| `notesNotOnPage` | Notes are not on this page | Open the speaker notes in the browser, then press Read. |
| `deckChanged` | The deck changed | Press Read to load the slide in front. |
| `unreadable` | Could not read the speaker notes | Press Read to try again. |
| `timedOut` | The browser did not answer | Press Read to try again. |

The empty-slide caption is "No notes on slide N" and "Read again when you move on." The loading line, used for `checking` and `reading`, is "Reading speaker notes". The showing kicker is "Speaker notes". The position is "N / M" in tabular figures. A truncated payload adds the caption "Truncated".

VoiceOver on the notes region: "Speaker notes, slide N of M". The notes are static text, not a field. Read is the default button. Follow is a separate button. Clear and Escape return to `idle`.

With Reduce Motion, a new slide replaces the text in place. There is no roll and no crossfade. The buttons keep a visible pressed state without scaling.

## Red-first test plan

No test is added in this change. The first implementation commit adds the tests below and no production type. They fail to compile. The next commit adds `DeckNotesReader` and the payload parser until the suite passes. The suite is `Tests/ZeusCoreTests/DeckNotesReaderTests.swift`. It uses synthetic strings and does not open a browser, an Accessibility session, a socket, or a permission prompt. Linux can run it.

The test that currently expects the in-browser provider's `load` to throw stays in place until the implementation replaces that provider. The new suite is the contract for the replacement. The presentation-app tests stay green without edits.

1. **Route table.** Rank, TCC, and eligibility match the table in this spec. Only rank 1 is eligible. The feature's prompt flag is false for every route.
2. **Parser.** A payload of title, slide, count, notes, and `notesInDocument` parses. An extra field, a missing field, a slide of 0, a slide above the count, or notes that are not a string is `unreadable`. The 8,001st character is absent and `truncated` is set. Line breaks inside the 8,000 are kept.
3. **Predicate.** A URL the existing predicate accepts can be matched. A URL it rejects, and an empty string, become `noMatch`. The test calls the predicate already in `PresenterSync.swift` and does not reimplement it.
4. **Idle read.** `read` from `idle` yields `checking` and `findDeck`. No `readNotes`.
5. **Choose the tab.** `bridgeDown`, `activePrivate`, and `noMatch` yield the three failures and no `readNotes`. `matched` yields `reading` and one `readNotes` for that target.
6. **Show.** A payload with notes yields `showing` and those strings. An empty notes string with the field present yields `showing` and the empty-slide caption. `notesInDocument` false yields `notesNotOnPage` and an empty buffer.
7. **Refuse the page.** A malformed payload yields `unreadable`. A stale document yields `deckChanged`. In both, the buffer is empty.
8. **One in flight.** A second `read` during `checking` or `reading` yields no new effect.
9. **Follow.** `follow` from `showing` yields `following` and `watchIndex`. The same index yields no `readNotes`. A new index yields `reading` and one `readNotes`. `stop` returns to `showing` and cancels the watch. `follow` from `idle` yields nothing.
10. **Drop.** `clear` and `dismiss` from `showing`, `following`, and every failure yield `idle`, an empty buffer, and `cancelWatch` when a watch was running. A later `showing` is possible only after a new `read`.
11. **Effects.** The effect set is the four names above. A walk of a whole session (read, show, follow, index change, dismiss) never produces another effect.
12. **Log name.** The description of every state is the state name and, for a failure, the failure name. Building it from a state that holds the sample sentence does not include that sentence, the sample title, or a URL.
13. **Desktop path stays.** When a presentation app is the running source, the browser machine is not sent `read` by the selector. The selector test feeds "app running" and "app not running" as inputs. It does not launch an app.
14. **Copy.** The titles and lines in the failure table, the empty-slide caption, and "Reading speaker notes" are the strings the view is specified to use.

A later extension test, `extension/tests/deck-notes.test.mjs`, is red until the commands exist. It feeds a fixture document and asserts three things: `deck.notes` returns the five fields and no other text, a non-presentation URL and a private window run no script, and the fixture function does not call click, write, or fetch. That file is not part of the first red commit.

A Mac pass, after the suite is green, checks the Prompter page with the pointer and the keyboard: Read, Follow, Stop, Clear, Escape, Return, a private window, the extension off, a deck with no notes field, and Reduce Motion. The notes region exposes the VoiceOver name above. That pass is the visual acceptance. This mock-up is not that pass.

## Out of scope

The presentation-app reader, its Automation grant, and its advance behavior. Editing the manifest. A new TCC prompt or usage string. A new window. Writing the notes into the script, the clipboard, defaults, the vault, or a log. Sending the notes to a model. Advancing the slide. Polling before the person presses Follow. Restoring notes after the bar closes.
