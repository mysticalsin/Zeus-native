# Decision

Hover grace N is `ScribeAutoStartTiming.hoverGrace`, 4 seconds. A pointer inside the card may keep the offer tappable only until the offer's own deadline plus N. When the pointer leaves, that extra grace ends. A tap then uses the offer's own deadline.

The ask timeout stays 20 seconds. The slow-start stays 45 seconds.

The native late-tap run on the built app is a merge blocker. It has not been run on this head.

## Residual

`TalkHold.swift` and `ScribePopupLifecycle.swift` stay unwired. Ticket: `specs/talk-shortcut-scribe-expiry/ticket-talkhold.md`. This change does not wire them and does not delete them.
