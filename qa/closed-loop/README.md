# Zeus closed-loop checks

This is an executable gate for the **19 requested checklist items** (Friday 13 +
Sunday 6). It is not a claim to enumerate every feature of Zeus. The finite matrix
is [feature-map.json](../feature-map.json); its strict validator is `contracts.py`.
Every item retains required contract, native integration and device proof
obligations. An implemented button, a unit-test count or an old receipt cannot
satisfy the latter two tiers.

Run from the repository root, with Python 3.11+ and Swift 6 on `PATH`:

```sh
python3 -m unittest discover -s qa/closed-loop/tests -p 'test_*.py' -v
python3 qa/closed-loop/run.py --mode development --output /tmp/zeus-development-NEW
python3 qa/closed-loop/run.py --mode full --output /tmp/zeus-full-NEW
```

Output directories must be new. The runner never overwrites evidence, installs
Zeus, requests permission, captures media, opens a personal vault or signs a
release. Tests use generated values, injected ports and temporary fixture files.
The selected native logo tests render their own views offscreen; they do not
capture the desktop. No manual clickthrough can change a gate result.

`development` runs the gate's own rejection tests, **every default portable
group**, and the mocked release-script tests. It can pass while all 19 complete
features remain incomplete. This standalone command defers native fixtures;
GitHub's separate `app` job and aggregate still require every mapped native
fixture/guard to execute, even for a development PR. `full` runs those plus the individually named native
fixture suites on macOS and evaluates **every obligation**. On Linux the native
checks are `blocked`. An unavailable device/signing/temporal acceptance runner is
`unimplemented`, never a passing placeholder. **Full mode currently must fail**:
the feature map records substantial acceptance work still missing. There is no
`--allow-missing`, arbitrary imported-pass receipt or manual approval override.

Native fixture tests execute actual platform app/core modules but often inject
hardware boundaries. Their successful execution still does not prove native UI
journeys, OS consent transitions, hardware capture, voice quality, reference
motion parity, MCP delivery or a distributable signed artifact. Future device
checkers must actually execute a reproducible acceptance protocol with artifacts;
changing a status string cannot implement one.

Full mode on macOS first compiles the native test target once with
`swift build --build-tests`. A failed compiler barrier records its exact source
hash and compiler log; every native fixture is `blocked` by that failure, and no
native test command runs. After verified current-source compilation, each mapped
suite executes independently with `swift test --skip-build --filter ...`.
One suite's runtime failure remains `failed` while later suites still run. A
missing, changed or unsuccessful compiler receipt cannot authorize `--skip-build`.
This optimization does not remove any native obligation or change full-mode failure.

## Evidence and rejection rules

`result.json` records actual git `tested_sha`, separately supplied PR `head_sha`,
dirty state, a SHA-256 snapshot of repository files, exact argv, exit code, named
passed cases, test counts, statuses and relative artifact paths with hashes.
`source-manifest.json` includes tracked/untracked nonignored build/check input files:
all Sources/resources, Tests, manifests, scripts, workflows, extension inputs and
QA code/policy. It excludes the chosen output directory, Python bytecode,
`docs/`, root Markdown handoffs, QA Markdown reports and `qa/receipts/` (archived
evidence cannot hash itself). A code/configuration change or
checkout change during execution fails the run. CI's `ZEUS_TESTED_SHA` must match
the actual checkout; PR merge SHA is not mislabeled as PR head SHA.

Each portable package is freshly copied from actual source. After executing it,
the runner regenerates the recipe independently and compares every source/test,
excerpt, compatibility file, package manifest and validation manifest byte.
Missing entries, stale source, wrong excerpt boundaries and edited generated
sources fail. Linux's geometry import reexport remains explicitly labeled; the
production package manifest/platform requirements are untouched.

Cross-job verification regenerates for the recorded `linux` or `darwin` platform
and normalizes only the checkout-directory field in the validation manifest.
Every compiled byte, source hash and other field still compares. Native render
fixtures receive `ZEUS_QA_ARTIFACT_DIR` inside their fresh output folder; all
generated frames, GIFs and metadata receive artifact hashes in the result.

A successful command with no Swift Testing summary, zero tests, missing named
case, failing diagnostic, timeout, unavailable tool or omitted compiled source
cannot pass. Source-level test existence is validated **and** the named guard
must appear in that run's passed-case log. Unsupported checks retain their
reason. `summary.md` lists every unmet obligation. `result.schema.json` documents
the wire format; the stdlib validator additionally enforces cross-references and
semantics that JSON Schema alone cannot express.

The workflow's stable `required-checks` job is an additional aggregate: every
expected job must have succeeded, have matching current-run receipts, actual
positive test output and intact artifacts. A missing, skipped, timed-out,
cancelled, budget-blocked or failing job is red. Configure repository branch
protection to require this exact check; workflow YAML alone cannot configure
GitHub branch protection. See `gate.py` and its regression tests.

## Regression loop

[regressions.json](../regressions.json) binds each recorded caught failure to a
real production-path guard and feature IDs. Removed or unexecuted required guards
fail validation. Newly failing checks create `regression-candidates.json` with
the exact source snapshot, command and artifact hashes. The failure stays red.
Repair work must reproduce the problem and add a test/type/lint guard to the
registry before declaring it resolved. Candidate generation does **not** invent
a test or automatically assert a fix; a new behavioral guard still requires code.
Native guards remain deferred in development and mandatory in full mode.

To extend coverage, add real fixtures first, update the portable recipe or safe
native suite selector, bind specific cases to precise obligations, and run the
rejection tests. Keep remaining device obligations explicit. Do not delete a
checklist item, remove a tier, substitute a related unit count for an integration
assertion, or import historical evidence as a fresh pass.
