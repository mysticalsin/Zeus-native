# Feature Specification: Local calendar

**Feature Branch**: `zeus-bot/local-calendar`

**Created**: 2026-11-19

**Status**: Draft

**Input**: Read the calendars already on this Mac. Do not connect to Outlook. Say so when an Outlook calendar is not visible.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - EventKit only (Priority: P1)

Agenda comes from calendars the Mac already has. Access is read-only and is asked only when the agenda is turned on.

**Independent Test**: `LocalCalendarTests`.

**Acceptance Scenarios**:

1. **Given** full access, **When** the status is mapped, **Then** it is allowed. Restricted wins over allowed. Denied stays denied. Not asked stays not asked.
2. **Given** a source named Outlook or Exchange, **When** the report is built, **Then** it says Outlook is visible through the Mac's calendars.
3. **Given** no such source, **When** the report is built, **Then** it says the calendar is not in the Mac's calendars and that Zeus does not connect to Outlook itself.
4. **Given** the Outlook bridge, **When** it is read, **Then** it does not use AppleScript.

### Edge Cases

- A source named "outlook calendar" matches the prefix. A source that merely contains the letters elsewhere does not have to match. The check is an exact name or a prefix "outlook " / "exchange ".

## Requirements *(mandatory)*

- **FR-001**: EventKit is the reader. No Outlook sign-in is added.
- **FR-002**: AppleScript is not used for Outlook.
- **FR-003**: A missing Outlook source is reported in words. It is not treated as a connected account.
- **FR-004**: The permission note says the read is local and happens when the agenda is turned on.

## Success Criteria *(mandatory)*

- **SC-001**: `LocalCalendarTests` cover the status map, the visible report, and `usesAppleScript == false`.

## Open questions

- Whether the permissions desk row for Calendars is the same switch that calls `ensureAccess` is not wired in this slice. The note and the reader exist.
