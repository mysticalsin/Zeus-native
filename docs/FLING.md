# Fling

Fling sends files between Macs that run Zeus, from the Shelf. The plan is `docs/FLING-PLAN.md`, the look is `docs/FLING-DESIGN.md`. This file says how it behaves, what was measured while building it, and what the owner must check by hand.

## S0 findings: TLS with a pre-shared key on Network.framework

Measured on macOS 27.2 (SDK 27.2, Swift 6.4.2) with a throwaway package outside this repository: an `NWListener` and an `NWConnection` over loopback (`requiredInterfaceType = .loopback`), TLS options built with `sec_protocol_options_add_pre_shared_key` on both sides.

| Case | Result |
|---|---|
| Same identity and key on both sides | Handshake completes, a ping and pong round trip works. |
| Server holds several PSKs, client uses the second | Works. The server picks the PSK by the identity the client sends. |
| Client sends an identity the server does not hold | Both sides fail with `-9864 unknown PSK identity`. |
| Known identity, wrong key | Both sides fail with `-9846 bad MAC` (server) and `-9820 bad MAC` (client). |
| Loopback connection | No Local Network prompt in a plain command line process. |
| `NWBrowser` for the Bonjour type in a plain command line process | Reaches `ready`. The policy-denied state was not seen outside an app bundle; it stays an owner check. |

What was negotiated: TLS 1.2 with `TLS_ECDHE_PSK_WITH_CHACHA20_POLY1305_SHA256` (0xCCAC), which has forward secrecy. Setting the minimum protocol to TLS 1.3 or appending other cipher suites did not change the negotiated version or suite, so the app records the suite it got instead of relying on those settings.

Two facts change the plan's wording but not its design:

1. **Do not set an identity hint on the server.** `sec_protocol_options_set_tls_pre_shared_key_identity_hint` makes every handshake fail (`-9858` client, `-9824` server).
2. **The server's PSK list is fixed when the listener is created.** Adding a PSK to the options object after the listener has started is not honoured (`-9864`). So the transfer listener is rebuilt whenever the set of paired Macs changes (a new pairing or a removal), and the new port is re-advertised.

Verdict: TLS-PSK works on this macOS. No replacement crypto is needed.

## How it behaves

- **Off until you turn it on.** Settings > Shelf > "Send and receive with nearby Macs" (or the "Turn on" button on the Shelf) starts the listener and makes macOS ask once for Local Network access. A settings import can never turn it on. While it is off nothing listens and nothing is advertised.
- **Pairing.** Press Pair under a nearby Mac. Both Macs show the same six digits; the Mac that was asked presses Accept. Declining stores nothing. Paired Macs are listed first, under the name they had when you paired. Remove (Settings > Shelf > Paired Macs) deletes the key from the Keychain and the Mac must pair again.
- **Sending.** Drag a file from the Shelf, or from Finder, onto a Mac in the Nearby strip; use the paper plane on a cell; or hold the paper plane and flick toward a Mac (up opens a picker). Every send carries its gesture (button, drop, flick or menu). Nothing sends on a timer, on an arrival, on a retry or on a reconnect. A failed send says so and waits for you.
- **Receiving.** A paired Mac that you let send without asking arrives at once; anything else asks in a card under the notch (Accept or Decline, declining by itself after 60 s). Each file is written to a hidden partial folder, hashed as it arrives, and only visible after its SHA-256 matched what the sender offered. Arrivals go to `~/Downloads/Fling/<Mac> <time>/`, to a private inbox when Downloads access is not granted or the mode is Clipboard or Ask, and show on the Shelf with a seal. Stacks show as one cell with a ribbon.
- **Modes.** Downloads/Fling, Clipboard (the files are also put on the pasteboard so Cmd-V pastes them in Finder), Ask each time (the card offers Save or Copy, even for a paired Mac).
- **Links.** A link is sent as an address, kept as a `.webloc` file, and opened in the browser when "Open received links" is on. Only http and https, at most 2048 characters.
- **Papers.** Off by default. Each arrival can float as a small paper over other apps; closing a paper never touches the Shelf.
- **Persistence.** Fling items on the Shelf survive a relaunch (`~/Library/Application Support/Zeus/Shelf/shelf.json`, at most 500 records, owner-only, never overwritten if it cannot be read).
- **iPhone.** Through AirDrop only: the AirDrop tile in the strip and the picker open the system sheet.

## Protocol v1

Frames are `UInt32 length | UInt8 type | payload`. Header payloads are JSON (at most 64 KiB); a chunk is `UInt32 item index | bytes` (at most 1 MiB). The decoder refuses an oversized frame from its five header bytes and stays failed after any bad frame. Messages: hello, pairCommit, pairKey, pairReveal, pairConfirm, pairDecline, offer, accept, decline, chunk, fileDone, itemResult, stackDone, cancel. A wrong version closes with `version`.

There are two listeners, each advertised as its own Bonjour service of type `_zeus-fling._tcp` (a `r` key in the TXT record says which, a deviation from the plan's single service with a `pp` port; the TXT also carries `v`, `id`, and for Everyone `name` and `model`):

- the **transfer listener** speaks TLS with a pre-shared key. The key identity is the sender's install id and the receiver also checks that the id in the hello is the one the TLS handshake proved. It exists only while at least one Mac is paired and is rebuilt whenever the set changes;
- the **pairing listener** is plain TCP and takes only pairing frames. Anything else gets `decline(notPaired)` and a closed connection. It is closed when visibility is Paired only or Off.

## Threat model and caps

| Threat | Defence |
|---|---|
| Unpaired Mac sends files | The transfer listener is TLS-PSK only; an unknown identity fails the handshake (`-9864`). The pairing port answers an offer with `notPaired`. |
| Spoofed name or id | A paired Mac is shown by the name stored at pairing. The id in a hello must match the key the handshake proved. The six digits and the commitment defeat a man in the middle; one prompt at a time; three declines mute an id for ten minutes. |
| Path traversal | `FlingNames.validate` rejects separators, colon, control characters, a leading dot, `.`, `..`, empty names and more than 255 UTF-8 bytes after NFC. The final path is checked to stay inside the stack folder. Senders clean their own names. |
| Oversized or zip-bomb payload | At most 100 items; header 64 KiB, chunk 1 MiB; bytes beyond the declared size abort; the total must fit in free space minus 1 GiB; archives are never unpacked; links http or https only. |
| Partial or corrupt files | Hidden partial folder (mode 0600, created exclusively), deleted on every end except done and by a launch sweep (older than an hour); a file is visible only after its hash matched. |
| Replay | Stack ids are remembered for ten minutes. |
| Flooding | At most 8 connections, one transfer per peer, 10 s to handshake, 30 s idle. |
| Secrets | Keys live only in the Keychain (service `com.zeus.app`, account `fling.peer.<id>`). Logs carry id prefixes and byte counts, never keys, codes or contents. |
| Sending without a gesture | `FlingService.send(_:to:gesture:)` is the only way in. |

## Limits and warnings

100 items per send; a send over 2 GB says so before it goes and still goes (`FlingLimits.shouldWarn`, REG-699); 8 connections; 60 s prompts.

## Deviations from the plan, and why

- Two Bonjour services of one type instead of a TXT port, so a browser result carries the endpoint to connect to without resolving a host.
- The pairing machine has an `awaitingConfirm` state and the confirmations name their role; the send machine has no separate `offering` state.
- The transfer listener's key list is fixed at creation (see the S0 findings), so it is rebuilt on a pairing or a removal.
- The catalog rows for Fling and the `shelf` section enum case landed with the app wiring, because the Fling light needs `lights.fling`; the Settings page followed in the next slice.
- The flick works from the paper plane on a cell, not from the file icon: a SwiftUI drag gesture cannot share a cell with the system drag session that carries files out to Finder.
- The AirDrop and screenshot watcher gets a pure `isIgnored` check so the skip is testable.
- `qa/closed-loop/contracts.py` and its count test now expect twenty-one features, as they did when F14 was added.
- `Sources/Zeus/App/SettingsStore.swift`, `AppDelegate.swift` and `SnapshotRenderer.swift` each got a few lines the plan did not name (the import guard, the notch-open closure, the snapshot states).

## Owner checks by hand (F15.6)

1. Two real Macs on one Wi-Fi: the peer shows in Nearby within 3 s, the codes match, a decline stores nothing, a file arrives in `~/Downloads/Fling` and on the Shelf, a 4 GB video verifies.
2. Wi-Fi off on both, near each other: does peer-to-peer discovery work? Record the answer.
3. The first enable shows the Local Network prompt once, with the text from the plist. A denial shows the help row and nothing crashes.
4. AirDrop to an iPhone from the Nearby strip, from the picker and from the flick picker opens the sheet with every selected item.
5. Removing a paired Mac deletes its Keychain item; the next send asks to pair again.
6. Clipboard mode: Cmd-V in Finder pastes the file.
7. Papers on: no focus is stolen and closing a paper leaves the Shelf unchanged.
8. The flick: hold the paper plane on a cell and flick toward a Mac; it flies off and arrives; Reduce Motion fades instead.
9. Dragging a stack out into a Finder window copies every file.
