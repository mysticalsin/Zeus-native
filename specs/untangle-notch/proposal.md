# Notch untangle proposal

**Branch**: `zeus-bot/spec-kit-setup`
**Date**: 2026-11-19
**Status**: Held. Tony has not approved this redesign. Do not start it from this note.

Comments and tests are not removed. The untangle additions for deleting restating comments and for deleting tests that would not catch a bug were declined.

## Decision log

The list of problems, read from the integration tree this branch is on:

- `NotchView.size(for:)` at the panel case and `NotchView.topBarPanelSize` both decide the hover size. `topBarPanelSize` adds `126 + extra + 8` when an approval exists, so a long note changes the panel. `GlanceTopBar.panelSize` is the other copy of the same size.
- `NotchView.size(for:)` also has a second panel formula, `540` wide and `rows * 62` plus `110` when an approval exists, used when there is no top bar. Two panel formulas, one view.
- `NotchView.peekSize` switches on approval, completion, failure, selection edit, work-behind, and recap. Each card brings its own width and height into the window.
- `NotchController` owns the pointer, the click-through flag, the lock flag, approvals, alerts, and the window frame. A change to hover tracking and a change to approval timeout land in the same type.
- `NotchModel.Session` is the agent row (id, name, project, task, status, times, reason). Timeline steps, tool durations, and file counts are not in it, so the agents view on `zeus-bot/agents-view` added an optional `supervision` beside the session rather than inside one agent record.
- `NotchView` draws the closed notch, the peek, the top bar, the approval body, and the agent list. A copy change in the agent row and a geometry change in the hover share the file (`NotchView.swift`, about 990 lines). `NotchController.swift` is about 870 lines.
- Card geometry tests and `GlanceTopBar` constants (body width, card top, row room) must change together, and nothing in the type says so except the tests.

The one fix, if the redesign is approved later:

- One size function owns the hover, the peek, and the closed notch. A notification is a factor that does not add height. Card views report the content they draw, not the window they force.
  - The two panel formulas in `NotchView.size(for:)`.
  - `topBarPanelSize` adding approval height.
  - `peekSize` special-casing every card.
- The notch window controller keeps frame, pointer, and click-through. Approval timeout, lock, and share move with the approval card. Agent sessions move with the agent list.
  - `NotchController` mixing hover, approvals, and alerts.
  - `NotchModel.Session` and `AgentSupervision.Run` as two records of one agent.
- `NotchView` splits by surface: closed and hover frame, approval body, agent list. `GlanceTopBar` stays the source of the top-bar numbers, and the geometry tests read those numbers instead of a second copy.
  - `NotchView.swift` holding every surface.
  - Card tests that repeat `GlanceTopBar` constants as literals.

`zeus-bot/notch-layout-bounds` already stops the hover from adding notification height (`NotchLayoutBounds.size`). That is the bug fix, not this split.

## Scope

In, if approved:

- Split size decisions into one function in ZeusCore, called by the view.
- Move approval presentation out of `NotchController`'s hover path.
- Keep one agent record that can hold a timeline, and delete the parallel only after the row reads it.
- Leave `GlanceTopBar` springs and the top-bar motion tokens as they are.

Out:

- No visual redesign of the top bar.
- No deletion of comments or tests.
- No change to Package.swift, workflows, or CI timeouts.
- The voice-key machine, the meeting card, and the approval button rules.

## Files

- `Sources/Zeus/Notch/NotchView.swift`
- `Sources/Zeus/Notch/NotchController.swift`
- `Sources/Zeus/Notch/NotchModel.swift`
- `Sources/ZeusCore/TopBar/GlanceTopBar.swift` (read-only for numbers; do not retune springs)
- `Sources/ZeusCore/TopBar/NotchLayoutBounds.swift` on the bounds branch
- `Tests/ZeusAppTests/NotchLayoutBoundsTests.swift`
- `Tests/ZeusCoreTests/GlanceTopBarTests.swift`
- `Tests/ZeusCoreTests/AgentListTests.swift` and `AgentSupervisionTests.swift` on the agents branch

## Risk

- Hover, peek, and closed sizes are what click-through uses. A wrong size makes the notch steal clicks or leave a dead band.
- Approval timeout, the hold button, and the lock/share hide rule sit in the controller and the view. Moving them can drop a clear or a button.
- Session identity is the id the stop handler and the approval use. Splitting the record can desync a Stop from its agent.
- The file is large enough that a partial split leaves two size formulas again.

## Test plan

- `NotchLayoutBoundsTests`: a long notification matches a plain hover and stays inside the maximum.
- `GlanceTopBarTests`: row room, card frames, and the close spring stay the current numbers.
- `ApprovalCardTests`: Allow and Deny, command hidden only for lock or share, card gone at the deadline.
- `AgentListTests` and `AgentSupervisionTests`: the row still opens in Zeus, and the timeline counts still hold.
- Hosted app job on the exact head. Linux cannot compile this target.
- Do not start the split until Tony says to. A red hosted job on the current branches is not a reason to begin it.
