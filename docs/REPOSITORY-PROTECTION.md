# Enforce the required GitHub check

The repository owner authorized failure-blocking PR checks. The workflow is active in the public `mysticalsin/Zeus-native` repository, but this session’s GitHub integration returned HTTP 403 for both ruleset creation and classic branch-protection access. A displayed ADMIN repository role does not grant the integration the Administration write permission. Server enforcement has not been claimed or enabled by the workflow itself.

The reviewed [ruleset payload](../qa/github/main-ruleset.json) requires a PR and current `required-checks` success from GitHub Actions. It disallows bypass actors, force pushes and branch deletion, with no added human-approval count. It targets only `Zeus-native/main`; it does not change the original private repository.

Once authenticated as the owner with repository Administration write access, apply the exact payload from this checkout:

```sh
gh api --method POST repos/mysticalsin/Zeus-native/rulesets --input qa/github/main-ruleset.json
gh api repos/mysticalsin/Zeus-native/rules/branches/main
```

Inspect existing rulesets first if another administrator has configured protection in the meantime. Do not repeatedly POST duplicate rulesets. The effective branch response must contain the expected required check and restrictions before describing enforcement as active. The same policy can be imported through GitHub’s repository Settings → Rules → Rulesets.

No token or signing credential should be placed in this file, a command argument, chat, or source control. The prepared policy and its failed API request are separate from successful app validation; both enforcement and actual feature acceptance are required.
