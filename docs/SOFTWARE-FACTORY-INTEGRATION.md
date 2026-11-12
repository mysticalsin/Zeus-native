# Software Factory integration for native Zeus

The user selected `mysticalsin/software-factory` as a development reference.
Zeus pins commit `9e53e4aedec5706e13c6d336482c3035e67f1c7b` in
[`qa/software-factory-reference.json`](../qa/software-factory-reference.json).
No upstream implementation or assets are copied into this integration.

The upstream README calls its code a TOTO OS snapshot dependent on the absent
`toto_brain` runtime, not a standalone package. The pinned tree has no LICENSE,
COPYING or AGENTS.md file. This adaptation uses its verification principles and
documented command interface; it does not claim factory enrollment, access to a
private Obsidian cockpit, a redistribution license, or an automatic deployer.

## Concrete integration

`tools/check.sh` is an original adapter for the upstream documented command
`./tools/check.sh`. With no arguments it runs development checks, creates a fresh
external temporary parent, and prints the retained evidence path. The runner
creates a still-absent result directory inside that parent. Explicit
`development`, `full` or `--mode full` and a custom fresh output directory are
also supported. It validates arguments, then executes Zeus's
existing `qa/closed-loop/run.py` unchanged. Exit codes and evidence requirements
are preserved. No capture, install, signing, publishing or consent action is
added. Relative output paths remain relative to the caller's working directory;
the runner itself is resolved relative to the wrapper's checkout.

```sh
./tools/check.sh
./tools/check.sh development --output /tmp/zeus-development-NEW --jobs 4
./tools/check.sh --mode full --output /tmp/zeus-full-NEW --timeout 1800
```

The wrapper's synthetic tests join the existing gate-selftest suite. They check
zero-argument direct/bash invocation, argument and working-directory forwarding,
literal paths, full-mode failure
propagation, fresh external output, and rejection of unknown/duplicate flags or
a second mode. They use a mock runner in a temporary checkout, so testing the
adapter does not recursively rerun CI.

`AGENTS.md` connects the selected workflow to the native code, current feature
map, design principles, privacy rules and actual UI journeys. The upstream's
three-role plan debate and independent verifier are useful review practices;
actual model availability and review execution must be reported truthfully.

## Keep Zeus's stronger proof boundary

Upstream `process.check_gate` validates logged phases, model labels and verdict
tokens. Zeus additionally binds executed named guards and artifacts to the
current source snapshot. Those executable receipts remain authoritative here;
an upstream phase note cannot make a missing native/device obligation pass.

The upstream app audit is not Swift-aware: its test-path regex misses `Tests/`
and its test-command discovery omits Package.swift. Its declared `TEST_CMDS`
list includes `./tools/check.sh` but is unused in the pinned code; actual agent
phases allow Bash under a sandbox/deny list, so Swift is not explicitly denied
by that unused list. The app audit recognizes this script by file existence and
does not bind configured arguments; the zero-argument command is therefore usable
without an upstream change. This adapter solves the command entrypoint mismatch only. Do not add
dummy tests or claim unattended factory eligibility to hide the other gaps.

The reference's merge/deploy code records accepted shipping marks and requires
rollback text. Its README explicitly calls future agent-run merge/deploy work
unfinished. Zeus's release scripts and the user's actual authorization still
govern release actions; no upstream installer or deployment recipe was run.

## Design and real UI testing

[`docs/DESIGN-DIRECTION.md`](DESIGN-DIRECTION.md) remains the canonical map for
all ten requested references. Each meaningful design change must link to the
existing 19-item feature map and prove the affected native flow. Current
controller tests, geometry tests and offscreen renders retain their narrower
scope. They do not establish actual keyboard/pointer journeys, OS consent or
reference-motion parity.

The next bounded improvement is own-process production-control testing of
onboarding and Memory's Graph/List/query/filter/navigation flows, with synthetic
records and isolated stores. Evidence should record the actual actions, state
assertions, accessibility/focus behavior and relevant temporal frames. No
private-vault or capture dependency is needed for these first journeys. New
machine-readable design coverage should extend the existing gate, with explicit
missing evidence, after the native compile checkpoint; this integration creates
no second readiness framework or new website.
