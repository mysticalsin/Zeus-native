# Closed-loop Zeus checks

The stable aggregate check is **`required-checks`** in [`.github/workflows/build.yml`](../.github/workflows/build.yml). It requires `app`, `extension`, `release-scripts`, and `feature-map`. The gate runs with `if: always()` and accepts only `success` from every prerequisite, complete passing command receipts, and verified evidence for the exact tested revision, source head, workflow run, and run attempt. Failed, cancelled, skipped, missing, malformed, stale, or zero-test results do not pass.

The active native repository is [mysticalsin/Zeus-native](https://github.com/mysticalsin/Zeus-native), created with a clean native root commit [`f07b1192ebdfb85f0dd9dadba397b52bbd63eebe`](https://github.com/mysticalsin/Zeus-native/commit/f07b1192ebdfb85f0dd9dadba397b52bbd63eebe). The historical private `mysticalsin/Zeus` repository and its unrelated default `main` remain separate and unchanged.

**Merge protection is not yet verified or enabled by this setup.** On 10 November 2026, the connected integration verified public native `main`, the exact audited source hashes, an active workflow, and ADMIN repository visibility. GitHub nevertheless rejected creation of the reviewed ruleset with HTTP 403, “Resource not accessible by integration”; the classic branch-protection read endpoint also returned HTTP 403. The ruleset inventory remained empty. Public visibility resolved the old repository-plan limitation, but did not grant this integration Administration API access.

The prepared policy requires a pull request, strict current-revision `required-checks` from GitHub Actions app 15368, resolved review threads, and no bypass actors, force pushes or branch deletion. It requires zero additional human approvals, so a solo owner can use the PR workflow. The setup has 12 mocked failure-path tests and independent source review, but those do not substitute for successful GitHub policy readback. Apply it using suitable Administration access and verify the effective rules on `main` before claiming GitHub will prevent a merge. A failed, cancelled, skipped, or missing aggregate remains a failed QA result regardless of the current repository permission limitation.

## Event coverage

| Event | Scope | Feature-map mode |
| --- | --- | --- |
| Push | Every branch and tag; no path exclusions | Development, except `main` uses full |
| Pull request | Synthetic merge revision, with the PR's exact head recorded separately | Development |
| Merge queue (`merge_group`) | GitHub's merge-group revision | Full |
| Push to `main` | Actual new `main` commit after a merge or direct push | Full |
| Daily schedule | Default branch, 06:17 UTC / 03:17 São Paulo | Full |
| Manual workflow dispatch | Selected ref's exact revision | Full |

Every event/ref/revision has a separate concurrency group and `cancel-in-progress` is false. A push does not cancel the pull request's check, and a later revision does not discard an earlier revision's validation. The workflow uses `github.sha` for checkout; it does not run `pull_request_target`, use an untrusted scheduled ref, or consume repository-dispatch commands.

**Daily activation:** In `Zeus-native`, the native workflow is now on the actual default branch `main`, so the daily 06:17 UTC schedule is eligible to run. Its first scheduled execution has not yet been observed. The [initial main-push workflow](https://github.com/mysticalsin/Zeus-native/actions/runs/42731139415) started after the clean initial publication; workflow activation does not establish test success. The old private `Zeus` repository's feature-branch workflow did not activate daily native runs there.

## What each check proves

- `app`: Xcode 26.1.1 native build, a reviewed allowlist of synthetic native integration tests, and an ad-hoc preview bundle. Tests use injected permission ports, generated buffers, temporary files, and offscreen rendering. This job does not launch Zeus, request permission, capture any device, install an app, or access signing credentials. The preview is not a notarized distribution build.
- `extension`: locked dependency install, TypeScript checking, browser-target/consent regression tests, and production extension build.
- `release-scripts`: failure-path tests using mock packaging, signing, notarization, Gatekeeper, and installation tools. These verify script decisions and rollback behavior; they do not establish an actual release signature or notarization.
- `feature-map`: the machine-readable [19-item acceptance map](../qa/feature-map.json), regression registry, runner self-tests, and source-bound portable tests. Full mode also attempts safe native integration fixtures and requires every acceptance obligation, including device proof and release proof.

Development mode can pass while native/device obligations remain explicitly incomplete. **Full mode currently fails deliberately on unimplemented or unproved obligations.** Neither a passing subset nor a `release_ready` field can override a missing feature, missing test case, changed source package, or unimplemented checker. Completion requires an executable, reviewed verifier and its fresh passing evidence, not a manually edited green receipt or a manual click-through checklist.

The scheduled/main/merge-queue jobs therefore expose remaining work rather than silently declaring the product ready. A full failure must be repaired and rerun on the new revision. Do not weaken the map, remove an obligation, add `continue-on-error`, or bypass the aggregate to make a build green.

## Evidence and reproduction

Every job uploads diagnostics even after failure. Artifacts are named `zeus-check-app`, `zeus-check-extension`, `zeus-check-release-scripts`, `zeus-check-feature-map`, and `zeus-required-checks`. Check artifacts retain logs and JSON for 30 days; the separate ad-hoc app preview is retained for 14 days. Source packages retain the exact compiled copies/excerpts and their manifests, excluding build caches. Offscreen recording feedback renders, when produced by native tests, are synthetic visual regression artifacts, not recordings of the user's screen.

`tested_sha` identifies the checkout actually tested; `head_sha` identifies the PR source commit when applicable. Pull-request checks therefore report both the merge candidate and the authored head. The gate hashes logs and result files, validates exact job/check sets, checks positive test counts, rejects duplicate JSON keys and non-finite values, and re-evaluates feature obligations against the checked-in map and regression registry. Source manifests and reproducible portable packages bind results to current source bytes.

From a clean checkout, with Python 3 and Swift 6.2 available, use a new output directory outside the repository:

```sh
python3 qa/closed-loop/run.py --mode development --output /tmp/zeus-development-new
python3 -m unittest discover -s qa/closed-loop/tests -p 'test_*.py' -v
```

On macOS with the required SDK, full mode runs the safe native fixture suites too:

```sh
python3 qa/closed-loop/run.py --mode full --output /tmp/zeus-full-new
```

The runner refuses an existing output directory, records commands/exit codes/counts/source hashes, and fails if repository input changes while checks run. Full mode does not grant OS permissions or convert mocked/device-unavailable work into a pass. The historical private repository's native Actions jobs were prevented from starting by its Actions budget. The new public native repository has started its initial workflow; inspect that run's actual results and artifacts before asserting native build/test success. No result from the old repository is reused as proof for the new root commit.

## Turning caught failures into guards

Add each reproduced failure to [`qa/regressions.json`](../qa/regressions.json) with its feature IDs, executable checker, and an actual uniquely named test function. Repair the production behavior and run the guard. The schema rejects missing functions, helper functions masquerading as tests, ambiguous case names, unsafe command kinds, and stale sources. The runner verifies that the named case actually passed in the relevant compiled package; a source reference or a positive count alone is insufficient.

Changes to this workflow, the gate, the acceptance map, or the verifier are security-sensitive review points: code in a pull request cannot independently prove that its own merge policy is untampered. Protect those paths and review policy changes when repository permissions permit. GitHub protection and independent review remain separate from the YAML's fail-closed behavior.
