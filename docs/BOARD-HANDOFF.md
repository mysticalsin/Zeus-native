# Board handoff

Updated 2026-11-26, 19:59 America/Sao_Paulo. Every pull request whose base was `main` is merged. `main` is now `0da69d62ff10ac37a0b4b6cf0c5ac3f3beabcd3f`.

These were resolved by hand and landed. Where both sides added behavior, both stayed:

- #419 notch hover, #406 approval preview, and #12 socket tests (already on `main` before this pass)
- #418 agent choice dismiss, at `161a13a322709d00b5628e7d204f7fa091a1f897` (halt and the peer choice card)
- #169 first playback chunk and #125 provider stop, at `14c6b5609295ee723a5da7b464dafa6da82f285c` and `6796c0314b873146337a129a975a1d19ce45577b`
- #401 Right Option hold, at `6eec8c4b5b072508056026d6f83a9472dfe6d51f`
- #403 speech-to-text flush lines, at `89c3ee19c94e6322245005c622f0150990448061` (the latency trace on `main` stayed)
- #19 voice-key walk bound, at `8243690991d910b179c1fcaf0996d78c60f06e21` (the search stops at 1,883,647 states and caches a finished full run)
- #249 Command dictation was already on `main` at `94ac788c3645697b2628f5c050075b0f858bd78d`. A later sync of that branch had no new work, so `0da69d62ff10ac37a0b4b6cf0c5ac3f3beabcd3f` records the pull request as merged and keeps the current tree.

Pull requests whose base is `codex/integration-20261111` or another feature branch were not merged into `main`. Merging that older line on top of this `main` would replay a different history. About 119 of those still use `codex/integration-20261111` as their base. #348 stays on `zeus-bot/s04-11-deck-notes` for the same reason.

The note below is the earlier record of cards that had no branch of their own.

## Already on this remote

The code drafts are open pull requests. Their branches are under `zeus-bot/` and `cursor/`. Newest heads seen on the board include #496 through #518 and #520 through #524. #519 was closed without merging because it overlapped the glow files already on #518.

Two queued cards already have branches:

| Card | Pull request | Branch |
| --- | --- | --- |
| ZGB-17 Animate the push-to-talk top bar | #355 | `zeus-bot/ptt-bar-round-indicator` at `9b4b52220c7ca7937e19fe18082c0df4ded70e3a` |
| ZGB-19 Read in-browser deck notes in the bar | #348 | `zeus-bot/s04-11-deck-notes` at `6a57ddbbd6bb879d9d41bf37aaf04543a6a148cf` |

#355 was merged onto `main` at `733d9b26a87b83be9373410cf8edcbea2f9857b7`. #348 stays on `zeus-bot/s04-11-deck-notes` and was not merged, because its base is the older integration branch.

Parent cards ZGB-1, ZGB-41, and ZGB-42 do not have a branch of their own. Their child drafts are the pull requests already open.

## No branch, and why

These cards are the ones that were not a commit. A later agent can finish them only by staying off the files named here.

| Card | Status | What a later agent should do |
| --- | --- | --- |
| ZGB-254 | Queued | No free HeyClicky or Canopy Foundation pair. Wiring the earbud overlay edits `TopBarLayout.swift`, `TopBarViews.swift`, `TopBarModel.swift`, and `SnapshotRenderer.swift`. `MusicTopBlock.swift` is #476. `NetworkSpeakers.swift` is #457. |
| ZGB-255 | Queued | PointingGuidance needs a real click in an owned window. `StepZeroProbe` and `StepZeroSeal` edit `main.swift` and `StartupPolicy.swift`. `PositionReread` waits on a Mac step zero and edits `MusicPlayerFeed.swift` on #56. |
| ZGB-256 | Queued | Canopy, SystemFocus, Earbuds, and Music had no free Foundation pair. Remaining names need owned app files. |
| ZGB-257 | Queued | A scan of 398 open pulls found the same block. |
| ZGB-259 | Queued | `PositionReread` is the remaining ZeusCore pair, and it needs `MusicPlayerFeed.swift` on #56. |
| ZGB-261 | Queued | Focus and Canopy settings rows need `GlanceSettingsPages.swift`, which many open pulls already change, including #425. |
| ZGB-211 | For review | `NetworkSpeakers.swift` is already #457. It stays closed until Tony says yes. |
| ZGB-220 | For review | The earbuds lint is free as a file, and making it pass edits the battery files on #46. |
| ZGB-237 | For review | No unpaid row had free files whose tests avoid an owned source. |
| ZGB-70 | For review | The research note had no pull request. It is now `docs/handy-mirror-research.md`. Its five named Linux drafts are already #450, #394, #453, #456, and #481. |

## Still being written

ZGB-288 is in progress and had no branch at 14:29 America/Sao_Paulo. Another agent is on that slice: one new Linux file pair after the focus timer box on #524, off owned paths. Do not open a second pair for it.

## How to continue

1. Read the open pull request for the card. The branch on that pull request is the work.
2. If this file says the card has no branch, the blocker above is the reason. Do not invent a second copy of an owned file.
3. Do not force-push. Do not merge a pull request whose base is `codex/integration-20261111` or another feature branch into this `main`.
