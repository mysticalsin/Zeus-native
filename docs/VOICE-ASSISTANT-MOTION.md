# Voice Assistant motion for native Zeus

The owner selected the [Voice Assistant Card](https://transitions.dev/studio.html?id=c85AR0dBjUE)
to replace the previous recording/export capsule sweep. The supplied component is
a React demonstration; Zeus adapts its motion to the existing SwiftUI surfaces.
Its simulated café transcript, synthetic microphone levels and timed automatic
success are reference fixtures only. They do not drive Zeus's product state.

## Pinned references

- Supplied text SHA-256: `4df4d29be5ae494276c94866101f0c4a19fd0836b5c4948cc86e581ec2276992`.
- `voice-glow` 0.2.1, MIT, Jakub Antalik. Published ES module SHA-256:
  `4ad0da2472ef3ab0bdacf1e70e1491a9003eb6f8cef5d073334f209ea68a89b8`.
  The license and adaptation notice are in both repository and bundled notices.
- `motion` 14.11.1 and `motion-ai` 14.2.0 were installed in an isolated tooling
  workspace. `npx --no-install motion-ai` completed project-scoped Codex skill
  and MCP configuration there. Its bundled guidance informs native work; no
  JavaScript animation runtime is added to the app. The hosted Motion MCP
  initialization returned HTTP 403. No Motion+ audit or paid capability ran.
- Stageshow, `benjitaylor/skills` at
  `299140fafd08df55a9c234e610c3f64af3f45531`, informs causal movement,
  stable handoffs, interruptions and temporal review. Its React illustration
  workflow is not a substitute for the native app or its control journeys.

## Motion contract

| Element | Reference behavior | Native requirement |
| --- | --- | --- |
| Status change | 150 ms exit, then 150 ms entrance; ease-in-out; −4/+4 pt and 2 pt blur | Latest status wins during interruption; replacement sessions cannot show an old label; accessibility names describe the actual current state immediately. |
| New text | 350 ms opacity/1 pt blur reveal, cubic `(0.22, 1, 0.36, 1)` | Reveal actual incoming content. Never synthesize words or delay completion to imitate the demo. |
| Press | Voice button overrides the generic scale with 0.95 over 150 ms, same smooth-out cubic | Local assistant controls only; cancellation and disabled states remain reliable. |
| Bottom beam | Seven soft color lobes, bloom and chromatic contour rising from the bottom; processing travels in 1.1-second legs with power 2.1 | Per-surface state and size-aware geometry. Actual work controls processing; a clock never declares success. |
| Listening bars | Five bars, 900 ms ease-in-out, minimum 0.35, offsets 0/−0.3/−0.6/−0.15/−0.45 cycles | Only an actual listening surface may represent microphone activity. Screen export must not impersonate live speech. |
| Greeting float | 4 seconds, 3 pt | Applies to the reference's greeting, not to export labels, controls or saved meeting notes. |
| Reduce Motion | No float, wave, movement, blur transition or press scale | A stable readable equivalent; changing the preference while visible takes effect without requiring reopening. |

Zeus keeps its palette, fonts, labels and semantic controls. The native Canvas
beam adapts the reference geometry; it does not reproduce its CSS/SVG turbulence
or browser compositor. Visual equivalence is not established by matching constants.
The pure native beam uses continuous fixed drift, rather than multiplying a
changing audio level by the elapsed session time. This avoids phase jumps when
input changes; it is an intentional adaptation of the stateful reference.

## Display pacing and resource use

The requested target is **240 presented frames per second on a compatible
display**, a **4.17 ms frame budget**. The new recording-card and compact-feedback
clock requests up to 240 Hz from the owning view's native display link, bounded
by that screen's maximum refresh rate. A 120 Hz screen cannot display 240 distinct
frames each second. Moving the window between screens must update the request.

Animation progress derives from elapsed time. Missed callbacks must catch up to
the current state without a queue of obsolete UI updates. Decorative work must
stop when its surface disappears, is hidden, is paused, or has finished its
transition. Reduce Motion keeps a stable equivalent; countdowns, saving and
export completion remain independent of the drawing clock. High refresh is a
visible-animation target, never an idle polling rate.

Dense 240 Hz model samples test continuity and timing. Display-link timestamps
measure callback delivery. Neither establishes actual GPU presentation, CPU
cost, energy use or smooth input on a physical Mac. Release evidence needs the
exact app and hardware, display refresh/scale, duration, delivered-frame and
missed-deadline measurements, resource traces, and the same test with lower-refresh
and mixed displays. Generated GIFs are 20 Hz previews and cannot certify 240 FPS.

## Verification boundaries

The supplied component was bundled and exercised in local Chromium with all
nonlocal requests blocked. Listening, streaming words, processing and reduced
motion assertions passed. No microphone request occurred. Those images and
assertions describe the supplied reference, not a native Zeus app.

Native acceptance requires current-source core timing/continuity tests, real
SwiftUI frame sequences for both producers and accessibility modes, interruption
and expiry checks, and actual reachable recording/export surface journeys.
Generated own-view frames do not establish physical capture, full-app usability,
or donor parity. Hidden surfaces must stop decorative clocks while logical save,
export and countdown state continues independently.
