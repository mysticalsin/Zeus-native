# Late-tap QA for the meeting card

For the build of PR #15, head `2bf968a2`. A person who did not write the change can run this on the real app. It is not a unit test. `Zeus --snapshots` draws the card and does not take the tap, so it does not count.

## Done when

After the offer has left on its own, a click where Record was does not start Scribe. A click while that same offer is still up does start it.

## Setup

1. Build and launch the app from that head.
2. Open Settings, then Features, then Scribe. Set "When a meeting starts" to "Ask me".
3. Do not rest the pointer on the card. A pointer on the card keeps it up.

Use one of these to raise the card. Either is enough.

- Calendar: an event on this Mac that starts within two minutes, with a guest or a meeting link.
- A call: a call app Zeus already treats as a meeting, with that app holding the microphone. The offer appears after the short check, about three seconds.

The offer leaves on its own after the ask timeout. On this build that is 20 seconds from when the offer is shown, longer only while the pointer is on the card.

## Late tap

1. Wait until the card is on screen.
2. Move the pointer off the card.
3. Wait until the card leaves by itself. Do not click Record before it leaves.
4. Click once where the Record button was.

Expected: Scribe does not start. No "Starting" card. The microphone is not opened for a new Scribe recording.

## Still-live tap

1. Raise the card again the same way.
2. While it is still up, and with the pointer not resting on it, click Record.

Expected: Scribe starts. This is the offer that is still live.

## If the card never appears

Stop. Do not call the late tap a pass. The calendar event or the call was not seen. Fix the setup and run again.

## Result

Pending. The person who runs it writes pass or fail, the head SHA, and whether the card appeared.
