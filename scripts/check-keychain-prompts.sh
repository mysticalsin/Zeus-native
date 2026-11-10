#!/bin/bash
# Acceptance for "no Keychain password prompts, ever": rebuild + re-sign + launch the Keychain
# self-test N times (default 3) and fail if any run raises a SecurityAgent dialog or loses access.
# Never prints secret values; the self-test reports account names only.
set -uo pipefail
cd "$(dirname "$0")/.."
RUNS="${RUNS:-3}"
LOG="${LOG:-../topbar-proof/keychain-check.log}"
fail=0
echo "keychain check $(date '+%F %T %Z') runs=$RUNS" | tee "$LOG"
for i in $(seq 1 "$RUNS"); do
  since="$(date '+%Y-%m-%d %H:%M:%S')"
  touch Sources/Zeus/App/KeychainSelfTest.swift
  if ! nice -n 10 scripts/bundle.sh > "../topbar-proof/keychain-bundle-$i.log" 2>&1; then echo "run $i: bundle failed" | tee -a "$LOG"; fail=1; continue; fi
  authority="$(codesign -dvv build/Zeus.app 2>&1 | awk -F= '/^Authority/{print $2; exit}')"
  cdhash="$(codesign -dvvv build/Zeus.app 2>&1 | awk -F= '/^CDHash=/{print substr($2,1,12)}')"
  out="$(build/Zeus.app/Contents/MacOS/Zeus --keychain-selftest --require-keys 2>/dev/null)"; code=$?
  # Count only prompts securityd raised for this worktree's build (other sessions' tests on this
  # Mac can raise their own SecurityAgent dialogs; those are logged separately as "other").
  here="$(pwd)/build/Zeus.app"
  lines="$(/usr/bin/log show --style compact --start "$since" --predicate 'process == "securityd" AND eventMessage CONTAINS "displaying keychain prompt for"' 2>/dev/null | grep -o 'prompt for [^;]*')"
  prompts="$(printf '%s\n' "$lines" | grep -c "$here")"
  other="$(printf '%s\n' "$lines" | grep -v "$here" | grep -c 'prompt for')"
  agent="ours=$prompts other=$other"
  echo "run $i: signed='$authority' cdhash=$cdhash exit=$code prompts($agent) report=$out" | tee -a "$LOG"
  [ "$code" = 0 ] && [ "$prompts" = 0 ] || fail=1
done
echo "result: $([ $fail = 0 ] && echo PASS zero prompts || echo FAIL)" | tee -a "$LOG"
exit $fail
