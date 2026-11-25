# Implementation Plan: Agent supervision

**Branch**: `zeus-bot/agents-view` | **Date**: 2026-11-19 | **Spec**: [spec.md](spec.md)

## Summary

Keep the calm row. Add a supervision value the row can show: steps, inline Allow and Deny, local usage, and a one-line overview. Do not redesign the session model.

## Technical Context

**Language/Version**: Swift 6

**Primary Dependencies**: `AgentList`, `ApprovalCard.buttons`, `AgentRunState`

**Storage**: None. The timeline is passed in.

**Testing**: `AgentSupervisionTests`, existing `AgentListTests`

**Target Platform**: macOS

**Constraints**: No bouncing indicator. Reduced motion skips the expand spring. The terminal stays a button.

## Constitution Check

- Simplicity: one timeline type, shown inside the row that already expands.
- The session struct gains an optional supervision value. That is not the held NotchView redesign.
- Privacy: no transcript or prompt text is added to the row.

## Project Structure

- `Sources/ZeusCore/Agents/AgentSupervision.swift`
- `Tests/ZeusCoreTests/AgentSupervisionTests.swift`
- `NotchModel.Session.supervision`
- `AgentCard` expanded section and the agents header line
