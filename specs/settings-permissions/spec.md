# Feature Specification: Settings permissions

**Feature Branch**: `zeus-bot/settings-permissions`

**Created**: 2026-11-19

**Status**: Draft

**Input**: One row per capability. Allow when the system can prompt. Otherwise open that capability's Settings pane. Never claim a grant the probe did not return.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - One row, one pane (Priority: P1)

Each capability has a title and the Settings pane that belongs to it.

**Independent Test**: `PermissionDeskTests.eachCapabilityOpensItsOwnPane`.

**Acceptance Scenarios**:

1. **Given** a capability, **When** its URL is built, **Then** the URL ends in that capability's pane.
2. **Given** Microphone, **When** the row is read, **Then** it can prompt. Screen Recording cannot.

---

### User Story 2 - The button comes from one check (Priority: P1)

The row asks `can(resource, action)`. The answer is whether the button is enabled and what it says.

**Independent Test**: `oneCheckDecidesTheButton`.

**Acceptance Scenarios**:

1. **Given** Microphone has not been asked, **When** advance is checked, **Then** the button is enabled and titled Allow.
2. **Given** Screen Recording was denied, **When** advance is checked, **Then** the button is enabled and titled Open Settings.
3. **Given** a capability is already allowed, **When** advance is checked, **Then** the button is disabled and the reason is Allowed.
4. **Given** a probe that is not allowed, **When** it is recorded, **Then** the stored status is that probe, not allowed.

### Edge Cases

- Unavailable describes itself and does not offer a button that claims a grant.
- Grant everything skips allowed and unavailable rows.

## Requirements *(mandatory)*

- **FR-001**: Ten capabilities, each with its own pane.
- **FR-002**: `can(resource, action, status)` returns `can` and `reason`.
- **FR-003**: A row never shows Allowed unless the probe said allowed.
- **FR-004**: Agent actions are not decided here.

## Success Criteria *(mandatory)*

- **SC-001**: The desk tests pass, including the single check.
- **SC-002**: The view has no status switch and no `canPrompt` title branch.

## Decisions

- Settings > Permissions shows this desk, so every capability can be granted from that page.
- The Calendars row calls the local reader only when it is tapped. The reader does not write events and does not run for any other row.
