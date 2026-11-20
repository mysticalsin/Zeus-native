# Portal

Low confidence. `specs/005-settings-surface/inventory.md` marks Portal UNSPECIFIED: no R-contract and no D-decision names a Portal setting. This file records the reading used for the section. It adds no UserDefaults key.

Placement: the eighth topbar tab. The landed API numbers tabs from zero, so the slot is `.topbarTab(7)`.

## What this section is

Portal is the notch file tray and the nearby-device controls.

1. The file tray is the existing Shelf. A drop is still the Shelf's drop. This section adds the decision for that drop (file URLs only, bounded count and size) and does not replace the Shelf.
2. A dropped file can be converted on this Mac. Conversion is local. It does not use the network and does not start another program. Bytes are read with a hard cap, then written only into a private inbox.
3. Paired devices and sync reuse the existing `fling.*` keys. The master switch stays off unless the person turns it on. Unknown values fail closed.

## Drop conversion

The machine has five phases: `idle`, `received`, `converting`, `done`, `failed`.

- `idle` accepts a drop. A drop that fails the file rules goes to `failed`. A drop that passes goes to `received`.
- `received` accepts `begin` and moves to `converting`. It does not accept another drop.
- `converting` accepts `finish`. Success goes to `done`. Failure goes to `failed`.
- `done` and `failed` accept `reset` and return to `idle`.
- `cancel` from `received` or `converting` returns to `idle` and keeps nothing.
- Any other event is refused and the phase stays as it was.

The tray holds at most 100 items, the same cap as a Fling stack. A full tray fails the drop.

## File rules

A path is refused when it is empty, not absolute, contains a NUL or backslash, or contains an empty, `.`, or `..` component. The source of a drop may sit outside the inbox. The converted file is written only inside the inbox, by a name with no separators.

The read walks from `/` with `openat` and `O_NOFOLLOW`. A symlink at any component is refused. The file must be a regular file, have one link, and be owned by the current user. The inbox directory must be owned by the current user and have no group or other permissions. The write uses `O_EXCL` and `O_NOFOLLOW`, mode `0600`.

Size must be from 1 byte through 8 MiB inclusive. The read stops at 8 MiB plus one byte and then fails. Image width and height must be positive and their product must be at most 16 megapixels.

Types are plain text (`.txt`, `.text`), PNG, JPEG, GIF, TIFF, and HEIC. The extension and the declared type must agree. Text becomes UTF-8, NFC, with newlines folded to LF, and a leading BOM removed. A NUL or an image header inside text is refused. PNG is checked chunk by chunk, including the CRC, and bytes after `IEND` are removed. Other still images become PNG only through the system image frameworks. When those frameworks are not present, the image fails with a clear error. Nothing is executed.

## Paired devices

The section reads `fling.enabled`, `fling.receiveInBackground`, `fling.deviceName`, `fling.visibility`, `fling.autoAcceptPaired`, `fling.saveMode`, `fling.papers`, `fling.flickSensitivity`, `fling.openLinks`, and `fling.pairedMacs`. It does not add a key. Those rows are already in the settings catalog, on Shelf, and `SettingsStore` saves them as `opt.<id>`. `fling.enabled` defaults off. An import can turn it off and cannot turn it on. Nearby sync is that same switch.

`fling.enabled` other than `true` means sync is off: nothing is sent, received, or opened. An unknown visibility value is treated as off. Local network denial fails closed even when the switch is on. Removing a device asks inline, then uses the existing pairing store. It does not open a window.

## Surface

Dark glass cards. Panel padding 32 pt, 28 pt between cards, rows at least 52 pt, and a helper line under every control. The preview tile shows the conversion phase. Reduce Motion uses duration 0 and no press scale. Every control has a VoiceOver label and is keyboard reachable. The paired list has loading, empty, and error states.

## Open questions

- Is conversion a Shelf behavior, a Portal-only behavior, or both?
- Is the output of a drop text-as-UTF-8 and still-image-as-PNG, or some other target?
- Is 8 MiB the right cap, given Fling warns only above 2 GB?
- Should a symlink that resolves inside the inbox be allowed? This spec refuses every symlink.
- A hard link is refused. Is a byte copy of a single-link file enough?
- Should Portal repeat the Shelf's Fling controls, or only show status and point at Shelf?
- The macOS sandbox and a real drag are not established here.
- The brief said `.topbarTab(8)`. The shell numbers the eight tabs from zero and already assigns Portal to `.topbarTab(7)`. This spec follows that.
