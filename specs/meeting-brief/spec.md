# Feature Specification: Meeting brief and prompt

**Feature Branch**: `zeus-bot/meeting-brief`

**Created**: 2026-11-19

**Status**: Draft

**Input**: A local meeting brief, plus a prompt a few minutes before the meeting that expands into purpose, context, attendees, the call app, and Join.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Brief stays on this Mac (Priority: P1)

The brief is built from the calendar event, a contact looked up by that attendee's email, and the local last-meeting record. Nothing is sent off the Mac.

**Why this priority**: The Sentinel rules are the condition for showing a brief at all.

**Independent Test**: The brief tests for collapse, lookup, history, plain text, domain match, the log line, and the off-device flag.

**Acceptance Scenarios**:

1. **Given** the screen is shared, recorded, or a meeting app is presenting, **When** the brief is shown, **Then** it is name and time only.
2. **Given** capture state is unknown, **When** the brief has not been opened, **Then** it stays collapsed until it is opened.
3. **Given** Contacts was denied, **When** the brief is shown, **Then** role and company are absent.
4. **Given** a history record, **When** it is saved, **Then** it is the email hash, the date, and a short title. Note bodies are not stored.
5. **Given** the log, **When** a brief is made, **Then** the line is a count only.

---

### User Story 2 - Prompt before the meeting (Priority: P1)

Five to ten minutes before a meeting, by default five, Zeus shows "Your meeting with X starts in 5 min. See it?" A click expands it.

**Why this priority**: This is the prompt Tony asked for.

**Independent Test**: A meeting 5 minutes out produces the line. A meeting 11 minutes out does not. Expanding shows purpose, context, attendees, the call app, and Join only when a link exists.

**Acceptance Scenarios**:

1. **Given** the lead is 5 minutes, **When** the meeting starts in 5 minutes, **Then** the prompt line names the meeting and the minutes.
2. **Given** a lead outside 5 to 10, **When** it is stored, **Then** it is clamped into that range.
3. **Given** the prompt is expanded and the screen is not shared, **When** the detail is built, **Then** purpose is plain text from the invite, context is the local previous record, attendees show role and company only when contacts are allowed, and Join is present only with a link.
4. **Given** the screen is shared or a meeting app is presenting, **When** the prompt is expanded, **Then** purpose, context, role, company, and Join stay hidden.

### Edge Cases

- An empty domain list still treats everyone as external.
- Off-device sending stays unbuilt and off.
- The prompt does not start a recording by itself.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The seven Sentinel rules already tested on `MeetingBrief` stay in force.
- **FR-002**: The prompt lead is configurable from 5 to 10 minutes and defaults to 5.
- **FR-003**: The collapsed line is "Your meeting with X starts in N min. See it?"
- **FR-004**: The expanded detail is purpose, local context, attendees, the call app, and Join.
- **FR-005**: Purpose and context are plain text, truncated, with no live links except the Join button the person taps.

### Key Entities

- **Brief card**: name, time, optional role, company, and summary. Collapsed under the Sentinel rules.
- **Prompt**: the lead window, the one-line question, and the expanded detail.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A meeting outside the lead window does not prompt.
- **SC-002**: Shared or presenting hides the expanded detail.
- **SC-003**: The log line does not contain a name, an email, or the brief text.

## Assumptions

- "X" is the meeting title, or the other person's name when the event has one attendee name. The implementation uses the name the caller already has. It does not look up a new directory.
- Join uses the event's own link. Zeus does not invent one.

## Open questions

- Should the prompt use the meeting title or the first attendee's name when both exist? This build uses the name string the caller passes.
- The live meeting card from the integration merge is a separate surface. This prompt does not replace it.
