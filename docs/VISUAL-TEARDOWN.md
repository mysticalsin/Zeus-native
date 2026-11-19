# the reference app visual teardown (for ZEUS rounds 6 and 7)

## Round 7 top bar (supersedes the round 6 panel rows below)
Source: `teardown/glance-live/TOPBAR-SPEC.md` (live window captures, 19:41 BRT, 2 px per pt).
These values live in `ZeusCore/TopBar/GlanceTopBar.swift`, and the colours in `GlassTheme.swift`
(`Glass.notchPanelFill`) and `GlanceHomeCards.swift` (`GlanceTint`, `GlanceType`).

| Item | the reference app | ZEUS now |
|---|---|---|
| Closed idle | 185 x 32, black, bottom radius 6, square top, no wings | same (idle wings off: Mini ZEUS beside the notch defaults off) |
| Open body | 870 x 210, ears 27.5 wide fading by y 30, bottom radius 22 continuous | 870 x 210 + 2 x 27.5 ears, earHeight 30, continuous 22 |
| Fill | black to (8,8,6) mid to (14,12,11) bottom, no shadow, no blur | `Glass.notchPanelFill`, opaque |
| Ambient glow | warm copper (81,51,46) behind the Calendar card | radial glow at the bottom right |
| Tab capsule | y 41, 34 tall, 24 in, white 10 % | same |
| Selected pill | 80 x 28, white 24 %, 12.5 pt glyph + 12 pt semibold label | same |
| Unselected | mono icon (white 85 %), 11 pt grey count, pitch about 55, 7 tabs | same; row shows 7: Home, Chat, Notifications, Clipboard, Shelf, Tasks, Waves |
| Right side | one 30 pt "more" circle, white 10 % | same (no Dictate pill, no footer) |
| Cards | 4 x 201 x 114, gap 10.5, inset 18, top y 82, radius 22, 1 px rim, content tint | 4 x 200.6 x 114, same gap, inset, top and radius |
| Card type | 11 pt titles (white 70 %), 11 pt subtitles (55 %), 13.5 pt medium media title, light 40 pt numerals, light 34 pt date | same |
| Controls | 30 pt circles, white 12 %, 1 px rim | same (transport 26 / 28) |
| Open spring | response 0.30 to 0.45, damping 0.86, no overshoot | 0.38 / 0.86 |
| Close spring | firm | 0.34 / 1.0 |
| Bloom | 8 to 10 pt frosted rim with bottom glints, gone by 0.4 s | 9 pt rim, glints, 0.4 s, ticks only while it plays |

Proof pairs (to be made by Devon; the `pair` tool lives outside this worktree):
- `teardown/glance-live/tools/pair teardown/glance-live/now/g-open-a.png claude/.build/snaps7b/topbar-10-page-home.png all-proof/live/parity/r7-topbar-open.png`
- `teardown/glance-live/tools/pair teardown/glance-live/now/g-window.png claude/.build/snaps7b/notch-1-closed-working.png all-proof/live/parity/r7-topbar-closed.png`

---


Sources (read-only): live captures `all-proof/live/glance/01-collapsed.png`, `02-hover-expanded.png`,
`02-hover-full.png` (3456 × 2234 px = 1728 × 1117 pt at 2×, 14-inch MacBook Pro), `BAR-REVIEW.md`,
`teardown/glance.md` (timings from the static parity record), `glance-topbar.md`,
`glance-settings-inventory.md` and the 14 `glance-ref/settings-glass-*` sidebar references.
Measurements are taken from the captures. ±2 pt is the reading error. Nothing was copied: ZEUS draws its own UI.

## Closed bar
| Item | Value |
|---|---|
| Notch (hardware) | ≈ 185 × 32 pt on this Mac; ZEUS reads it from `auxiliaryTopLeft/RightArea` |
| Closed shoulders | concave curves into the menu bar, radius ≈ 10 pt; status glow sits under the shoulders |
| Glow breathing | 1.8 s period when the agent needs you, 2.6 s otherwise |
| Side wings | mascot on the left of the notch, state chip on the right, both inside the bar height |

## Expanded panel
| Item | Value |
|---|---|
| Width | ≈ 870 pt (497 → 1503 px displayed, ×0.864), centred on the screen |
| Height (with one card) | ≈ 343 pt from the top of the screen |
| Background | near-black (`#050607`, ≈ 0.96 opacity), whatever is behind barely shows |
| Bottom corners | radius ≈ 26 pt, continuous |
| Top row | the notch row (32 pt): avatar centred on the notch, nothing else |
| Tab capsule row | y 38 → 71 pt, **below** the notch; capsule height 33 pt, left inset 25 pt, fully round |
| Tab item | icon 15 pt, selected item is a lighter pill (white ≈ 0.12) 26 pt tall with icon + label (13 pt semibold) |
| Badges | **numbers** next to the icon (e.g. 29, 1), 11 pt semibold, cloud grey; no dots |
| More button | 33 pt circle, white ≈ 0.08, at the right of the capsule row, inset ≈ 24 pt |
| Secondary pills (New chat, History) | 25 pt tall, 13 pt semibold, stroke white ≈ 0.12 |
| Content card | inset 11 pt left/right/bottom, radius ≈ 24–26 pt |
| Card glass | translucent, tinted by state (green = done); a top-left highlight, a 1 pt light stroke (white ≈ 0.14) and a soft inner glow; the panel shows through slightly |
| Card type | title 15 pt semibold; body 12.5 pt regular, cloud grey; meta chips 11 pt |
| Numerals (Home) | large numbers are **light** weight (not bold), rounded, ≈ 32 pt; the label beside them is 13 pt medium |

## Motion
| Animation | Spring / timing |
|---|---|
| Expand (hover → panel) | spring response 0.30, damping 0.86 |
| Collapse | spring response 0.34, damping 1.0 (no bounce) |
| Peek | spring response 0.35, damping 0.85 |
| Wings | spring response 0.42, damping 0.92, 0.1 s delay |
| Content reveal | starts 0.07 s after the shape, 0.12 s fade |
| Tab pill | matched-geometry slide, ≈ 0.3 s |
| Hover dwell | 0.25 s by default (choices 0.1 / 0.25 / 0.6 s); a dwell ring only past 0.3 s |
| Close after leaving | short delay (≈ 0.3 s) |

## Hover zone
- Opens from the notch **and its corners**: the closed bar's full width (notch plus shoulders), widened
  by ≈ 60 pt each side, down to ≈ 12 pt below the menu bar. Moving diagonally into a corner still opens.
- While open, the zone is the panel frame plus an 8 pt margin, so a quick overshoot doesn't close it.

## Companion
- No buddy or spark is drawn over the open panel. The mascot lives in the bar.

## Settings
- the reference app's sidebar order: General, Appearance, Notifications, Sounds, Voice, Dictation, Shortcut,
  Integrations, Permissions, Privacy, Interview, iPhone, Diagnostics, License.
- ZEUS keeps the sections it actually has. It never shows a "Coming soon" row.
