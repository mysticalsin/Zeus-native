# Board handoff

Updated 2026-11-26, 16:41 America/Sao_Paulo. The drafts whose base was `main` and whose files did not clash were merged. `main` is now `08dce0e9882bfc231ec88c0fb0a0231bd32dc149`.

Still open against `main`, because they edit the same files and Git cannot combine them without a manual resolution:

- #419 notch hover
- #418 agent choice dismiss
- #406 approval preview
- #403 speech-to-text lines
- #401 Right Option hold
- #249 Command dictation
- #19 voice-key walk bound
- #12 voice-key walk socket tests

Pull requests whose base is `codex/integration-20261111` or another feature branch were not merged into `main`. Merging that older line on top of this `main` would replay a different history.

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
3. Leave `main` where it is. Do not force-push. Do not merge a draft whose proof is still pending.
