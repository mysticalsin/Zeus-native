# Feature Specification: Meeting alerts

**Feature Branch**: `zeus-bot/meeting-alerts`

**Created**: 2026-11-19

**Status**: Draft

**Input**: A compact meeting notice: title, when, and the call. It dismisses itself. Notes start only when the person taps.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - A short notice (Priority: P1)

The notice is one row. It names the meeting, when it is, and which call the link is.

**Independent Test**: `MeetingAlertTests`.

**Acceptance Scenarios**:

1. **Given** a meeting ten minutes away, **When** the model is built, **Then** the when-line is "in 10 min".
2. **Given** a meeting about to start or just started, **When** the model is built, **Then** the when-line is "Now". Older than a minute is "Started".
3. **Given** a link host, **When** it is teams.microsoft.com, a zoom.us host, meet.google.com, or a webex.com host, **Then** the call is identified. example.com/zoom is not.
4. **Given** the notice, **When** time passes, **Then** it is gone after 10 seconds unless the person has already acted.
5. **Given** the notice, **When** nobody taps, **Then** recording does not start.

### Edge Cases

- An empty title is shown as "Meeting".
- The row is at most 440 by 48 points. The model uses 420 by 44.

## Requirements *(mandatory)*

- **FR-001**: Width 420, height 44, dismiss after 10 seconds.
- **FR-002**: Recording starts only from a tap.
- **FR-003**: The call comes from the link host, not from a path segment.

## Success Criteria *(mandatory)*

- **SC-001**: `MeetingAlertTests` pass.
- **SC-002**: Snapshots are named `meeting-alert-{teams,zoom,meet,webex}-{dark,light}.png` when the hosted renderer runs.

## Open questions

- The integration meeting card is a separate surface with its own size tests. This slice does not resize that card. Whether the live card should become this 44-point row is unanswered.
