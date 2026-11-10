# ZEUS

A voice- and screen-aware assistant for macOS that routes every request through your own AI CLIs
(Claude Code, Codex, Gemini, cursor-agent, Ollama) and the Dust API, points at things on your
screen, supervises your coding agents from the notch, and acts in your real Chrome profile.

Development is in progress. A passing subset of tests does not establish native feature completion or a sellable release. The [19-item acceptance map](qa/feature-map.json) and [closed-loop verification guide](docs/CLOSED-LOOP-QA.md) track what is executable, unverified, or still missing. Verification is automated; no manual click-through substitutes for a missing check.

## Layout

| Path | What |
| --- | --- |
| `Sources/ZeusCore` | Shared contracts: brain provider, reply tags, hook and bridge envelopes, native-messaging framing |
| `Sources/Zeus` | The menu-bar app (AppKit + SwiftUI) |
| `Sources/zeus-hook` | CLI that Claude Code / Codex / Cursor hooks call |
| `Sources/zeus-bridge` | Chrome native-messaging host `com.zeus.bridge` |
| `extension/` | ZEUS Chrome extension (MV3, TypeScript, esbuild) |
| `scripts/` | `test.sh`, `bundle.sh` |

## Build

Runs on macOS 14.2+. Building the current sources requires Swift 6 and the macOS 26 SDK
(Xcode 26.1.1 in CI); newer speech and translation features remain availability-gated at runtime.

```sh
swift build
scripts/test.sh                 # uses the selected Xcode/Command Line Tools toolchain
scripts/bundle.sh               # → build/Zeus.app (ad-hoc signed)
open build/Zeus.app
cd extension && npm ci && npm run build
```

## Rules

- No telemetry. Keys go in the macOS Keychain, never in the repo.
- Nothing is copied from HeyClicky or Glance (closed source): behaviour only, never assets, sounds, prompts or names.
- Code adapted from [farzaa/clicky](https://github.com/farzaa/clicky) keeps its MIT notice.
- `zeus-hook` never answers `allow` on its own.

## Chrome

Click **Connect Chrome** in the ⚡ panel. It registers `zeus-bridge` as Chrome's `com.zeus.bridge`
native host (only extension `dkpclhaealkdnnihlccglmonmmjfjobe` may start it) and opens
chrome://extensions plus the `ChromeExtension` folder: turn on Developer mode → Load unpacked →
pick that folder. Then, with Chrome in front, ZEUS reads the active tab, and can open pages,
click and type (asked once per site in the notch, never into password or card fields), and send
prompts to ChatGPT, Claude or Dust in your logged-in tabs.

Debug: `build/Zeus.app/Contents/MacOS/Zeus --chrome page.context` sends one raw bridge request.

## Logo

`Design/zeus-icon.svg` is the source: a Z drawn as a lightning bolt on a storm-dark tile. Rendered to
`Resources/AppIcon.icns` (app), `Resources/MenuBarTemplate*.png` (template image, tinted by macOS),
`Resources/Logo.png` (panel, setup) and `extension/icons/` (Chrome).

## Ease of use (Apple HIG)

- First launch opens **Set Up ZEUS**: one step per permission, each explained before macOS asks,
  one Continue button, skippable, reopenable from the panel or the menu. Nothing is requested at launch.
- Talk key is your choice (Settings): Control+Option, right Option, right Command or Fn. Control+Option
  is refused while VoiceOver is on, since VoiceOver uses it.
- Everything ZEUS says is also captioned next to the spark (Settings › Show captions).
- Reduce Motion: the spark jumps instead of flying, the notch glows steadily, no strike ring.
- Approvals show a countdown and what happens at zero; VoiceOver announces them; no default button.
- Status uses symbol + word, not colour alone; text meets 4.5:1 contrast; buttons are 28 pt with press
  and focus states; Escape closes the panel; ⌘, opens Settings; the menu bar icon can be hidden and
  reopening ZEUS brings Settings back.

## Tests

- `scripts/test.sh`: unit tests.
- `scripts/e2e.sh`: 27 end-to-end checks on the built app: the Chrome bridge in an isolated Chrome for
  Testing profile, hook merge on a *copy* of your settings, real `claude` sessions approved and denied
  in the notch, and real Claude turns emitting the right actions.
- `Zeus --snapshots <dir>`: renders every notch, spark, panel and setup state to PNG.
- `scripts/package.sh`: builds `build/ZEUS.dmg`.
- `python3 qa/release-scripts/test_release_scripts.py`: release and rollback failure paths with mock tools; no real install or capture.

## Release and installation

Ordinary bundles and DMGs are local previews. They do not establish notarization or Gatekeeper readiness.
After choosing the release version/build in `Resources/Info.plist`, configure your own Developer ID identity
and a `notarytool` keychain profile on the signing Mac, then run:

```sh
RELEASE=1 SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
  NOTARY_PROFILE="zeus-release" scripts/package.sh
```

Release mode verifies hardened runtime, Developer ID and secure timestamps, submits the app and DMG,
staples both, and assesses both with Gatekeeper before publishing `build/ZEUS.dmg`. Notary receipts and
the DMG SHA-256 stay in `build/`. A failure preserves the previous DMG. This must still be followed by
a clean-machine launch and feature QA using the user's own OS consent.

To install a prepared app, quit Zeus and run `scripts/install.sh build/Zeus.app`. It verifies the new
bundle and creates a checked rollback copy under `~/Library/Application Support/Zeus/Rollbacks` before
replacing `/Applications/Zeus.app`. It restores the previous app if replacement fails, never deletes
old rollback copies, and does not launch the app or answer permission prompts.
