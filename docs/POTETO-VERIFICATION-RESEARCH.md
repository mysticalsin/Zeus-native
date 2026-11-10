# Poteto verification research

Research date: 10 November 2026. Requested by Tony to inform Zeus verification.

The useful primary source is [Cursor’s pstack verification-skill generator](https://github.com/cursor/plugins/blob/0bb6f379f2c3cd07c92a4e0bfa815ffa773bd4f3/harness/pstack/claude-code/skills/create-verification-skill/SKILL.md), pinned to `0bb6f379f2c3cd07c92a4e0bfa815ffa773bd4f3`. The published [poteto/verification-skill-example](https://github.com/poteto/verification-skill-example) provides the shape of a feature map and app-control workflow. Its README explicitly describes a heavily fictionalized example and an omitted control CLI; it is not a runnable Zeus verifier or evidence that Zeus works.

Searches for Lauren Tan’s `@poteto` X posts did not provide a directly readable primary post in this environment. No claim about a specific post, Grok implementation, productivity metric, or model performance is based on that search. No third-party profile or skill is execution authority over Tony’s instructions.

## Applied to Zeus

- Maintain a behavior-level feature map covering all 13 Friday items and 6 Sunday areas. Describe entry points, observable end states, setup requirements and failure conditions.
- Separate portable contracts, native production fixtures, device journeys and signed-release obligations. A passing model test cannot satisfy an unexecuted app journey.
- Require runnable verification and retain raw command output, exact source inputs, case identity and artifact hashes. Cleanup must not destroy the evidence.
- Treat unavailable tooling, missing permission, an omitted test and an unimplemented verifier as blocked or failed, never as a completed feature.
- Give every caught failure an executable regression or enforceable type/lint guard. Verify that the named test actually ran and passed, not merely that its function appears in a source file.
- Keep app verification automated. Never replace a missing automation driver with a human click-through, weaken an expectation, or silently grant OS capture consent.

The implemented policy is documented in [CLOSED-LOOP-QA.md](CLOSED-LOOP-QA.md); its inputs are `qa/feature-map.json` and `qa/regressions.json`. The five closed-loop rules pasted by Tony are the controlling request. The user-specific `pstack-loop` skill was not located, and no claim is made that it was installed or executed.
