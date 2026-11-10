# 10 November automated-check receipts

See [summary.json](summary.json) and the [readiness record](../../../readiness-20261110.md). The development command passed; full mode deliberately failed missing native/device obligations. Source SHA plus dirty input snapshot are recorded.

These are compact audit receipts: raw logs, source/excerpt manifests and result JSON. Compiled-source package copies and .build directories are omitted to avoid duplicating the repository. This directory is not accepted as a fresh gate input; rerun the documented command. Full original packages are retained at the output paths in summary.json, and the CI artifact contract preserves package source inputs for independent verification.

The source-change-rejected receipt demonstrates a real stale-input rejection despite passing tests; it has no reusable success status. No native, device, capture or signing acceptance is implied.
