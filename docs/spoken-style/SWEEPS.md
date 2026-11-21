# Spoken style sweeps

2026-11-21T05:28:00Z. Branch `zeus-bot/spoken-style`. Draft PR #182. Lens: UX polish and motion, read here as the naturalness of the spoken text.

No open review comments, review threads, or Devin notes were on #182. At `89dcbb72e7757b7b4f54789bafe112c5af78c453`, `extension` and `release-scripts` had succeeded and `app` and `feature-map` were still queued.

The root `SWEEPS.md` is on the file lists of open PRs #237 and #242. This log is `docs/spoken-style/SWEEPS.md`.

## Findings

Measured on this Linux VM with Swift 6.2.3, optimized (`swiftc -O`), before the fix:

| input | result |
| --- | --- |
| `The build passed... the details can wait.` | `The build passed.. the details can wait.` |
| `Stop!!!` | `Stop!!` |
| `C'est prêt… les détails peuvent attendre.` | the ellipsis character stayed in the sentence |
| `# Status` plus `The build passed. The logs can wait.` with `maxSentences: 1` | `Status.` |
| `- [x] Ship it` / `- [ ] Wait` | `First [x] Ship it. And last [ ] Wait.` |
| `The ~~old~~ plan is ready.` | tildes kept |
| `The build (the fast one) passed.` | parentheses kept, one run |
| `Line one<br>line two` | `Line one<br>line two.` |
| `See <https://example.com/docs> now.` | `See <example dot com> now.` |
| tilde fence whose body is `secret` | `Wait. ~~~ secret ~~~ Done.` |
| `A & B are ready.` | ampersand kept |
| `THE BUILD PASSED.` | left in capitals |
| `I AM READY.` | left in capitals |
| 40 times `alpha` | 1 run, 40 words |
| 1500 times `alpha` | 1055 ms, 1 run |
| 2500 times `alpha` | 2537 ms, 1 run |
| 8000 times `word` | 18477 ms, 1 run |

## Fixes

Ellipsis and a repeated `!` or `?` become one stop, and the next word is capitalized. A heading with a paragraph after it is a clause lead-in, so a one-sentence budget keeps the heading and that paragraph's first sentence. Checkboxes are spoken `done` / `still open` in English and `fait` / `encore ouvert` in French. Struck text is dropped. Parentheses become clause pauses. `<br>` starts a sentence. Autolink brackets are removed. `&` is `and` or `et`. Two or more fully capitalized words become sentence case before English contractions. A tilde fence uses the same code summary as a backtick fence. A clause longer than 16 words is cut into sentences of at most 16 words. Quantity matching does not copy the tail of a non-numeric word, and contraction matching does not count that tail.

After the fix, same host, optimized:

| input | ms | runs | words per kept run |
| --- | ---: | ---: | --- |
| 1500 times `alpha`, `maxSentences: 2` | 38 | 2 | 16, 16 |
| 2500 times `alpha`, `maxSentences: 2` | 60 | 2 | 16, 16 |
| 8000 times `alpha`, `maxSentences: 2` | 191 | 2 | 16, 16 |
| 500 identical calls of `It is **3.5%** at https://example.com/a.` | 251 |  | `It's three point five percent at example dot com.` |

The combined pathological sample did not contain `secret` or `~`.

## Commits and tests

| | sha | tests |
| --- | --- | --- |
| Red | `a00895718bcd3ebe160ba876265b0971d9a86efb` | 81 tests, 15 failed, 29 issues, 1.099 s. The 1500-word case alone was 1.098 s. |
| Green | `7476da334f8b6efdb847960ad324283124ed3439` | 81 tests passed in 0.053 s (`swift test --filter SpokenStyleTests`, debug). |

The red and green test runs used a throwaway package with only the SpokenStyle sources. `swift build --target ZeusCore` on this repo still fails on Linux with `no such module 'Darwin'` in `Sources/ZeusCore/AgentFollowUps.swift`.
