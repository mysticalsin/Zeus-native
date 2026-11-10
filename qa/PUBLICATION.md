# Clean native source publication

The owner explicitly authorized a new public `mysticalsin/Zeus-native` repository. This snapshot is derived from native checkpoint `f06e92c8` in the original private Zeus repository. No original Git objects, branches, tags or history are imported.

Personal handoff and design delivery briefs are excluded; generic work-recap/persona documents replace the private originals. Two personal home-path literals in source comments/demo data are neutralized. Production resources, source, tests and third-party notices are retained.

The final snapshot was scanned using official Gitleaks 8.30.1 with its default rules and suppression comments disabled. The official Linux archive was verified against its published SHA-256 (`551f6fc83ea457d62a0d98237cbad105af8d557003051f41f3e7ca7b3f2470eb`). Three findings were reviewed: two Keychain test identifier/fixture matches and the Chrome extension public key. No operational credential was detected in this snapshot. This is bounded scan evidence, not a claim that every possible secret format or binary payload can be detected. Private history reports are not included.

Archived Linux receipts describe the exact pre-publication inputs they tested. They are not current native CI passes: source sanitization and this new Git history have different identities. Every public push must obtain new source-bound checks. Signing, notarization, Gatekeeper, real user journeys and reference motion still need their own evidence.
