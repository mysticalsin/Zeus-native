# Face presence card: design

Written 14 November 2026 for ticket FP-9 of `docs/FACE-PRESENCE-PLAN.md`. The plan owns the rules and the row table;
this note fixes how the one visible surface looks and speaks. Nothing here adds a surface: no notch cue, no menu bar
item, no preview of the camera.

## Where it sits

One card, "Face presence", on the Privacy page, after the "Music" card. It is built from the Settings kit in
`GlanceSettingsStyle.swift` (`GSCard`, `GSRow`, `GSToggleRow`, `GSDivider`, `GSPopup`, `GSButtonStyle`) with the
existing type roles. No new colour, no new type size, no new motion.

## Rows, top to bottom

| Row | Control | Notes |
| --- | --- | --- |
| Face presence | Switch | Stored as `face.presence`, default off. Off stops the camera at once. |
| Status | One word, tabular numerals | Symbol in the icon column. The word changes in place. |
| Face 1, Face 2 ... | Switch and a delete button | One row per enrolled face. A face that is switched off is kept and never matched. |
| Enroll | Button | Enabled only in the watching, present and away states. Under it: "Saving a face asks for Touch ID or the device passcode. Zeus does not keep the face print after it checks a match." |
| Lock after absent for | Menu | Stored as `face.lockAfter`: 30 seconds, 1 minute, 2 minutes (default), 5 minutes, 10 minutes. |

The Enroll line is the one sentence on the card, because that is what the keychain enforces. Saving and reading the face print ask the system for Touch ID or the device passcode. The print is not kept after a match. When the fingerprints on this Mac change, the card adds "Fingerprints on this Mac changed. Enroll this face again." No other helper text, and no preview of the camera.

## Status words and symbols

Off (`person.crop.circle`), Needs camera (`video.slash`), Enrolling (`person.crop.circle.badge.plus`), Watching
(`eye`), Present (`person.crop.circle.badge.checkmark`), Away 1:42 (`person.crop.circle.badge.clock`), Locked
(`lock`), Paused (`pause.circle`), Unavailable (`exclamationmark.triangle`). Status is never colour alone: the symbol
and the word carry it. The countdown uses monospaced digits so the word does not shift as the time runs down.

## Motion

None. The status word changes in place. While the state is away the row is redrawn once a second so the countdown
reads true; in every other state it is drawn when the state changes. Nothing animates, so Reduce Motion needs no
branch.

## Accessibility

- The status text carries the full sentence for VoiceOver: "Face presence status: Away, 1 minute 42 seconds left".
- Each face switch is labelled with the face name, and each delete button reads "Delete Face 1".
- The menu is labelled "Lock after absent for". The switch is labelled with its row title.
- Order is the visual order, top to bottom, so VoiceOver reads the card in the order it is drawn.
- Text and rims use the Settings palette, which holds its contrast in the dark panel it is drawn on.

## Deleting and switching off

Switching a face off or deleting it is immediate and asks nothing: it is one face of several, and enrolling again
takes seconds. Deleting the last face removes the template from the keychain. The template is a data-protection
keychain item (`WhenUnlockedThisDeviceOnly`, current fingerprints or the device passcode). A cancelled prompt
saves nothing and reads nothing. The card's names do not include the face print.

## Review fixtures

`Zeus --snapshots <dir> --snapshot-match face-presence` renders the card for every status word, with one and two
faces and with a face switched off, from fixed values (`FacePresenceCardFixtures`). The render never touches the
controller, the camera, the vault or the Keychain.
