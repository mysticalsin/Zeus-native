# Fling: design

Written before any Fling view was built. It follows `docs/DESIGN-DIRECTION.md`: restrained, one accent, text that reads at a glance, motion that explains and stops. Fling adds no new colours and no new fonts: `Theme`, `TopBarStyle.label` and the Settings palette only.

## What a person sees

The Shelf already has a drop zone on the left and a row of file cells. Fling adds one strip above the cells and one glyph on each cell.

1. **Off.** The strip is one line: a paper plane, "Send files to nearby Macs", and a "Turn on" button. Nothing listens until it is pressed.
2. **On, nobody near.** "Looking for Macs running Zeus" in quiet text, and the AirDrop tile.
3. **On, Macs near.** A row of avatars, paired Macs first, then the others by name, then AirDrop last. An avatar is a 34 pt circle with a laptop glyph and the Mac's name under it in 9.5 pt. A paired Mac has a small check badge. A Mac that is not paired shows "Pair" under its name.
4. **Local Network refused.** One line of help and a button that opens the Local Network pane. Nothing else changes and nothing crashes.

### Sending
- Drag a cell, or a file from Finder, onto an avatar. The avatar lights with a ring while the file is over it.
- A paper plane on each cell opens a picker (paired Macs, then AirDrop). A paper plane that is held and flicked toward a Mac sends to it; a flick upward opens the picker.
- A progress ring runs around the avatar while the stack goes out and turns into a check for two seconds.
- Failure says what to do in plain words on the notch ("Could not send. Tap to try again.") and nothing is resent on its own.

### Receiving
- A paired Mac that is allowed to send without asking arrives with a short glow (`lights.fling`) and a cue "3 from Mac B". The files appear on the Shelf with a small seal that means "verified".
- Anything that needs an answer shows a card under the notch, in a panel that never takes the keyboard: the pairing code with Accept and Decline, or "Mac B wants to send 3 items (12 MB)" with Accept and Decline. Sixty seconds without an answer counts as Decline, and the card says how long is left.
- A stack of more than one file shows as one cell with three fanned thumbnails and a count. Opening it shows a ribbon of its files with a back chevron; Escape closes the ribbon.

### Pairing
Both Macs show the same six digits. The person who received the request checks that they match and presses Accept. The other Mac shows the same digits with Cancel. Three declines from one Mac in ten minutes silence that Mac for ten minutes. Only one pairing card is ever on screen.

## Rules the views follow
- Every control has a text label for VoiceOver; the avatar says "Mac B, paired" or "Mac B, not paired, press to pair".
- Reduce Motion: the fly-off arc becomes a fade; rings step instead of sweeping.
- Contrast: text on the notch uses `Theme.cloudPrimary` and `cloudSecondary`; the seal and check use the existing accent.
- A view never starts a transfer by itself. Each send carries the gesture that caused it (`button`, `drop`, `flick`, `menu`).
- Two surfaces carry journey ids for the hosted tests: `fling.turnOn`, `fling.avatar.<id>`, `fling.prompt.accept`, `fling.prompt.decline`.

## Not in v1
Aimed landing, resume after a dropped connection, anything on a phone.
