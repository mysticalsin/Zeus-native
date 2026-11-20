# End-to-end proof plan

Nothing in this file has been run. A row is **proven** only when every rung that the row marks required is green on the same commit, the evidence names that commit, and a blocked native rung is still a failure. There is no missing-proof override.

Linux can run the unit rung when it is pure Swift. Linux cannot prove a Mac UI rung, a microphone, a face, or a display link. Those stay blocked until they run on a Mac, and a blocked required rung fails the gate.

## Evidence ladder

| Rung | What it is | What it is not |
|---|---|---|
| Unit | A red test, written first, against a pure type. No window, no network, no microphone. | A count of tests, or a sentence that says pass. |
| Integration | The same rule through fakes: a scripted transcript, a generated tone, a bitmap fixture, a fake clock. | A call that skips the type and pokes a private field. |
| Scripted native UI | On a Mac, XCUITest or the accessibility-driven runner activates the real control and reads the visible result: phase label, badge, lamp, notch text. | An offscreen render, a direct controller call, or a screenshot with no action. |
| Live with Tony | Tony performs the sitting below on his Mac, on the commit under test. | A teammate's recording, or a unit test that plays a wav. |

Synthetic fixtures live in a later `Tests/Fixtures/Companion/` (slice S11 in `plan.md`):

- `tone-440.wav` — 1 s sine, generated in the test, never a recording of a person.
- `silence-300ms.wav` — generated silence.
- `buttons.png` — a drawn window with three buttons labelled One, Two, Three, at known pixels.
- `displays.json` — two rectangles, display 1 at the origin and display 2 to its right.
- `transcript-point.txt` — the text "Point at button two."
- `stream-tokens.json` — tokens that emit a point tag, then a first sentence, then more sentences, with the stream end after the first sentence.

No fixture is a screenshot of Tony's real screen, a face image of a person, or a vault from his Mac. Face and AirPods exist only in the sittings.

## What "proven" means

A row is proven when:

1. Its red test failed on the commit before the implementation, and that failure is in the slice's notes.
2. The unit rung passes.
3. The integration rung passes against the fixtures.
4. The scripted UI rung passes on a Mac, or the row says the scripted rung is not required because only Tony can supply the input.
5. If the row lists a sitting step, Tony has done that step in one sitting and the signposts from that sitting meet `perf-budgets.md`.
6. The evidence directory is new, kept on failure as well as success, and contains the command output, the signpost export, and the commit SHA.

Merging this spec proves none of the rows.

## Shared scripted path

The scripted runner, on a Mac, for every row that can be driven without Tony:

1. Launch the app with a disposable defaults domain and a disposable vault.
2. Deny the network for offline rows. Allow it only for the direct-stream row.
3. Place `buttons.png` in a fixture window on display 1.
4. Inject `transcript-point.txt` through the test speech seam, or post the key events the row names.
5. Read accessibility labels for the phase, the badges, and the lamps.
6. Export signposts. Fail if any line contains the transcript or the answer.

## Per row

### R1 Hold Right Option

- Unit: a key-down of Right Option past 0.25 s yields `listening` with no microphone call in the trace.
- Integration: the fake event tap delivers the key at time 0 and the mic fake returns at 200 ms. The phase is `listening` at 50 ms.
- Scripted UI: post Right Option down, read the buddy's phase label "Listening" before the mic fake completes.
- Tony: Sitting A, step 1.
- Pass: p95 under 50 ms, and a tap at 100 ms types nothing into the talk path.
- Proven: all four rungs.

### R2 Right Command stays dictation

- Unit: Right Command produces a dictation start and zero companion phases.
- Integration: both keys down in one fixture. Dictation receives characters. The companion stays `idle`.
- Scripted UI: focus a text field, hold Right Command, see the dictated fixture text. The buddy stays hidden under the default policy.
- Tony: Sitting A, step 2.
- Pass: the text field contains the fixture words and the companion phase log is empty.
- Proven: all four rungs.

### R3 Primary talk key and VoiceOver

- Unit: with the VoiceOver flag set, Control+Option is refused and the fallback key starts the turn.
- Integration: the same flag, plus a second-key Right Option that is free, still starts a turn.
- Scripted UI: the settings row shows the fallback key while the flag is on, and Control+Option again when it is off.
- Tony: Sitting D.
- Pass: VoiceOver's own chord is not consumed. The announced fallback matches the row.
- Proven: unit, integration, scripted UI, and Sitting D.

### R4 Double-tap latch

- Unit: two taps inside the gap move the machine to latched. Silence past the limit returns to `idle` and sends.
- Integration: a fake clock fires the silence timer. One send occurs.
- Scripted UI: two short presses, the phase label stays "Listening" until the silence fixture, then "Thinking".
- Tony: Sitting A, step 3.
- Pass: exactly one send, and a third press is not required to end it.
- Proven: all four rungs.

### R5 Streaming speech-to-text

- Unit: three partials then a stop yield the last stable partial and a time under 150 ms on the fake clock.
- Integration: `tone-440.wav` through the on-device seam. Partials append. The model request contains the final partial and starts before a 2.5 s timer.
- Scripted UI: the caption label updates twice during a held key, then freezes on key-up.
- Tony: Sitting A, step 4, and Sitting C for AirPods.
- Pass: no turn waits 2.5 s when a partial exists. Caption matches the committed text.
- Proven: all four rungs. AirPods is proven only by Sitting C.

### R6 First audio before the full answer

- Unit: `stream-tokens.json` makes `FirstAudioGate` schedule sentence 1 before the stream-end token.
- Integration: a fake speaker records the schedule time. A fake brain yields tokens on a clock. `first_audio` is less than stream end on 27 of 30 scripted turns.
- Scripted UI: a stub speaker plays a generated click at first-audio. The accessibility announcement "Speaking" posts before the stream-end event.
- Tony: Sitting A, step 5, against `perf-budgets.md` for the route his log line names.
- Pass: the route's p50 and p95, and 27 of 30 turns with audio before stream end.
- Proven: all four rungs on that route. A different route is a different proof.

### R7 Streaming speech synthesis

- Unit: a fake socket that yields PCM in three chunks schedules playback on chunk 1.
- Integration: sentence 2's fetch starts while sentence 1's fake player is still "playing".
- Scripted UI: the speaking phase stays up across two sentences with one player, and the caption grows.
- Tony: Sitting A, step 5, same signposts.
- Pass: the first schedule time is before the response body end.
- Proven: all four rungs.

### R8 Barge-in

- Unit: from `speaking`, key-down yields `interrupted` then `listening`, and the effect list is stop-speech, stop-flight, stop-capture, in that order.
- Integration: a fake player, a fake flight, and a fake capture all report stopped before the phase is `listening`. Elapsed fake time is 150 ms or less.
- Scripted UI: start a scripted speaking turn, post the key, read "Listening", and assert the fixture player seam received stop.
- Tony: Sitting A, step 6.
- Pass: audible stop within 150 ms on the sitting log, and no second answer from the cancelled turn.
- Proven: all four rungs.

### R9 Screen capture

- Unit: a denied-permission fake returns a typed failure, not an empty success.
- Integration: `buttons.png` is captured as one display. The failure type speaks through `SpokenFailure` as one short line.
- Scripted UI: with the permission seam denied, the notch shows the spoken line and the phase is `error` then holdable.
- Tony: Sitting A, step 7, with Screen Recording already granted by Tony himself. The test does not click a permission dialog.
- Pass: granted path returns bytes. Denied path speaks and does not call the model.
- Proven: all four rungs.

### R10 Screen understanding

- Unit: a brain fake given `buttons.png` and the point transcript returns a tag for button Two and no other button.
- Integration: the tag's pixels map onto the fixture control's frame.
- Scripted UI: the badge and the flight target sit on button Two's frame within 8 points.
- Tony: Sitting A, step 7, using a window he chooses. He says whether the badge sat on the control he named.
- Pass: the fixture control is the one named. A turn with no brain speaks that it cannot see and does not invent a control.
- Proven: scripted UI for the fixture, Sitting A for a real window.

### R11 Flying pointer

- Unit: a parsed tag emits flight-start within 50 ms of fake time.
- Integration: the flight curve ends inside the target frame. Reduce Motion is a single position write.
- Scripted UI: the buddy's accessibility frame is inside button Two after the turn.
- Tony: Sitting A, step 7.
- Pass: p95 of `companion.point-to-flight` under 50 ms, and the visible buddy rests on the control.
- Proven: all four rungs.

### R12 Numbered marks

- Unit: six marks place in sentence order. A seventh is refused. A mark on a missing display is dropped.
- Integration: `displays.json` puts mark 1 on display 1 and mark 2 on display 2. Labels are "Mark 1, One" and "Mark 2, Two".
- Scripted UI: the badges are visible, numbered, and their accessibility labels match.
- Tony: Sitting A, step 7, on one display, and step 8 if a second display is attached.
- Pass: numbers increase in sentence order and VoiceOver reads them.
- Proven: all four rungs.

### R13 Highlight

- Unit: a highlight tag becomes one rectangle in the overlay model for the duration of its sentence.
- Integration: the rectangle is in the exclusion list of the next capture.
- Scripted UI: the outline is visible around button Three for that sentence and gone after.
- Tony: Sitting A, step 7, if he asks for an outline.
- Pass: the outline's frame matches the fixture within 8 points, and the next capture's excluded-window list contains it.
- Proven: all four rungs.

### R14 Cursor-adjacent mascot

- Unit: a pointer on display 2 selects the display-2 window.
- Integration: the panel is non-activating and click-through.
- Scripted UI: the buddy's frame is within 40 points of the pointer 100 ms after the key, and the front app keeps keyboard focus.
- Tony: Sitting A, step 1.
- Pass: focus stays in the front app. The buddy is on the pointer's display.
- Proven: all four rungs.

### R15 Animation states

- Unit: each phase maps to one pose, and `interrupted` and `error` have their own poses.
- Integration: a phase write updates the notch model and the buddy model in the same turn of the fake scheduler.
- Scripted UI: for each phase, the notch label and the buddy label match the table in `plan.md`.
- Tony: Sitting A, he sees listening, thinking, speaking, and pointing in one hold.
- Pass: no phase shares a pose with a different meaning. Error is not the idle pose.
- Proven: all four rungs.

### R16 Live waveform

- Unit: levels 0, 0.5, and 1 map to bar heights. Reduce Motion yields the rest heights for every level.
- Integration: the speech seam's level callback drives the model with no allocation counted by the test's allocation checker on 120 calls.
- Scripted UI: with motion allowed, the bars' accessibility value changes while `tone-440.wav` plays. With Reduce Motion, it does not.
- Tony: not required. The waveform is not a voice-quality claim.
- Pass: the still-pose assertion under Reduce Motion, and a moving value without it.
- Proven: unit, integration, and scripted UI.

### R17 Conversation memory

- Unit: the 11th turn drops the 1st. A point tag stored in the fixture is stripped.
- Integration: a disposable vault reloads the same 10 turns. The vault bytes contain neither `buttons.png` nor a point tag.
- Scripted UI: two scripted turns, then the second answer's request fixture contains the first transcript.
- Tony: Sitting A, step 9.
- Pass: the second reply can refer to the fixture name from turn 1, and the vault file has no image bytes.
- Proven: all four rungs. R36 adds the relaunch.

### R18 Multi-monitor

- Unit: `displays.json` maps a screen-2 tag onto the second rectangle.
- Integration: removing display 2 drops its marks and rebinds the buddy to display 1.
- Scripted UI: two fixture windows. The badge for screen 2 is on the second window's screen.
- Tony: Sitting A, step 8, only if a second display is attached. If it is not, the row stays unproven for hardware and the fixture rung still runs.
- Pass: the badge's screen id is display 2. After unplug, no badge remains on a dead id.
- Proven: scripted UI plus, for Tony's desk, step 8.

### R19 Offline and no-model fallback

- Unit: `OfflineCorePolicy` with network denied and no keys allows face, instant commands, and dictation, and refuses a brain call.
- Integration: a brain spy counts zero calls for "What time is it" and one spoken refusal for "What is on my screen" when capture is the denied fixture.
- Scripted UI: the notch shows the time, then the refusal line. No helper process from `PerformanceBudget.forbiddenDefaultProcesses` is running.
- Tony: Sitting A, step 10.
- Pass: the spy is at zero for instant routes, and the refusal is the one line.
- Proven: all four rungs.

### R20 Face unlock

- Unit: the reducer, given a match verdict, unlocks, and given a non-match, does not. No network type appears in the effect list.
- Integration: a synthetic feature vector that matches the enrolled fixture vector unlocks. A different vector does not. The camera flag stays off while the feature switch is off.
- Scripted UI: not available. A fake camera is not a face.
- Tony: Sitting B. Required.
- Pass: his face unlocks, a second person or a turned head does not, and the network is off for the whole sitting.
- Proven: unit, integration, and Sitting B. There is no scripted substitute.

### R21 Core controls

- Unit: time, date, arithmetic, and a fast command route to instant, never `brain`.
- Integration: the brain spy stays at zero. The answer matches the fake clock.
- Scripted UI: the notch reads the fixture time within 150 ms of the injected transcript.
- Tony: Sitting A, step 10.
- Pass: p95 under 150 ms and an empty brain-process check.
- Proven: all four rungs.

### R22 Privacy lamps

- Unit: mic-open turns the mic lamp on. Mic-close turns it off. Capture-start and capture-end do the same for the screen lamp. The two lamps are independent.
- Integration: a turn that captures and listens shows both, then neither, and the log line has no transcript.
- Scripted UI: the notch accessibility labels "Microphone in use" and "Screen capture in use" appear and disappear with the seams.
- Tony: Sitting A, step 1 and step 7. He looks at the notch.
- Pass: lamps match the seams. The share setting off keeps the buddy window's sharing type hidden.
- Proven: all four rungs.

### R23 Onboarding

- Unit: the guide's last step is the hold step. Skip records no shortcut change.
- Integration: completing the hold step runs one companion turn against the tone fixture and sets the completed flag.
- Scripted UI: the runner activates Next through the guide, then the hold control, and reads one answer caption.
- Tony: Sitting A, step 11, on a fresh defaults domain, not his real one.
- Pass: one completed turn, defaults unchanged on Skip, Reduce Motion uses the crossfade.
- Proven: all four rungs on the disposable domain.

### R24 Settings

- Unit: the persona setting's default is the current mascot id. The orb id is rejected while the study flag is unfilled.
- Integration: saving Right Option onto dictation returns the refusal from the existing second-talk rule.
- Scripted UI: the persona popup shows the current mascot selected. The orb row is absent or disabled. The shortcut recorder shows the conflict text.
- Tony: Sitting A, step 12.
- Pass: the stored value is the mascot id. An attempt to select the orb does not write.
- Proven: all four rungs.

### R25 Error and recovery

- Unit: a failure event from `thinking` or `speaking` enters `error`, speaks one line of at most ten words, and the next key-down enters `listening`.
- Integration: a brain fake that throws, a speaker fake that throws, and a capture fake that throws each end in `error` with lamps off and no flight left.
- Scripted UI: each injected failure shows the line in the notch and the next posted key shows "Listening".
- Tony: Sitting A, step 13, by turning Wi-Fi off mid-reply on a cloud route.
- Pass: one line, no provider dump, and the next hold reaches listening.
- Proven: all four rungs.

### R26 Reduce Motion

- Unit: the motion policy returns a cut, not a spring, for every phase change and a single write for a flight.
- Integration: the waveform model does not change bar height when the flag is on.
- Scripted UI: with the system Reduce Motion flag set for the test process, a scripted turn shows one pose change and no moving bars.
- Tony: Sitting A, step 14.
- Pass: zero interpolated frames in the frame-pace log, and the phase is still announced.
- Proven: all four rungs.

### R27 VoiceOver

- Unit: the announcement table for each phase and for "Mark N, title" is pure data.
- Integration: a phase change posts one announcement. A mark placement posts one announcement. The buddy view is an accessibility element with the phase label.
- Scripted UI: the accessibility runner reads the phase and the mark labels in order.
- Tony: Sitting D.
- Pass: the spoken labels match the table, and Control+Option still operates VoiceOver.
- Proven: unit, integration, scripted UI, and Sitting D.

### R28 Show, then leave

- Unit: policy `onCall` is visible during a turn and hidden 2 s after the last reason. `always` stays. `never` stays hidden.
- Integration: the fake clock crosses the linger and the window alpha becomes 0.
- Scripted UI: after a scripted turn the buddy window is ordered out. With Always, it remains.
- Tony: Sitting A, step 1, he confirms the buddy left after the answer.
- Pass: the default remains `onCall`. The window is gone after the linger and present for the whole error line.
- Proven: all four rungs.

### R29 Warm on key-down

- Unit: key-down records a warm effect. A second key-down inside 45 s does not. Launch records none.
- Integration: the warm fake is called from the key path and the indicator signpost does not wait for it.
- Scripted UI: not required beyond the signpost export of a scripted hold.
- Tony: the latency log of Sitting A, step 5, shows a warm that started at key-down.
- Pass: warm time is absent from the 50 ms indicator interval.
- Proven: unit, integration, and the sitting log.

### R30 Capture overlaps speech

- Unit: the capture effect is armed on entering `listening`, not on entering `thinking`.
- Integration: the capture fake completes at 100 ms while the hold continues to 1 s. Key-up does not start a second capture.
- Scripted UI: the screen lamp turns on during the held key, before key-up.
- Tony: Sitting A, step 7, the capture signpost starts before key-up.
- Pass: one capture per hold, started before key-up.
- Proven: all four rungs.

### R31 Own windows excluded

- Unit: a window list that contains the buddy id is filtered out of the capture set.
- Integration: the bitmap result's checksum matches the fixture with the buddy pixels absent.
- Scripted UI: the capture saved by the test seam does not contain the buddy's accessibility frame.
- Tony: he glances at a saved fixture capture from the sitting and confirms he does not see the buddy. The file stays on the disposable vault and is deleted at the end.
- Pass: checksum match, and the share switch still hides Zeus when off.
- Proven: unit, integration, scripted UI, and his glance.

### R32 Spoken errors

- Unit: a provider dump becomes the persona line. A quota string becomes the short quota line. Both are ten words or fewer.
- Integration: the speaker fake receives that line and nothing else.
- Scripted UI: the notch shows that line.
- Tony: Sitting A, step 13.
- Pass: the notch text equals the unit's line.
- Proven: all four rungs.

### R33 Notch and top bar

- Unit: the phase-to-notch map equals the phase-to-buddy map.
- Integration: one phase write updates both models.
- Scripted UI: the notch label and the buddy label are equal for each scripted phase.
- Tony: Sitting A, he sees the notch match the buddy.
- Pass: no scripted phase where they differ.
- Proven: all four rungs.

### R34 Persona swap

- Unit: `Persona` default conformance returns the current mascot lines. The orb conformance returns no lines and reports unfilled.
- Integration: selecting the mascot writes `voice.personality` unchanged in meaning. Selecting the orb writes nothing.
- Scripted UI: the settings popup lists the current choices and does not apply an orb.
- Tony: Sitting A, step 12.
- Pass: the spoken fixture line for an error is the current persona's line.
- Proven: all four rungs. This does not prove an orb. R39 stays open.

### R35 Consent

- Unit: a drive plan emits no click effect before an approve event. Escape emits cancel and no further steps.
- Integration: a five-step fake plan runs zero steps until approve, then one step per approve, and stops on Escape.
- Scripted UI: the notch shows the plan. The runner activates Escape. The target app fixture receives no click.
- Tony: Sitting A, step 15. He says "open Notes and stop" and presses Escape. He confirms Notes was not typed in.
- Pass: zero clicks after Escape, including a click that was already queued.
- Proven: all four rungs.

### R36 Durable memory

- Unit: the vault codec round-trips ten turns and rejects a blob that contains image bytes.
- Integration: quit and relaunch the fixture process. The eleventh turn still drops the first. The privacy wipe leaves zero turns.
- Scripted UI: relaunch the app on the disposable domain and run a second turn whose request contains the first fixture transcript.
- Tony: Sitting A, step 9, quit the disposable build and open it again.
- Pass: the restored transcript is present, and after he uses the privacy wipe it is absent.
- Proven: all four rungs.

### R37 Listening lamp on the key event

- Unit: the phase publisher fires on the key event with an empty mic trace.
- Integration: the mic fake is delayed 200 ms. The lamp label is "Listening" at 50 ms.
- Scripted UI: the same delay, read from the accessibility tree.
- Tony: Sitting A, step 1, p95 under 50 ms.
- Pass: the threshold in `perf-budgets.md`.
- Proven: all four rungs.

### R38 Display-rate motion

- Unit: a timestamp series with one gap over 1.5 frames counts one drop. A settled series marks the link paused.
- Integration: a 10 s fake speech clock drives the link shim at 60 Hz and at 120 Hz.
- Scripted UI: on the Mac, during a scripted 10 s reply, the real display link records zero drops.
- Tony: Sitting A, step 14, at each refresh his panel can select.
- Pass: zero drops, and the link paused within 1 s of idle.
- Proven: the scripted UI rung on hardware that actually refreshes at that rate, plus his sitting when the rates differ from the lab Mac.

### R39 Orb

- Unit: `OrbPersonaTests.unfilledStudyStaysOff` asserts the setting is off and the mascot id is unchanged.
- Integration: none until the orb study replaces the marked section in `spec.md`.
- Scripted UI: none until that replacement.
- Tony: none in this plan.
- Pass: the test fails if any orb pixels or Jarvis lines are loaded.
- Proven: not a goal of this plan. The row becomes provable only after the marked section is replaced by the study.

## Sitting A — one sitting, voice and controls

Disposable build of the commit under test. Tony's real vault is not opened. Network state is whatever the step names. He grants microphone and Screen Recording himself if the system asks. The runner does not click those dialogs. Signposts and `log stream` run as in `perf-budgets.md`.

1. Hold Right Option. Confirm the buddy and the notch say listening at once, and the mic lamp is on. Release after "What time is it". Confirm the time, the lamp off, and the buddy leaving.
2. Hold Right Command in a text field. Confirm dictation, and that the buddy did not start a talk turn.
3. Double-tap Right Option, wait, and confirm it stops on its own after silence.
4. Hold and say a sentence with a correction ("Tuesday, no, Wednesday"). Confirm the caption follows and the sent text is the correction.
5. Hold and ask a question that needs a model, with the network up if this build has a cloud key. Confirm he hears the start of the answer before the reply could have finished. The log is checked after the sitting, not by ear alone.
6. Hold again in the middle of that answer. Confirm the voice stops and the buddy listens.
7. Hold and say "Point at the second button" in front of a window with three buttons. Confirm a numbered badge on the second button, the buddy on it, and a spoken line. If Screen Recording is off, confirm he hears that Zeus cannot see, and grant it himself before repeating.
8. If a second display is attached, ask for a control on that display. Confirm the badge is on that display. Unplug it. Confirm the badge is gone and the buddy remains.
9. Ask a follow-up that only makes sense after step 7. Quit the disposable build, open it, ask again. Confirm it still knows. Use the privacy wipe. Confirm it does not.
10. Turn Wi-Fi off. Ask the time. Unlock with his face (Sitting B can be this moment if he is ready). Ask what is on the screen. Confirm a refusal, not a guess.
11. On a fresh defaults domain, walk the welcome guide to the hold step and complete one hold. Then skip a second fresh domain and confirm the keys stayed at their defaults.
12. Open settings. Confirm the persona row is the current mascot and the orb does nothing. Try to put Right Option on dictation and confirm the refusal.
13. With the network off mid-reply, confirm one short error line and that the next hold listens.
14. Turn Reduce Motion on. One reply. Confirm a still pose. Turn it off. One 10 s reply at each refresh rate he can set. The frame log is checked after.
15. Say "open Notes and stop", then press Escape. Confirm Notes received no typing.

The sitting is proven when steps 1–7, 9–10, and 12–15 are done, the signposts meet the budgets for the routes he actually had, and steps 8 and 11 are done or written down as not available on that desk. A step he skips is an open row, not a pass.

## Sitting B — face, one sitting

Network off. No model key in this build. He uses the face he already enrolled, or enrolls in this disposable build and deletes it at the end.

1. Switch face presence on himself. Confirm the camera indicator is the system's, and Zeus's screen lamp is off.
2. Sit in frame. Confirm the status becomes present and the Mac unlocks when he asks it to lock and return.
3. Leave the frame past the lock delay he set. Confirm it locks.
4. Have someone else sit, or hold the laptop so no face is enrolled. Confirm it stays locked.
5. Switch face presence off. Confirm the camera is released.

Proven only if all five happen on this commit with the network off. A unit test of the reducer is not this sitting.

## Sitting C — AirPods, one sitting

His AirPods, connected as the input he selects under the talk microphone setting.

1. Hold Right Option and speak. Confirm the listening lamp and that the transcript matches what he said.
2. Let go. Confirm first audio comes back on the AirPods, not only the Mac speakers, when that output is selected.
3. Take one AirPod out so the route changes mid-hold. Confirm the turn ends with the capture-failure hint and does not send a partial from the broken route.
4. Put them back. One more hold succeeds.

Proven only by these four steps. The built-in microphone percentiles do not cover this sitting.

## Sitting D — VoiceOver, one sitting

VoiceOver on before launch.

1. Confirm Control+Option moves VoiceOver and does not start Zeus.
2. Confirm the fallback key is announced in settings.
3. Hold that key. Confirm VoiceOver speaks "Listening", then "Speaking" on a scripted or live answer.
4. On a pointing turn, confirm VoiceOver speaks each "Mark N" label.
5. Turn VoiceOver off. Confirm Control+Option talks to Zeus again.

Proven only by these five steps.

## Order

Run the unit and integration rungs on every slice before any sitting. Book Sitting A, then B, C, and D in one visit if he wants, in that order, so VoiceOver is not on during the percentile blocks. A failed sitting fixes the named row and repeats that row's rungs. It does not reopen a rung whose code did not change.
