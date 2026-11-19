# Implementation Plan: Local calendar

**Branch**: `zeus-bot/local-calendar` | **Date**: 2026-11-19 | **Spec**: [spec.md](spec.md)

## Summary

`LocalCalendarAccess` and `OutlookCalendarBridge` already implement the spec. `LocalCalendarReader` asks EventKit only when called. No new code.

## Technical Context

**Language/Version**: Swift 6

**Primary Dependencies**: EventKit, behind the reader. The core tests do not import EventKit.

**Testing**: `Tests/ZeusCoreTests/LocalCalendarTests.swift`

**Target Platform**: macOS

**Constraints**: Do not script Outlook. Do not add an OAuth client.

## Constitution Check

- Local only. The report does not send account names off the Mac.
- The finding is written as a fact about public API, not as a copied integration.

## Project Structure

- `Sources/ZeusCore/Calendar/LocalCalendar.swift`
- `Sources/Zeus/Calendar/LocalCalendarReader.swift`
- `Tests/ZeusCoreTests/LocalCalendarTests.swift`

## Converge

The spec matches the code that is already on the branch. Nothing further is implemented.
