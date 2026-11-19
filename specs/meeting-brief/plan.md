# Implementation Plan: Meeting brief and prompt

**Branch**: `zeus-bot/meeting-brief` | **Date**: 2026-11-19 | **Spec**: [spec.md](spec.md)

## Summary

Keep the local brief and its Sentinel tests. Add a prompt model and a small view for the minutes-before question and the expanded detail.

## Technical Context

**Language/Version**: Swift 6

**Primary Dependencies**: Existing `MeetingBrief` plain-text and collapse rules. No network client.

**Storage**: The existing local history store. The prompt does not write note bodies.

**Testing**: Swift Testing in `MeetingBriefTests` and `MeetingPromptTests`.

**Target Platform**: macOS

**Project Type**: Native macOS app

**Performance Goals**: The prompt decision is a date comparison.

**Constraints**: Local only. No emails in logs. Lead stays inside 5 to 10 minutes.

**Scale/Scope**: One prompt per meeting inside the lead window.

## Constitution Check

- Privacy: local sources only. Off-device stays disabled.
- Red-first: prompt tests land with the model.
- Clean-room: call apps are named only by the string the calendar event already has.
- No Package.swift or workflow edits.

## Project Structure

- `Sources/ZeusCore/Calendar/MeetingPrompt.swift`
- `Sources/Zeus/Calendar/MeetingPromptCard.swift`
- `Tests/ZeusCoreTests/MeetingPromptTests.swift`
- Existing `MeetingBrief.swift` is unchanged except where the prompt calls `plain`.
