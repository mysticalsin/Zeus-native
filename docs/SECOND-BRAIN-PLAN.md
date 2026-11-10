# Second brain completion plan

Reviewed 9 November 2026 on `codex/zeus-readiness-20261109`, based on
`cursor/polyglot-caption-flow-fa03-from-packet`. The first outbound destination
requested by Tony is **Obsidian / local Markdown**. This branch adds saved-meeting
source navigation, a related-pages list, and a selected-page local MCP export
workflow. The visual graph and unified learning stages remain implementation plans.
Native macOS acceptance is still required for the new export sheet and security-scoped access.

## What exists

| Capability | Code and current boundary |
| --- | --- |
| Learning wiki | `WikiController`, `WikiCompiler`, `WikiPage`, `WikiStore`. Saved Scribe decisions and action items are deduplicated into topic pages. No raw audio or private meeting notes are ingested. |
| Durable memory controls | Wiki search, pin, body editing, pause, forget-meeting tombstones, delete, pending-write retries, and recovery notices. Edited pages affected by a forgotten source require review before export or promotion. |
| Provenance | `WikiFact.sources` and `WikiPage.sources` preserve meeting IDs. A meeting source can open its existing saved recap; missing, dismissed, cancelled or forgotten sources cannot be revived. Opening is blocked while a Scribe capture/processing session runs. `WikiSource.preference` and `.memory` are defined, but the compiler currently ingests meetings only. |
| Related pages | `WikiRelationships` derives an accessible navigation list from explicit `[[Page title]]` / exact-page-ID links in edited pages and identical current source IDs. Links show incoming, outgoing or both directions; shared-source connections retain their evidence separately. Missing or removed meeting evidence and forget tombstones are excluded. Ambiguous titles, missing pages and self-links do not resolve. This is not a visual graph or Graphify parity. |
| Explicit wiki export | The existing Save Panel exports one selected page. The new **Send to vault…** sheet selects up to 20 pages, previews exact Markdown and provenance, applies source/review/sensitive-information gates, and sends only after an explicit Export action. |
| Preferences and to-do learning | `UserMemoryStore` keeps explicitly remembered rules/facts; `TodoLearning` learns local recurring-task patterns. These stores are separate from the learning wiki. There is no first-class lesson record or graph. |
| Vault integration | Local note search, today's tasks, to-do mirroring, profile creation, and explicit Save to Brain from chat, stickies, routines, and shelf items. Existing capture has a source category such as `zeus-chat`, but does not retain the original record ID. |
| MCP | `WikiMCPExportModel` uses the real `MCPStdioClient` and bundled `zeus memory-mcp` helper. The helper exposes only create and inspect for UUID-named exports in the explicitly configured Obsidian/Markdown inbox. No arbitrary third-party server adapter or background sync exists. Global wiki scope remains unrelated to export permission. |

## Corrections in this branch

- Save to Brain uses the configured Memory destination and inbox, including its
  read-only setting. An explicitly chosen legacy profile vault is used only when
  no Memory connection exists. A missing choice never silently selects
  `~/Documents/brain`.
- The preview has a fixed creation time and planned filename. Save rechecks the
  selected destination/access and refuses filename collisions rather than
  overwriting a note or silently changing the previewed path.
- Vault reads and write admission reject symlinks below the selected root,
  including dangling links and links to other folders inside the same vault.
  A root explicitly selected through an alias is supported. Writers recheck the
  boundary after creating directories. This is path validation, not a claim that
  filesystem operations are immune to a hostile process swapping directories
  between validation and I/O; descriptor-based traversal is a follow-up hardening
  item before an untrusted MCP filesystem backend is supported.
- Existing profile/inbox exports do not overwrite an existing file.
- Meeting source clicks re-read saved records before opening an existing recap.
  A source removed from the Meetings list stays removed. Active capture or notes
  processing is never reset to make room for navigation; a completed or failed
  stage is closed only when a valid requested recap can actually be shown.
- Related pages retain review requirements and use only current shared evidence.
  The current meeting compiler groups a meeting into one topic page, so the list
  starts empty for unrelated meetings. A person can connect those pages by editing
  `[[Page title]]` into a page; no semantic connections are inferred. Links from
  unreviewed or forgotten text are withheld until review. Parsing is bounded to
  the first 65,536 characters and 128 valid references per page.

## Stage 1: Complete sources and learning

Extend the existing wiki rather than create a competing memory store.

1. Add a versioned `WikiSourceReference` with a stable source ID, kind, source
   revision, display title, local record locator, and optional transcript segment
   IDs/time ranges. Keep the existing meeting UUID when migrating v1 pages.
   `ChatMessage`, `ChatConversation`, `StickyNote`, and `ScribeMeetingRecord`
   already have stable IDs; capture entry points must pass them through.
2. Extend the in-app saved-meeting resolver to preferences, remembered facts and
   to-dos. Meeting rows now open the original saved recap and disclose unavailable
   sources; they never open an unrelated replacement. Do not advertise a
   `zeus://` link until URL routing and deleted-source behavior exist and are tested.
3. Wire explicit user memories, selected preferences, and to-do events into the
   compiler. Add `preference` and `lesson` fact kinds with backward-compatible
   decoding. Keep observed actions separate from inferred lessons. A suggested
   lesson becomes durable only after review; do not silently ingest screen text.
4. Preserve pause, editing, forgetting and source-removal behavior across every
   new source type. Forgetting a fact removes derived relationships, blocks stale
   pending exports, and persists a tombstone so the next refresh cannot relearn it.
   An edited page with unresolved provenance remains blocked by `needsReview`.

Acceptance: synthetic records of every kind survive restart, expose the correct
source, update on edits, and stay forgotten after source refresh. Inaccessible or
partially corrupt source storage must not delete unrelated learned facts.

## Stage 2: Graph with inspectable connections

The first bounded connection model is implemented: `WikiRelatedPage` carries the
target page ID/title, explicit authored-link direction and exact shared source
IDs, derived by `WikiRelationships`. It recomputes after source or page removal
and does not mutate page contents or clear a review flag. Native
keyboard/VoiceOver/source routing acceptance is still pending.

Extend this to `WikiRelation(id, fromID, toID, kind, sourceIDs, origin, confidence, revision)`.
Start with deterministic `derivedFrom`, `sameTopic`, and `actionFromMeeting`
relationships. Suggested semantic relationships must show their supporting
sources and remain distinguishable from confirmed ones. A shared topic alone is
not evidence that one fact caused another.

Build the graph and an equivalent accessible list from the same relation model.
Selecting a node opens its page; selecting an edge shows its explanation and
source records. Provide search, focus on one topic, keyboard navigation, reduced
motion, and a readable empty state. Deletion/forgetting removes derived edges;
edited content invalidates suggestions whose evidence changed. Benchmark large
synthetic graphs before enabling an unbounded all-pages view.

Acceptance: source links work from both graph and list; no orphan edges survive
forget/delete/restart; VoiceOver and keyboard can reach every relationship;
performance is measured on a representative Mac. Graphify-style visual parity
needs the user's actual reference and live review.

## Stage 3: Selected Obsidian export over MCP — implemented slice

The first adapter is a bundled local MCP server, launched only from Memory's
**Send to vault…** sheet. It uses the existing explicit Memory connection and
inbox; only read-and-write Obsidian/Markdown destinations qualify. It does not
search installed MCP configurations, browse a vault, use a legacy fallback,
request new OS permissions, or send content to a network service.

### Exact contract

- `zeus memory-mcp --vault PATH --inbox RELATIVE --identity DEVICE:INODE` is
  implemented in `WikiExportMCPCommand`, before the CLI's app-control socket code.
  The existing bundle script already includes/signs this CLI as `Contents/Helpers/zeus`.
  The native client verifies its executable exists and never resolves it through
  shell strings or the global PATH. A development build uses its sibling CLI.
- Standard newline JSON-RPC/MCP initialize and tools discovery precede requests.
  The client checks the server name, version and protocol, plus the required
  property sets for `zeus_memory_create_export(export_id, markdown)` and
  `zeus_memory_inspect_export(export_id)`. There are no arbitrary path, list,
  search, delete, overwrite or network tools. No credentials are needed.
- The selected root's device/inode is captured at review and rechecked before
  dispatch and inside the helper. Held directory descriptors, `openat`, and
  `O_NOFOLLOW` constrain traversal to ordinary inbox directories. Hidden paths,
  traversal, symbolic links, nonregular files and multiply-linked files fail
  closed. New files are private (0600), newly created inbox directories 0700.
- `WikiExportDraft` contains the exact sorted selected page snapshots, source
  titles, reviewed bytes, export UUID and destination. Page/source revisions,
  settings readability, read/write access, root identity and review state are
  rechecked after discovery immediately before dispatch. The exact preview,
  including its source metadata, is scanned for sensitive information.
- Markdown schema 1 includes export UUID, creation time and selected page IDs;
  each section includes its existing source titles and stable identifiers.
  No absolute vault path, private notes or unselected records are appended.
  Source IDs currently open from Zeus Memory; no external deep link is fabricated.
- One complete temporary file is fsynced, then published with an exclusive hard
  link. Existing notes are never overwritten. A retry uses the same UUID and
  succeeds only when existing bytes match exactly. A separate inspect call reads
  back the exact file and compares all bytes before reporting success.
- Before dispatch, a private recovery record is persisted under the wiki's
  `exports/` directory. A lost reply, cancellation or unverified readback stays
  **uncertain**. Reopening the sheet offers read-only **Check result**. Only a
  confirmed missing note enables **Retry same export**, with the same review and
  revision gates. No automatic retry or new UUID follows a timeout.
- **Abandon recovery…** requires an explicit confirmation that a note may already
  exist and a future export could duplicate it. It erases the private draft,
  preserves possible-copy destination/UUID metadata, and sends nothing.
  Successful verification also erases the retained draft bytes.
- Forgetting a contributing meeting invalidates and erases its pending draft.
  Refresh also invalidates unavailable, dismissed and cancelled meeting sources.
  A running sheet cancels its helper when invalidated. A request already sent may
  have created a note: Zeus discloses this and never deletes external copies.
- Security-scoped access from the already chosen vault bookmark stays alive until
  the helper closes. Requests have deadlines; cancellation closes stdin, then
  terminates/kills a child that fails to exit. Helpers receive only a minimal locale
  environment, not provider credentials. No background export is scheduled.

### Remaining delivery work

The native sheet, app bundle helper resolution, bookmark lifetime, keyboard and
VoiceOver flow still need the macOS build and a disposable-vault live acceptance
run. Test destination movement, read-only/disconnect during review, termination
between publish and receipt, source forgetting, and recovery after relaunch.
A third-party or remote MCP server requires a separately reviewed adapter and
explicit destination choice; this implementation does not imply permission to
send selected content to an arbitrary configured server.

The current recovery record describes the latest export only; a browsable durable
history of all verified exports and source-level external-copy notices is future
work. Unified preference/lesson/to-do ingestion, versioned source locators,
portable source deep links, and the visual graph remain in Stages 1–2.

## Validation evidence and limits

The Linux Swift 6.2.1 temporary harness passed **29 core tests in 6 suites**:
`BrainCaptureTests`, `AboutYouTests`, `SecondBrainTests` (including `TodoTests`),
`TodayTests`, and `VaultBoundaryTests`. Production files were symlinked unchanged;
only the unrelated `ResearchReport.vaultFolder` constant was supplied by the
harness. All filesystem fixtures were temporary. No real vault was opened.

Three `BrainCaptureModelTests` were added for preview/save behavior, revoked
access, and filename collision. The actual model class and tests typechecked in
a Linux harness with native provider/access wrappers stubbed, but linking hit a
Swift Observation runtime symbol error. These tests and the complete app still
require the native macOS build. Those earlier core tests do not establish native UI, bookmark, graph or live
Obsidian acceptance. The local MCP delivery evidence below is separate.

The follow-up portable suite passed **14 tests in 2 suites**: eleven synthetic relationship regressions for exact evidence,
deduplication, removed/missing sources, forget/review preservation, stable ordering
and source-kind identity, plus compiler-to-edited-link reachability, directional
links, ambiguity, deletion and unreviewed text. Three saved-recap navigation policy tests cover
all active phases, missing/cancelled sources and terminal-stage routing. Their
portable execution receipt is recorded by `qa/portable-core/prepare.py`; this is
policy/model validation, not native window or capture acceptance.

Mac acceptance must open an available source from idle, completed and failed
Meetings stages; attempt the same during starting, recording, ending and notes
processing; delete/dismiss/forget the source after rendering its row; and confirm
the original session, pending edits and review/export blocks remain intact.
Verify related-page selection saves edits, clears a search hiding the target,
exposes the shared evidence through VoiceOver and keyboard focus, and still fits
the minimum-size Memory window. No actual vault or private meeting was used in
the synthetic checks.

The MCP export recipe is now part of the default `qa/portable-core/prepare.py`
groups (`wiki-export`). It copies exact production core sources, the real
`MCPStdioClient`, and the exact production export-client conformance. The helper
wrapper only forwards command-line arguments to `WikiExportMCPCommand.run`.
The manifest records the exact `ScribeMeetingRecord` declaration and unrelated
`ResearchReport.vaultFolder` constant excerpts used to isolate the portable
package. This does not build the SwiftUI sheet or verify macOS code signing.

`WikiExportTests` covers selection, provenance, review/access/source changes,
create-only confinement, symlinks/hardlinks, collisions, uncertain delivery,
exact readback, same-ID retry, forgetting, corrupt recovery and confirmed
abandonment. `MemoryMCPTransportTests` exercises a real child process over stdio
with a large Unicode export, plus handshake timeout and cancellation cleanup.
Every filesystem test uses temporary synthetic vaults; no real vault is opened.

Final targeted portable run: **26 tests in 2 suites passed** with Swift 6.2.1
on Linux, including all three real process tests. Receipt:
`/workspace/zeus-validation/wiki-export-06/wiki-export/test.log` and its
`validation-manifest.json`. The interactive process test caught and fixed a
Foundation buffered-read initialization deadlock; the server now uses bounded,
EINTR-safe POSIX reads. Modified native Swift files pass syntax parsing, which
is not macOS typechecking or live UI acceptance. Independent source review also
closed stale-recovery dead ends, wrong-attempt receipt attribution, and hardlink
read confinement findings before this final run.
