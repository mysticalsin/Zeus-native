# Local tasks and agenda

**Branch:** `zeus-bot/local-todo-agenda`

**Base:** `codex/integration-20261111`

**Status:** Draft. The top bar is not wired. Tony approves the mock-up before that follow-up.

## Ticket

Tony, verbatim (t1990u): "the to-do section can actually pull my to-dos from Microsoft To Do on my Mac, and it could also pull, like, my agenda from my Outlook on my Mac without necessarily connecting to Microsoft Entra ID."

The packaged build of this slice has the read, the off switch, and the states. It does not yet show them in the notch.

## Done when

- The read is local and read-only. No Entra, MSAL, or Graph sign-in. No network call, token, cookie, or Keychain read. No write to a task or an event.
- Nothing reads another app's container or Group Container.
- The feature stays off until `todo.microsoftLocal` is turned on. That id lives in the settings catalog, default `false`, state `stub`, so the row is stored and not shown.
- Missing apps, a denied prompt, and an empty day each have their own phase. The phase switch has no `default`.
- Tests use synthetic records. The red commit is `7adc28b26f57decfae7c70a68ba8fb59cae396e2`.

## Routes

| Route | Verdict | What was checked |
| --- | --- | --- |
| EventKit calendars for accounts already in macOS Calendar or Internet Accounts | **VERIFIED** as the read API. **UNVERIFIED** that a calendar which exists only inside new Outlook appears there. | Apple, WWDC23 "Discover Calendar and EventKit" (https://developer.apple.com/videos/play/wwdc2023/10052/): one `EKEventStore`, `requestFullAccessToEvents()`, then `predicateForEvents` and `events(matching:)`. A nil calendar list is every calendar in that store. Full access is the read; write-only is not. Apple's guide "Accessing Calendar using EventKit and EventKitUI" says the same and names `NSCalendarsFullAccessUsageDescription`. Zeus already has that key in `Resources/Info.plist`. Apple's Calendar guide (https://support.apple.com/guide/calendar/add-calendars-and-calendar-accounts-icl4308d6701/mac) is how an Exchange or Outlook account is added to the Mac's calendars. |
| EventKit reminders for Exchange or Outlook tasks that macOS has synced into Reminders | **VERIFIED** as the API and as Microsoft's own support answer for seeing To Do tasks in Reminders. **UNVERIFIED** for a To Do list that never reaches Reminders. | The same EventKit model: `requestFullAccessToReminders()`, `predicateForReminders(in:)`, `fetchReminders(matching:)`. Zeus already has `NSRemindersFullAccessUsageDescription`. Microsoft Q&A, Zachary.W, 12 October 2024 (https://learn.microsoft.com/en-us/answers/questions/4670434/how-to-display-ms-to-do-in-calendar-(mac-ios)): To Do syncs with Outlook tasks, and Apple apps can show those tasks in Reminders when Reminders is enabled on the system account. |
| Legacy Outlook for Mac scripting | **VERIFIED** that a scripting dictionary has existed and can create tasks. **UNVERIFIED** as a stable read-only list on a current build. Not used. | A 2021 DEVONthink forum script addresses `tell application "Microsoft Outlook"`, reads `task folders`, and runs `make new task` (https://discourse.devontechnologies.com/t/microsoft-todo-taskmanager/65717). That is an Apple Event, and the sample writes. |
| New Outlook for Mac scripting | **VERIFIED** as cancelled, from a capture of Microsoft's roadmap feed. The live roadmap page no longer lists the item. | Microsoft 365 roadmap 88537, "Support for AppleScript in the New Outlook for Mac". The webchecks.io capture of that feed, read 21 November 2026 (https://webchecks.io/365-roadmap/88537), quotes Microsoft: full compatibility is not feasible, status Cancelled, and the item left the feed on 4 October 2026. This slice did not retrieve a current microsoft.com page for 88537. |
| Microsoft To Do for Mac scripting, Shortcuts, or a URL scheme that returns tasks | **UNVERIFIED**. Not used. | No Microsoft document was found that gives To Do for Mac a scripting dictionary or a Shortcuts action whose result is the task list. Apple's Shortcuts guide describes `shortcuts://run-shortcut` for shortcuts the person already saved, not another app's database (https://support.apple.com/guide/shortcuts-mac/run-a-shortcut-from-a-url-apd624386f42/mac). A March 2026 note on `ms-todo:` says the iOS app opens and no task payload was found (https://www.reddit.com/r/microsofttodo/comments/1rq9thg/ios_deep_links_to_the_to_do_app/). That is not a Mac read API. |
| Apple Events entitlement and the usage string | **VERIFIED** in this repo. Not extended. | `Resources/Zeus.entitlements` already has `com.apple.security.automation.apple-events`. `NSAppleEventsUsageDescription` names Chrome, Music, Spotify, Terminal, iTerm, Keynote, PowerPoint, and System Events. It does not name Outlook or To Do. Sending those apps an event would be a new prompt and a wider string. |
| Another app's sandbox or Group Container | Not a supported route. Needs Full Disk Access. **Not implemented.** | Reading `~/Library/Containers` or `~/Library/Group Containers` is the widening Tony would have to approve. This slice does not open those paths. |

Bundle identifiers used only as a presence probe, through `NSWorkspace.urlForApplication(withBundleIdentifier:)`, which does not open a container:

- `com.microsoft.to-do-mac` is **VERIFIED** as the Mac App Store app's identifier from a crash report posted on Microsoft Q&A (process `Microsoft To Do`, identifier `com.microsoft.to-do-mac`, version 2.114). https://learn.microsoft.com/en-us/answers/questions/5276170/unable-to-install-the-microsoft-to-do-app-on-macbo
- `com.microsoft.Outlook` is the identifier in the Mac App Store catalog mirror checked November 2026 (https://github.com/cocopuff2u/MOFA). This machine does not have the app, so the binary was not opened.
- `com.microsoft.to-do` appears as a second identifier in that same mirror. **UNVERIFIED** against a binary. The probe treats it as a fallback only.

## Decision

**Primary route:** EventKit, read-only, and only for sources that are Exchange or whose name is Outlook or Exchange (exact, or the prefix `outlook ` / `exchange `). That is the account the Mac already has. Zeus does not sign in.

**Not built, and why:**

1. Apple Events to legacy Outlook. The dictionary can create tasks, new Outlook's scripting was cancelled, and the prompt would widen automation. Needs Tony's approval before anyone writes it.
2. Shortcuts or `ms-todo:`. No verified read of the task list.
3. Full Disk Access to the app container. Documented here so it is a choice, not an accident. Not implemented.

If the account is only inside new Outlook, and it is not in System Settings under Internet Accounts, this read reports that the calendar is not in the Mac's calendars. It does not reach into Outlook.

## PR #77

`zeus-bot/local-calendar` at `d8ebd6f81e322e074f3a56a91ef1228764647cb4` is an open draft. It is 25 commits ahead of this base and is mostly the approval queue. Its own description says it is not reviewed.

The EventKit slice is `0a3fc57f` ("Read the agenda from the calendars already on the Mac"): `LocalCalendarAccess.map`, the Outlook/Exchange name rule, and `OutlookCalendarBridge.usesAppleScript = false`. The reader asks for calendar access and lists source titles. It does not read events or reminders, and it has no on/off switch.

**Do not stack this branch on #77.** Stacking would take the unreviewed approval-card commits with it. Cherry-picking `0a3fc57f` would add a second access type that this feature replaces.

This branch stays on `codex/integration-20261111`. `LocalAccessStatus.map` and `MicrosoftAccountMatch` repeat that status order (restricted, then full read, then write-only or denied) and that name rule, and add the Exchange source kind. If both branches land, delete the smaller calendar types in a cleanup. There is nothing to merge first.

## Behaviour

The machine starts off. Turning it on uses the access it has already been given:

- Nothing readable, and a side not yet asked: `permissionNeeded`, effect `requestAccess`.
- Nothing readable, and every side denied or restricted: `denied`. No prompt.
- Calendar or Reminders allowed: `loading`, then a read of that generation.

A permission answer while the switch is off updates the stored access and does not read. A load or a failure whose generation is not the one in flight is ignored, including after the switch is turned off mid-read.

A finished read:

- No Microsoft app and no Exchange or Outlook source: `missingApp(.applicationsNotInstalled)`.
- An app may be installed, but no such source and no matching records: `missingApp(.notInMacAccounts)`.
- A source, and nothing left after the filters: `empty`.
- Otherwise `populated`.
- A failed read of the current generation: `error(.readFailed)`.

Agenda rows are the local calendar day of the injected clock. An all-day event's end is exclusive, so it does not also appear the next morning. A multi-day event is one row. A timed event is labelled in its own time zone. Recurring occurrences on different instants stay; the same series instant, or the same title, start, end and all-day flag, collapses to one. Exchange wins a mirror over another kind. Incomplete Microsoft tasks are kept, overdue and today first, then later, then no date. Completed tasks and other accounts are left out. Titles are compared after canonical composition, and the first spelling is the one kept.

The pull takes a clock. Tests pass a fixed instant. There is no `Date()` inside the reducer.

## Setting

There is no type named `SettingsSectionRegistry` on `codex/integration-20261111`. The registry that exists is `SettingsCatalog`, generated from `scripts/gen-settings-catalog.py`.

`todo.microsoftLocal` is a privacy toggle, default `false`, state `stub`. Stub rows are stored and exported and `isShown` is false, so Settings does not draw the row. The generator rejects a `true` default and rejects showing the row early. The follow-up changes `stub` to a visible row after the mock-up is approved. An import must not turn it on; the default stays false, same as the other opt-ins in that table.

## Privacy

- Prompts, when the follow-up wires them, are `requestFullAccessToEvents` and `requestFullAccessToReminders`. Those are the ordinary system prompts. Nothing edits TCC.
- The usage strings already in `Resources/Info.plist` are the ones those prompts show. This slice does not change them.
- The EventKit file is behind `canImport(EventKit)`. Its source is scanned for save, remove, commit, AppleScript, URL sessions, MSAL, Entra, Keychain, cookies, Graph, and container paths.
- Presence uses a bundle identifier lookup. It does not open the app or its container.

## Follow-up

Branch suggestion: `zeus-bot/local-todo-agenda-ui`, after Tony accepts `mockup.md`.

- Change `todo.microsoftLocal` from `stub` to a visible row on the existing Privacy page, or on the existing To-do settings page if he prefers that home.
- Fill the existing To-do page and the existing Agenda list. No new window.
- Ask for Calendar and Reminders only after the switch is on.
- Keep Reduce Motion and VoiceOver as the mock-up describes.
- Do not script Outlook or To Do in that PR either, unless Tony has approved that prompt.

## Open questions

1. Is EventKit enough when new Outlook keeps a calendar that Internet Accounts does not have?
2. Do you want the legacy-Outlook Apple Event investigated after this, knowing new Outlook will not answer it?
3. Is Full Disk Access in or out? This slice leaves it out.
4. Agenda is only the Exchange or Outlook sources. Should a later slice show the other calendars too?
5. Undated Microsoft tasks are included. Should the list be today and overdue only?
6. Privacy is the catalog home because the row reads personal data and stays hidden for now. The To-do settings page is the other place it could sit.
