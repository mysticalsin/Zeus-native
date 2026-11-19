# Plan: can(resource, action) for the permissions desk

**Branch**: `zeus-bot/settings-permissions` | **Date**: 2026-11-19

## What is copied

Refine's access check is `can({ resource, action }) -> { can, reason }`. Zeus stays Swift. No Refine package is added. Agent actions are not part of this plan.

## What it replaces

The desk view had two branches of its own: a status switch, and a button title chosen by `canPrompt` with the button disabled when the status was already allowed.

`PermissionDesk.can(resource:action:status:)` now returns that decision.

- `describe` — `reason` is the status line. `can` is false only when the capability is unavailable.
- `advance` — `can` is true when a button can do something. `reason` is "Allow" when the system can prompt, "Open Settings" when it cannot, and the status line when the button is disabled.

The view reads `reason` and `can`. It no longer switches on status or on `canPrompt`.

## What it does not do

The rules still differ by capability. That difference lives in one function instead of the view. Agent allow and deny stay on the approval card.
