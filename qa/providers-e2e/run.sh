#!/bin/sh
# Fake voice-provider journeys, one command. No real keys.
# Live contracts are a separate invocation and read keys from the environment only.
#
#   qa/providers-e2e/run.sh
#   qa/providers-e2e/run.sh selftest
#   ZEUS_LIVE_ELEVENLABS_KEY='…' qa/providers-e2e/run.sh live
#   ZEUS_LIVE_GOOGLE_TTS_KEY='…' qa/providers-e2e/run.sh live
#
# Output: $ZEUS_E2E_OUT or $TMPDIR/zeus-e2e/providers/<sha8>/
#   summary.json  junit.xml  swift-test.log  latency.txt  screenshots/<journey>.png
set -eu
here=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
root=$(CDPATH= cd -- "$here/../.." && pwd)
cd "$root"
mode=${1:-run}
case "$mode" in
    selftest) exec python3 "$here/report.py" selftest ;;
    run|live) ;;
    *) echo "usage: qa/providers-e2e/run.sh [run|live|selftest]" >&2; exit 64 ;;
esac
python3 "$here/report.py" selftest
if [ "$mode" = "live" ]; then
    exec python3 "$here/report.py" live
fi
exec python3 "$here/report.py" run
