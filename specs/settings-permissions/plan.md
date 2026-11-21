# Implementation Plan: Settings permissions

**Branch**: `zeus-bot/settings-permissions` | **Date**: 2026-11-19 | **Spec**: [spec.md](spec.md)

## Summary

Keep one row per capability. Move the button and status decision into `PermissionDesk.can`. See `specs/permissions-access/plan.md`.

## Technical Context

**Language/Version**: Swift 6

**Primary Dependencies**: None added.

**Testing**: `PermissionDeskTests`

**Target Platform**: macOS

**Constraints**: Do not claim an ungranted permission. Do not add a package. Agent actions stay out.

## Constitution Check

- Red-first test covers Allow, Open Settings, and a disabled Allowed button.
- Privacy: the desk only reports the probe it was given.

## Project Structure

- `Sources/ZeusCore/App/PermissionDesk.swift`
- `Sources/Zeus/Settings/PermissionDeskView.swift`
- `Tests/ZeusCoreTests/PermissionDeskTests.swift`
