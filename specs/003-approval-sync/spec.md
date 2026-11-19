# Feature Specification: Approval sync

**Feature Branch**: `003-approval-sync`

**Created**: 2026-11-19

**Status**: Draft

**Input**: Tony, 2026-11-19. A choice answered in the terminal must clear Zeus's card, and a hung-up hook must not leave the card up. Verified on main `d6d45dde`.

## What is true today

- `AgentEventServer` handles `PermissionRequest` by calling `notch.requestApproval` (`Sources/Zeus/Agents/AgentEventServer.swift`, the case at line 96). Nothing in that case withdraws the card when the person answers in the terminal first.
- `PostToolUse` for `AskUserQuestion` only calls `QuestionAnswers.shared.toolResult` (lines 83–90). It does not withdraw an approval card.
- `HookEvent` (`Sources/ZeusCore/HookEnvelope.swift`) has `id`, `tool`, and `input`. It has no tool-use id.
- `UnixSocket.Connection.receive` (`Sources/ZeusCore/UnixSocket.swift`, lines 342–372) treats a failed read as `finish()`. That close does not tell the approval card the peer hung up.

The behaviour of the command-line tool when Tony answers in the terminal has not been confirmed on a Mac. This spec does not claim that the tool emits a particular event today. Native confirmation comes first. Until that log exists, the withdraw event is specified, not asserted as already sent.

## User scenarios

### User Story 1 - One answer clears both (Priority: P1)

One answer, in the terminal or on the card, clears both within 300 ms (p50). There is no duplicate card and no stale card.

**Independent Test**: A synthetic hook line with a tool-use id raises one card. A later line with the same id and a terminal answer withdraws that card. The reverse, a card answer, is already the queue's allow path and must still carry the same id.

**Acceptance Scenarios**:

1. **Given** a permission request with a tool-use id, **When** the card is shown, **Then** the card is stored under that id.
2. **Given** the card is up, **When** a terminal answer for that same id arrives, **Then** the card is withdrawn and no second card is shown.
3. **Given** the card is answered in Zeus, **When** the decision is sent, **Then** it names the same tool-use id.

### User Story 2 - The hook hangs up (Priority: P1)

If the waiting hook's socket closes before a decision, the card is withdrawn.

**Independent Test**: Close the test socket while a card is waiting. The card leaves. No decision is written after the close.

**Acceptance Scenarios**:

1. **Given** a card is waiting on an open socket, **When** the read fails or the peer closes, **Then** a hangup event withdraws that card.
2. **Given** the card was already answered, **When** the socket then closes, **Then** the close does not invent a second verdict.

### User Story 3 - Face check (Priority: P2)

When the notch-parity face check is on, it is what allows the answer. This slice does not implement that check. It only refuses to clear both sides before the check, once that setting exists. Until then, the existing approval path remains.

## Requirements

- **FR-001**: `HookEvent` MUST carry a tool-use id, distinct from the envelope `id` when the hook sends one. A missing tool-use id MUST NOT be invented as a random UUID that could collide with another request.
- **FR-002**: A terminal answer for a tool-use id MUST withdraw the card for that id. The card answer MUST send the decision with that same id.
- **FR-003**: A failed read or peer close on the hook socket MUST emit a hangup for the in-flight request and withdraw its card.
- **FR-004**: The command-line tool's actual event when Tony answers in the terminal MUST be confirmed on a Mac before the parser is pinned to a field name. The red test uses a fixture line, marked as unconfirmed against the live tool.
- **FR-005**: One answer clears both places within 300 ms (p50) once the events exist. That figure is a target, not a measurement.
- **FR-006**: "Start automatically" and the 20 s meeting-card timeout are not part of this slice.

## Success criteria

- **SC-001**: A fixture terminal answer withdraws exactly one card, the one with that tool-use id.
- **SC-002**: A socket close withdraws the waiting card and does not write a decision.
- **SC-003**: The Mac log of a real terminal answer is attached before the fixture's field names are called final.

## Assumptions

- PR #14's approval queue is the card this slice withdraws.
- Face verification stays specified in notch parity. This slice calls it when that setting is on and does not bundle a model.
