# Smooth motion plan

Owner request, 16 November 2026: "make the animations more smooth like Apple would have them". Audited read-only at
`d946ecd`. Owner's Mac: Liquid Retina XDR, ProMotion 120 Hz. Decisions taken: close test replaced by a fit test; cue
spring option A (settles under 120 ms, R24 kept); mascot plays at the clip's own fps (keep idle at 6 fps only if the
idle CPU cap fails). C9 (draw-on reveal for talk marks) is a separate ticket.

Already right: no `.animation(` without `value:` (TopBarViews.swift:335 belongs to a transition); the island is one
shape whose size animates; the tab pill uses `matchedGeometryEffect` (TopBarViews.swift:354); meeting card motion is
left alone.

## 1. Problems, worst first

1. Panel snaps shut: `TopBarStyle.closeMotion = .linear(GlanceTopBar.closeDuration)` (TopBarViews.swift:18,
   GlanceTopBar.swift:66) drives height, width, drop and content removal (NotchView.swift:232, 235, 241, 405). The
   recorded close heights (GlanceTopBar.swift:64-65) ease into the end: linear 0.1 s misses them by 17 to 22 pt rms; a
   critically damped spring (response 0.175, damping 1.0) by 12.5 pt, measured against the real closed height (38 pt) with no time offset; an earlier 5.2 pt figure used a 60 pt end and an 8 ms offset the app does not draw. Comment at :62 ("a firm 0.40 s") contradicts the code.
2. Panel height jumps on tab switch (Home and others differ by 122 pt; also home strip and approval height): size
   depends on `selectedTab` (NotchView.swift:199) but the size animations key only on `shownHeight`, `presentation`,
   `closedWidthKey` (:231-235); a tab tap sets `selectedTab` without animation (TopBarViews.swift:314). Inferred from code.
3. Pages hard-cut: `.id(selectedTab)` with `removal: .identity` (TopBarViews.swift:496-500).
4. Visible motion on a 30 Hz run-loop `Timer` not locked to the display (TickingView.swift:105-109): halo
   (NotchView.swift:275), `LevelBars` (TopBarViews.swift:157), buddy waveform and spinner (BuddyOverlayView.swift:102,
   :129; 15 degree jumps), ThinkingOrb.swift:28, LivingMascot.swift:105, edit wiggle at 24 Hz (GlanceHomeCards.swift:210),
   onboarding `TimelineView` at 1/30 (OnboardingView.swift:121).
5. Mascot tick rate vs atlas fps (12, 20, 24 in Avatar/Anim/*.json): clock ticks at 24 or 6 Hz (MascotMotion.swift:141-157).
6. Idle stroll at 6 fps: offsets at MascotMotion.swift:65-80, `.idle` ticks at rest rate (:154).
7. HUD cue pops: wing spring 0.09 / 0.86 (NotchClosedBodyLayout.swift:22-23), first 120 Hz frame 12 percent, 95
   percent by 54 ms; literals duplicated at TopBarModel.swift:445-448.
8. Open: GlassBloom fades on a 1/60 timer (GlassBloom.swift:38). Canvas rebuild per frame (NotchView.swift:230,
   843-869): profile before changing.
9. Talk marks pop (C9, separate ticket).
10. Inconsistent curves: buddy `NSAnimationContext` fades without explicit timing (BuddyController.swift:145) and a
    display link bound to `NSScreen.main` (:75); spring literals repeated (NotchView.swift:343-344, 364-392,
    LivingMascot.swift:73-89, TopBarViews.swift:1102, :1475).

## 2. Motion tokens

All in one table; under Reduce Motion every token is instant or the 0.12 s crossfade and ambient loops pause.

| Token | Value |
| --- | --- |
| panelOpen (width) | spring 0.30 / 0.87 (keep) |
| panelOpenHeight | spring 0.105 / 1.0 (keep) |
| panelClose | spring 0.175 / 1.0 (new; no overshoot) |
| panelResize, page | spring 0.34 / 0.84 (existing `Motion.page`) |
| cueGrow | spring 0.12 / 0.90 (settles in about 105 ms over 120 pt, first frame about 7 percent) |
| pageOut | opacity, easeOut 0.08 |
| crossfade | easeInOut 0.12 (existing) |
| press | easeOut 0.12, scale 0.98 (existing) |
| peekContent | spring 0.34 / 0.82, 0.1 s delay (replaces five copies) |
| windowFadeIn / windowFadeOut | 0.2 s easeOut / 0.25 s easeIn (explicit AppKit timing) |
| ambient loops | display link at 60 fps (divides 120); spinner at 120 |
| one-shot (bloom) | display link at the screen maximum with an end time |
| mascot | the clip's fps (12, 20, 24); travel windows at 60 |

## 3. Steps (failing test first, then the change; one commit each)

- C1 tests: `Tests/ZeusCoreTests/MotionTokensTests.swift`: close spring fits `measuredClose` within 8 pt rms with no
  overshoot; cue spring settles under 0.12 s at 120 pt and `SystemHUDWingMotion.allKindsPass()` holds; first 1/120 s
  frame under 10 percent; every damping in 0.75...1.0; ambient fps divides 120; mascot rate is `fps(clipFPS:travelling:)`.
  Replace `GlanceTopBarTests.closeIsFourFramesAfterHalfASecond` (GlanceTopBarTests.swift:122-126) with the fit test.
- C2 Core: `Sources/ZeusCore/TopBar/MotionTokens.swift` (`SpringToken(response:damping:)`, the table,
  `MotionRules.ambientFPS`, mascot rate); `measuredClose` and `closeSpring` in GlanceTopBar.swift with the :60-62 comment
  fixed; NotchClosedBodyLayout.swift:22-23 to 0.12 / 0.90. Add new Core files and suites to qa/portable-core/prepare.py
  where Core files of that group are listed.
- C3 app tokens: extend `Motion` (Preferences.swift:66) with `spring(_:reduceMotion:)` and the tokens; point
  `TopBarStyle.closeMotion`, `NotchView.wingsSpring` (:155), TopBarModel.swift:445 and NotchView.swift:343-392 at them.
- C4 resize and page switch: `.animation(Motion.page(...), value: panelHeightKey)` outside the open-height animation
  (NotchView.swift:232), `panelHeightKey` the open panel height or nil; page removal `pageOut` (TopBarViews.swift:499).
- C5 lint: `Tests/ZeusAppTests/MotionSourceLintTests.swift` (pattern of OnboardingTests.swift:15): fail on a
  `TickingView` interval under 0.1 s outside an allowlist with reasons (NotchLights, HomeBackdrops, HomeWidgetViews,
  ScribeIdleView, ScribeMemoryMascot, OnboardingMascot); `TimelineView(.animation` or `.periodic` under 0.1 s;
  `.animation(` without `value:` outside a transition; `spring(response:` literals in Notch/ and TopBar/ outside the token files.
- C6 display link: the views of problem 4 to `DisplaySynchronizedView(paused:, preferredFramesPerSecond:
  Motion.ambientFPS)`; GlassBloom to `DisplaySynchronizedView(until: start + bloomDuration)` (DisplaySynchronizedView.swift
  handles Reduce Motion, hidden windows and snapshots: :28, 65, 202).
- C7 mascot cadence: `LivingAvatar` at the clip's fps, 60 during travel; update TickingTests.swift:28-29, :78-81 and
  MascotMotionTests.swift:155-159. If an idle CPU cap test fails at 12 fps, keep idle at 6 and say so.
- C8 buddy: explicit timing at BuddyController.swift:145; display link from the buddy window's screen.

## 4. Risks

- CPU: 30 to 60 Hz doubles the halo cost (three shadows, one 26 pt blur) while an agent works; if CPU rises more than
  about 3 percent, animate opacity only. Mascot idle at 12 fps doubles idle cost.
- Tests that must change are named in C1 and C7; ScribeMeetingCardMotionTests and `wingsSpringTargetsUnder120ms` stay green.
- Unverified: SwiftUI animation reaching 120 Hz in this panel; default `NSAnimationContext` curve; the tab-height jump.

## 5. Owner checks on the Mac

Hover open and close ten times; Home to Calendar to Home; volume keys five times (`zeus debug animate volume`); an
agent running (halo); mascot stroll; Instruments Animation Hitches before and after; Activity Monitor CPU idle and with
an agent; Reduce Motion on: everything instant or a crossfade.
