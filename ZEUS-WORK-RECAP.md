# Zeus native work recap

This is a clean source snapshot of the native macOS Zeus project. It contains no Git objects or history from the original repository. Private handoffs and source-delivery briefs are excluded; production source, tests and third-party notices are retained.

Read `docs/ZEUS-READINESS-PLAN.md`, `docs/CLOSED-LOOP-QA.md`, `qa/feature-map.json` and the current `qa/readiness-*.md` receipts before making completion claims. All 13 feature items and 6 rerun areas remain explicit obligations. A portable test or screenshot does not establish native behavior, motion parity, capture privacy or a signed release.

Checks must run on every push, failures must block PRs, and the full map must run on native main and daily. Every caught failure needs an executable guard. Verification is automated, never a manual app click-through. No microphone, screen or system-audio capture without the owner’s own OS consent; no private vault access; preserve rollback before installation; never force-push.

The application is under development and is not certified ready to sell.
