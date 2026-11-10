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
GitHub's separate `app` job and aggregate still require every Core test and every
mapped app fixture/guard to execute, even for a development PR. `full` runs the
complete `ZeusCoreTests` module plus the individually named app fixture suites on
macOS and evaluates **every obligation**. On Linux the native
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

Both full mode on macOS and the CI app entrypoint first compile the native test
target once with `swift build --build-tests`, then save compiled discovery once.
A failed compiler barrier records its exact source hash and compiler log; every
native fixture is `blocked` by that failure, and no native test command runs.
After verified current-source compilation and discovery, each mapped native check
executes in its own process using `swift test --skip-build --filter ...`. The CI
app entrypoint runs the complete Core module first, followed sequentially by one
process for each explicitly mapped App suite in map order.
This keeps process-global UI fixture state isolated between App suites. One
process's runtime failure remains `failed` while later suites still run; any
failed or incomplete required process fails the app result. A missing, changed or
unsuccessful compiler/discovery receipt cannot authorize `--skip-build`. Every
mapped obligation remains required, including both AX and event journey suites.

The audited native selection is **all Core tests plus 25 explicitly mapped app suites**.
Three former narrow Core selections are subsumed by the module; their named
obligations and regression bindings remain mandatory. The compiler's discovery
stream must include every current Core `@Test` declaration. A source inventory is
only a completeness check and is never reported as executed coverage.

`native.py --output NEW --jobs 4` is the CI app entrypoint. It builds the test
target, saves compiler discovery, then runs that exact native selection in the
separate sequential processes described above. `--jobs` controls Swift build
jobs, not concurrent fixture processes. Both
discovery and execution request Swift Testing **wire version 0**. Each selected
qualified ID must match its current file, function and `@Test` location, start,
and finish with a pass. Swift Testing lists functions without expanding their
argument collections and may omit implicit suites. Execution must declare a
nonempty parameter-case plan before `runStarted`; every planned argument ID must
then start and finish. Implicit suites are authorized only by the containers of
selected compiler-discovered functions. Every process must exit zero and contain
its own complete terminal `runEnded` event. Skips, issues, missing/duplicate events,
unknown protocol versions or unselected suite execution fail even when the human
summary reports success.
Apple Testing 1400 discovery from commit `df3dcc3` was validated against that
exact source snapshot, including unexpanded parameters and implicit suites.
The complete argument lifecycle was additionally probed with Linux Swift 6.2.1.
At `dd19cb5`, actual Apple Testing 1400 execution produced complete independently
validated evidence for 18 separate App suites and 147 tests; all 22 selected
processes were attempted. Core and three UI suites failed, so the aggregate and
a complete passing Core/parameterized receipt remain unproved. The same-source
push compiler internal error also remained blocking despite exit zero. See the
[dd19 receipt](../receipts/20261110/mac-dd19-ci.json). An unsupported protocol
variant remains a failed gate until its actual evidence is reviewed.

The CI app stores `native-evidence/result.json`, a source manifest, compiler log,
discovery log/events and per-process execution log/events. Its version 2 receipt
contains ordered `native_runs` rows under their mapped check IDs and a
`native_summary` with recomputed `tests`, `suites`, `parameter_cases` and
`passed_cases`. The aggregate verifies the exact required partition set and
order, every process's hashed evidence, and the disjoint qualified case union
with `native_evidence.py`; neither console totals nor the summary alone can
substitute for execution. Legacy version 1 combined-run receipts are rejected.
Native case bindings use qualified file/function identities rather than
borrowing a same-named pass from another file. `native-result.schema.json`
documents this app receipt; the feature-map receipt remains version 1.

## Evidence and rejection rules

The separate mandatory extension job runs every Node test and emits TAP. Its
[session regression registry](../extension-regressions.json) binds named guards
to current source declarations and exactly one passing result each. The aggregate
also requires its hashed npm audit JSON, including development dependencies, with
no moderate, high or critical findings. Missing names, mismatched totals and an
absent or unsuccessful audit fail the gate. This is synthetic browser-boundary
evidence; it does not satisfy native Swift or real-browser device obligations.

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
