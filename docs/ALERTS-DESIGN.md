# DESIGN: Alerts (incoming alert, Alerts page, stack)

Owner feedback (2026-11-11): alerts should feel "very sexy, fluid and futuristic", while staying Apple-quality,
legible and cheap on CPU. Follows `DESIGN-DIRECTION.md` (meaning before decoration, Reduce Motion, one hierarchy),
`SCRIBE-RECORDLY-REDESIGN.md` (shared glass rules, no CPU at rest) and `VOICE-ASSISTANT-MOTION.md` (interruptible,
temporal evidence, no decorative clock after the transition ends).

## Evidence of the problem
Snapshot of build 224d9df (`topbar-14-page-notifications.png`): the Alerts page is three flat dark rows (title,
subtitle, "2 mins ago") with an empty 36 pt gap where the app icon belongs, no grouping, no actions, no motion.

Root cause of the empty gap: `NotificationsController.icon(_:)` returned `NSWorkspace.icon(forFile:)`, a lazily drawn
`NSISIconImageRep` image. IconServices draws it on demand; in a headless, sandboxed or off-screen pass (the snapshot
harness, `ImageRenderer`) the draw produces fully transparent pixels. Verified: the same Mail icon drawn into a
bitmap gave 0 opaque pixels of 4096 in such a process. The view treated "non-nil image" as success, so the SF Symbol
fallback never showed and the slot stayed blank. Fix: rasterise once into a bitmap, check that it has visible pixels,
cache it, and fall back to a glyph tile when it is blank (`AppIconCache`, `AlertIconPixels.isBlank`).

## Surfaces
| Surface | File | Change |
| --- | --- | --- |
| Incoming alert (other apps) | `Notch/NotchView.swift` overlay, `Notch/NotchController.swift`, `Agents/AgentTroubleCard.swift` (`NotchNotificationLine`, `NotificationPeeker`) | Slim line becomes the liquid capsule, fed by `AlertPresenter` |
| Alerts page | `TopBar/TodayPages.swift` (`NotificationsPage`) | Grouped stacks, real icons, actions, clear all, "All clear" |
| Scribe call popup | `Scribe/ScribeCallPopup.swift` | Restyle only, via `AlertGlass`; logic untouched |
| Brief card | `Proactive/BriefCard.swift` | Restyle only, via `AlertGlass` |
| Agent failure / finished cards | unchanged | Already use `AgentCardLayout`; they adopt `AlertGlass` later |

## Shared material: `AlertGlass`
One view modifier used by every alert surface.
- Fill: `Theme.storm` at 0.92 over `.ultraThinMaterial`; Reduce Transparency: solid `Theme.storm`.
- 1 px inner highlight: top-down white gradient 0.18 to 0.02, `strokeBorder`.
- Outer glow: the app accent at 0.14 opacity, radius 14, y 6. Accent = the app icon's dominant colour (computed
  once per bundle id from the rasterised icon, cached); blank icon or Zeus itself: `Theme.accent`.
- Typography: `TopBarStyle.label` roles only: title 12.5 semibold, body 11.5 regular, time 10 with `monospacedDigit`.
- No new colours: every tint is `Theme` or the cached per-app accent.

## Incoming alert (the notch capsule)
1. Start state: the notch shape (width 185, the existing closed notch) with no content.
2. Land: the shape stretches down into a glass capsule (width 360, height 64) with
   `spring(response: 0.42, dampingFraction: 0.78)`. Corner radius morphs 10 to 22.
3. Content fades in after the shape lands, staggered 60 ms: icon at 0.30 s, title at 0.36 s, body at 0.42 s,
   each `easeOut(0.2)` plus 3 pt rise.
4. Edge sweep: a 1.5 pt luminous edge in the app accent travels once around the capsule. Implementation: a
   conic gradient layer rotated 0 to 360 degrees over 1.2 s (`linear`), masked by the capsule border, opacity
   fading 1 to 0. One animation, then the layer is removed from the tree. No animation exists after 1.2 s.
5. Dismiss (timeout, swipe up, Esc, Clear): the capsule collapses back toward the notch silhouette (scale toward
   185 x 32 anchored at the top, rising 6 pt, fading). This approximates matched geometry: the notch is drawn by a
   different view, so a true `matchedGeometryEffect` pair is not possible without restructuring it.
6. Hover: pauses auto-dismiss, lifts the capsule 2 pt (shadow grows), and reveals the action row
   Reply / Open / Snooze / Clear (capsule grows to height 100 with the same spring). Leaving restarts the timer
   with at least 1.5 s left. Reply and Snooze are shown only when the source supports them (Reply: Messages,
   Mail, Slack, Teams; Snooze: all, 10 minutes, re-posts the alert).
7. Stack: up to three cards fan behind the front one (each 8 pt lower, 0.94 scale step, 0.55 opacity step);
   beyond three a "+2" chip. Newest in front. Duplicates within 5 s coalesce into one card with a "x2" count.

### Timing by priority (`AlertPriority`)
low 4 s, normal 6 s, high 10 s, urgent: stays until acted on. Timers only count for visible cards; queued cards
start when they reach the front. Hover pauses every timer.

### Reduce Motion
No stretch, no sweep, no stagger, no lift. The capsule cross-fades in and out (0.12 s, `Motion.crossfadeDuration`),
content appears with it. State is identical; only the transition changes.

### Reduce Transparency
`AlertGlass` becomes a solid `Theme.storm` fill with the same highlight and no material.

### VoiceOver
Each alert is announced once, polite, as "App, title, body" (`AccessibilityNotification.Announcement`, posted on
first presentation only; a coalesced duplicate does not re-announce). The card is one element with named actions
Open, Reply, Snooze, Clear, so the hover-only actions are also reachable without a pointer. Esc dismisses when the alert has keyboard focus (after a click or with VoiceOver);
the panel is non-activating and a global key monitor would need Input Monitoring, so Esc is not captured globally.
Swipe up is a click-drag gesture; a trackpad two-finger scroll does not dismiss.

## Alerts page
- Grouped by app, newest group first (`AlertGrouping`). A group is a stack: header (icon, app name, count, chevron)
  and rows. The newest group opens by default; others collapse to a header with the newest line as subtitle.
- Rows: 22 pt icon from `AppIconCache` (brand logos via `EngineBrandLogo` for agent engines), title, one-line body,
  relative time in monospaced digits ("now", "2m", "3h", "2d"; `AlertRelativeTime`).
- Actions: hover reveals Open and Clear on the trailing edge; swipe left (trackpad) clears; context menu and
  VoiceOver custom actions mirror them.
- Clear all: header button; rows collapse into their group header with a staggered `spring`, then the page shows
  the empty state. Clear all remembers the newest id (kept across launches), a single Clear hides one alert until the
  next launch; Notification Center itself is never modified.
- Empty state "All clear": idle mascot pose at 56 pt, one line "All clear. New alerts land here." No animation.
- Permission and disabled states keep their existing copy.

## Performance contract
- No `Timer`, `TimelineView`, `DisplaySynchronizedView` or `repeatForever` in `Sources/Zeus/Alerts/`. All motion is
  one-shot SwiftUI animation, so an idle alert surface owns no display link or timer. A source lint
  (`qa/closed-loop/tests/test_alerts_lint.py`) enforces this; `AlertMotion.isAnimating` proves in Core that the
  animation window ends (1.2 s) and that Reduce Motion has none.
- Auto-dismiss uses one cancellable `Task.sleep` to the next deadline, not polling.
- Icon rasterisation and accent extraction run once per bundle id and are cached (64 px bitmap, 12 hue buckets).
- Acceptance on the owner's Mac: an idle Mac with the Alerts page open stays under 1 % CPU; a burst of ten alerts
  stays under 10 % for the 1.2 s sweep and returns to idle afterward (Instruments, Time Profiler).

## Model (ZeusCore, pure, tested)
`AlertStack`: queue, coalescing duplicates within 5 s, max 3 visible, per-priority deadlines, hover pause.
`AlertGrouping`, `AlertRelativeTime`, `AlertAccent` (dominant colour from RGBA pixels), `AlertIconPixels`
(blank-icon detector), `AlertMotion` (timings and the `isAnimating` window), `AlertAppGlyph` (fallback symbols).

## Snapshot states
Single alert (landed), stack of three with "+2", hover with actions, page grouped, page empty. Each is rendered at
rest (post-landing). Motion claims need a screen recording on a Mac; stills do not prove them.

## Not in this change
Replying inline from the notch (Reply opens the source app), a notification action API for other apps' own
buttons, and a global Esc shortcut.
