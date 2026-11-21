# Implementation Plan: Meeting alerts

**Branch**: `zeus-bot/meeting-alerts` | **Date**: 2026-11-19 | **Spec**: [spec.md](spec.md)

## Summary

The compact notice is `MeetingAlert` plus `MeetingAlertSnapshot`. Tests already cover the size, the clock words, the link hosts, and the tap-only rule. No further code is required for those scenarios.

## Technical Context

**Language/Version**: Swift 6

**Primary Dependencies**: `ScribeCallApp` for the four call kinds.

**Testing**: `Tests/ZeusCoreTests/MeetingAlertTests.swift`

**Target Platform**: macOS

**Constraints**: Do not resize `ScribeMeetingCard`. Its width is pinned by its own tests.

## Constitution Check

- The call names are the ones the accepted meeting-alert spec required.
- Snapshots use synthetic titles. No recording starts from the model.

## Project Structure

- `Sources/ZeusCore/Scribe/MeetingAlert.swift`
- `Sources/Zeus/Scribe/MeetingAlertSnapshot.swift`
- `Tests/ZeusCoreTests/MeetingAlertTests.swift`

## Converge

The in-scope model and tests match the spec. The live-card question stays open and is not implemented.
