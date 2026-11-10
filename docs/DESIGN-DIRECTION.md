# Zeus native design direction

Updated 9 November 2026. This applies to the existing macOS app. The references
below are principles for Zeus's own interface, not requests to copy another
product's assets or replace the app with a website.

## Reference map

| Reference | Principle for Zeus | Concrete native application | Acceptance evidence |
| --- | --- | --- | --- |
| Apple animations | Motion explains a state change and remains interruptible. | Short press feedback, a consistent page spring, immediate geometry changes with Reduce Motion, and paced recording/completion sequences. | Record normal-speed transitions on a Mac; interrupt with another tab/action; verify Reduce Motion while the app is running. |
| Duolingo onboarding | A clear next step, visible progress and confidence through small successes. | Show the current setup step and total; retain Back and Set up later; celebrate an actual completed action rather than an unanswered permission request. | Fresh launch, restart midway, denied permissions and deferred setup all reach a usable app without misleading completion states. |
| Linear UI | Clear hierarchy, compact working surfaces and dependable keyboard behavior. | Consistent selected tabs, purposeful status labels, dense but legible meeting/task lists, visible focus and predictable dismissal. | Keyboard-only daily-use walkthrough; selected state is understandable without color or hover. |
| Pentagram typography | Type creates hierarchy and identity without decorative clutter. | Preserve Zeus's licensed bundled display family; use semantic title/body/caption roles, tabular numerals for timers and counts, and comfortable reading widths for notes. | Check long titles, missing-font fallback, multiple languages and text enlargement; no truncation of essential actions. |
| Muji minimalism | Reduce decisions and decoration until each visible element earns its place. | One primary action per task, restrained chrome, progressive disclosure for export/recording options, calm empty states. | A first-time user can identify Start, Stop, Save and Cancel without exploring a menu; active capture is never concealed for visual cleanliness. |
| Airbnb search and filters | Make the current search scope and filter state obvious. | Meeting/Memory search with clear labels, result counts, removable filter chips, useful no-results guidance and one-step reset. | Combined filters, empty results, clearing one filter and restoring search state are verified with synthetic records. |
| Aesop art direction | A coherent, restrained atmosphere with generous attention to composition. | Keep Zeus's existing palette and mascot identity; use quiet backgrounds, controlled contrast and a single purposeful visual focal point. | Review full windows on real desktops in light/dark appearance; decoration must not compete with transcripts or permission/error text. |
| Notion dashboards | Useful information structure and direct links to the underlying work. | Home and Memory cards lead to real meetings, tasks and sources; empty widgets explain how to populate them; user priorities remain configurable. | Each card opens the correct record; source deletion and unavailable data produce truthful states, not invented metrics. |
| Stripe landing layouts | A strong reading order from outcome to detail and action. | Apply the hierarchy to native welcome, feature introduction and upgrade/help surfaces: benefit, concrete capability, evidence, next action. | The user understands the feature and its requirements before choosing it. No separate website is included in this work. |
| Framer microinteractions | Small, consistent feedback makes an action feel direct. | Quiet press/release feedback, deliberate tab selection, immediate copy success, and export progress/completion that reflects actual work. | Rapid repeat actions and cancellation do not leave stuck pressed/success states; feedback remains visible when motion or sound is disabled. |

## Shared interaction changes in this branch

`Motion` now holds shared interaction timings: 120 ms press feedback, a 120 ms
onboarding crossfade, and a page spring with a 0.34 s response and 0.84 damping.
The longer recording and onboarding choreography remains separately defined;
those sequences convey a different kind of state change.

- Shared notch, settings and onboarding buttons use a restrained 2% press scale
  and the same feedback timing. Disabled controls are visibly subdued.
- With Reduce Motion, button press state remains visible without scaling; tab,
  page, toggle and segmented-control geometry changes immediately. Tab labels
  do not blur out, and selected pills do not travel between positions.
- The onboarding header now visibly names the current step and its position in
  the nine-step guide. VoiceOver receives one progress landmark. Reduced-motion
  progress indicators change state without stretching or wiping across the row.
- The welcome animation respects task cancellation when the user changes steps;
  a canceled delay cannot advance the mascot later in another step.
- Existing typography, colors, layout dimensions, feature actions and permission
  flows are retained. This is a shared interaction pass, not a completed redesign.

## Rules for the remaining feature work

**Meaning before decoration.** Capture, mute, pending transcription, saved notes,
and failed exports must look different because they are different states. Use
text or symbols as well as color. A glowing recording indicator must never appear
before capture actually starts; a success reveal must wait for successful save.

**One type hierarchy.** Keep body text readable at native scale. Use the existing
semantic type roles instead of adding a new one-off font to each card. Keep
monospaced numerals for duration, countdown, progress and counts. Truncate
nonessential metadata before the main action or note title, and provide access to
the full value. Long-form notes should be comfortable to read without relying on
wide, very small text.

**Progressive depth.** The first useful action should be easy to find. Detailed
capture modes, speaker diagnostics, provider configuration, MCP destinations and
advanced export settings belong in appropriate secondary surfaces. Explain a
requirement where it matters to the user's decision. Do not expose internal
implementation details as normal product instructions.

**Stable navigation.** A pinned listening bar remains available without blocking
Stop or Dismiss. Search and filters preserve user context. Opening a source returns
the user to the same meeting or Memory page rather than a generic home screen.
Closing or canceling a transient surface never starts another capture.

**Accessibility is part of the style.** Use the system Reduce Motion and Reduce
Transparency preferences; retain meaningful contrast, focus, labels and pressed
states. Support keyboard completion of daily workflows. Visual or audio feedback
alone is insufficient for success, failure, mute, or permission status.

## Native acceptance before visual approval

These changes have not been visually reviewed on a running Mac. Linux syntax
checks cannot establish SwiftUI layout, animation quality, focus behavior,
VoiceOver order, or parity with any reference.

1. On an authorized test Mac, build and run the complete app and existing app
   tests. Keep a rollback copy before replacing an installed app.
2. Walk the nine onboarding steps at normal speed, then with Reduce Motion and
   Reduce Transparency. Check light/dark appearance, Back, Set up later,
   keyboard shortcuts, early dismissal, restarting, and permission denial. The
   user's OS permission prompts remain theirs to answer.
3. Exercise shared buttons using pointer and keyboard; cancel a press by moving
   away; verify disabled controls; switch tabs rapidly; change accessibility
   preferences while the window remains open. There must be no flying pills,
   spring scaling or delayed sweeps with Reduce Motion.
4. Test short and long tab labels, long meeting titles, multilingual text, large
   counts, empty results and error states on a small Mac display and an external
   display. Check that the added onboarding progress label does not collide with
   content and remains legible at normal viewing distance.
5. Review recording, live transcription, mute, countdown, finalization and export
   in motion against the user's supplied references. Do not use a static
   screenshot as proof of animation parity. Capture any evidence only with the
   user's own OS consent.
6. Inspect VoiceOver landmarks, names, values and focus return for onboarding,
   tab selection, search/filter changes and completion windows. Confirm visible
   status remains understandable with audio off.

Approve visual quality only after the actual transitions and complete task flows
meet these criteria. The user-requested principles guide the review; they do not
replace live evidence.
