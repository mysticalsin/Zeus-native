# Feature Specification: Agent supervision

**Feature Branch**: `zeus-bot/agents-view`

**Created**: 2026-11-19

**Status**: Draft

**Input**: A calm agent row, plus a live timeline, an inline approval, a local cost only when it exists, and a compact line when several agents run.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - The row stays in Zeus (Priority: P1)

Opening a row shows its detail here. It does not open a terminal. The terminal is a separate button.

**Independent Test**: `AgentList.rowOpensDetails` is true and `rowJumpsToTerminal` is false.

**Acceptance Scenarios**:

1. **Given** an agent row, **When** it is opened, **Then** the detail is in the row.
2. **Given** the row, **When** VoiceOver reads it, **Then** it hears the name, project, status word, and activity.

---

### User Story 2 - The timeline (Priority: P1)

Each agent can show steps, tool calls, how long each took, files changed as plus and minus counts, and a test or command result.

**Independent Test**: `AgentSupervisionTests`.

**Acceptance Scenarios**:

1. **Given** three steps, **When** the run is built, **Then** each keeps its duration, and a file edit shows "+N −M".
2. **Given** a test step, **When** it has an outcome, **Then** that outcome is the result string.

---

### User Story 3 - Needs you (Priority: P1)

A waiting agent shows Allow and Deny inline, the same titles as the approval card. High risk still holds.

**Acceptance Scenarios**:

1. **Given** needs-you and high risk, **When** the run is built, **Then** the buttons are Allow and Deny and Allow holds.
2. **Given** a working agent, **When** the run is built, **Then** there are no approval titles.

---

### User Story 4 - Several agents (Priority: P2)

When more than one agent is running, one line counts them and how many are working, waiting, or in error.

**Acceptance Scenarios**:

1. **Given** one agent, **When** the overview is asked, **Then** it is that agent's status word.
2. **Given** three agents in different states, **When** the overview is asked, **Then** one line names the counts.

### Edge Cases

- Token count and cost appear only when a local number was provided. Missing numbers are not shown as zero.
- The activity mark does not bounce. Reduced motion removes the expand spring.

## Requirements *(mandatory)*

- **FR-001**: Detail stays in Zeus. The terminal is an explicit button.
- **FR-002**: A timeline step has a title, a kind, an elapsed time, optional file counts, and an optional outcome.
- **FR-003**: Waiting uses `ApprovalCard.buttons`.
- **FR-004**: Usage is omitted when both local numbers are absent.
- **FR-005**: The overview is one line.

## Success Criteria *(mandatory)*

- **SC-001**: The supervision tests pass.
- **SC-002**: A working row still does not bounce.

## Open questions

- Live steps are not yet fed by a running agent process. The model and the row accept a timeline when one is supplied. Wiring a live agent feed is a later slice.
- Snapshot PNGs are produced by the hosted app job when `ZEUS_QA_ARTIFACT_DIR` is set. This environment does not render them.
